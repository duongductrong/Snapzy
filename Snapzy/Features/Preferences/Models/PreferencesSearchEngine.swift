//
//  PreferencesSearchEngine.swift
//  Snapzy
//
//  Ranked, typo-tolerant search over Preferences pages and the settings inside them.
//
//  Text is folded (case, diacritics, width, đ → d) and split into words. Every query token must
//  match some field of an entry; each token takes its best tier (exact word > word prefix >
//  initials > in-word abbreviation > substring > typo) scaled by the field's weight, and the
//  entry scores the mean over tokens plus small bonuses for title-only and phrase-prefix hits.
//

import Foundation

// MARK: - Entry

struct PreferencesSearchEntry: Identifiable, Hashable {
  let tab: PreferencesTab
  let section: String?
  let title: String
  let detail: String?
  let keywords: [String]
  /// The row exists as a `SettingRow` whose title is its scroll anchor; otherwise the search
  /// only opens the page.
  let anchored: Bool
  /// The page itself rather than a setting inside it.
  let isPage: Bool
  /// Segment of a page that splits its rows behind a picker (Capture), which must be shown first.
  private(set) var pane: String?

  var id: String { isPage ? tab.rawValue : "\(tab.rawValue)/\(pane ?? "")/\(section ?? "")/\(title)" }

  init(
    _ tab: PreferencesTab,
    section: String?,
    title: String,
    detail: String? = nil,
    keywords: [String] = [],
    anchored: Bool = true
  ) {
    self.tab = tab
    self.section = section
    self.title = title
    self.detail = detail
    self.keywords = keywords
    self.anchored = anchored
    self.isPage = false
  }

  /// The page entry, searchable by its title and `searchKeywords`.
  init(page tab: PreferencesTab) {
    self.tab = tab
    self.section = nil
    self.title = tab.title
    self.detail = nil
    self.keywords = tab.searchKeywords
    self.anchored = false
    self.isPage = true
  }

  func inPane(_ pane: String) -> PreferencesSearchEntry {
    var entry = self
    entry.pane = pane
    return entry
  }
}

// MARK: - Result

struct PreferencesSearchResult: Identifiable {
  let entry: PreferencesSearchEntry
  let score: Double
  /// Matched spans of `entry.title`, for emphasis.
  let titleHighlights: [Range<String.Index>]

  var id: String { entry.id }
}

/// Results for one page: the page row followed by its matching settings.
struct PreferencesSearchGroup: Identifiable {
  let tab: PreferencesTab
  let pageResult: PreferencesSearchResult?
  let settings: [PreferencesSearchResult]

  var id: PreferencesTab { tab }
}

// MARK: - Engine

struct PreferencesSearchEngine {
  private let documents: [Document]

  /// Pages plus every catalogued setting.
  static func standard() -> PreferencesSearchEngine {
    PreferencesSearchEngine(
      entries: PreferencesTab.sidebarOrder.map { PreferencesSearchEntry(page: $0) }
        + PreferencesSearchEntry.catalog()
    )
  }

  init(entries: [PreferencesSearchEntry]) {
    documents = entries.enumerated().map { Document(entry: $1, order: $0) }
  }

  /// Matching entries, best first. Empty for a blank query.
  func search(_ query: String, limit: Int = 60) -> [PreferencesSearchResult] {
    let normalizedQuery = SearchText(query)
    let tokens = normalizedQuery.words.map { Array(normalizedQuery.chars[$0]) }
    guard !tokens.isEmpty else { return [] }

    let phrase = tokens.map { String($0) }.joined(separator: " ")
    var scored: [(result: PreferencesSearchResult, order: Int)] = []

    for document in documents {
      guard let match = document.match(tokens: tokens, phrase: phrase) else { continue }
      scored.append((match, document.order))
    }

    return scored
      .sorted { lhs, rhs in
        if lhs.result.score != rhs.result.score { return lhs.result.score > rhs.result.score }
        return lhs.order < rhs.order
      }
      .prefix(limit)
      .map(\.result)
  }

  /// Results grouped per page, pages ordered by their best hit.
  func groupedSearch(_ query: String) -> [PreferencesSearchGroup] {
    let results = search(query)
    var order: [PreferencesTab] = []
    var pages: [PreferencesTab: PreferencesSearchResult] = [:]
    var settings: [PreferencesTab: [PreferencesSearchResult]] = [:]

    for result in results {
      let tab = result.entry.tab
      if pages[tab] == nil && settings[tab] == nil { order.append(tab) }
      if result.entry.isPage {
        pages[tab] = result
      } else {
        settings[tab, default: []].append(result)
      }
    }

    return order.map {
      PreferencesSearchGroup(tab: $0, pageResult: pages[$0], settings: settings[$0] ?? [])
    }
  }
}

// MARK: - Scoring

extension PreferencesSearchEngine {
  enum Weight {
    static let title = 1.0
    static let section = 0.7
    static let keyword = 0.6
    static let detail = 0.35
    /// Below this an entry is noise (e.g. a mid-word hit buried in a description).
    static let threshold = 0.2
  }

  enum Tier {
    static let exact = 1.0
    static let prefix = 0.9
    static let initials = 0.8
    static let abbreviation = 0.6
    static let substring = 0.5
    /// Substring inside CJK text, which has no word breaks to prefix-match against.
    static let ideographicSubstring = 0.9
    static let typo = 0.45
  }

  fileprivate struct TokenMatch {
    var score: Double
    var spans: [Range<Int>]
  }

  fileprivate struct Document {
    let entry: PreferencesSearchEntry
    let order: Int
    let title: SearchText
    let section: SearchText?
    let detail: SearchText?
    let keywords: [SearchText]

    init(entry: PreferencesSearchEntry, order: Int) {
      self.entry = entry
      self.order = order
      title = SearchText(entry.title)
      section = entry.section.map(SearchText.init)
      detail = entry.detail.map(SearchText.init)
      keywords = entry.keywords.map(SearchText.init)
    }

    func match(tokens: [[Character]], phrase: String) -> PreferencesSearchResult? {
      var total = 0.0
      var allInTitle = true
      var spans: [Range<Int>] = []

      for token in tokens {
        var best = 0.0
        if let hit = title.bestMatch(for: token) {
          best = hit.score * Weight.title
          spans += hit.spans
        } else {
          allInTitle = false
        }
        if let section, let hit = section.bestMatch(for: token) {
          best = max(best, hit.score * Weight.section)
        }
        for keyword in keywords {
          if let hit = keyword.bestMatch(for: token) {
            best = max(best, hit.score * Weight.keyword)
          }
        }
        if let detail, let hit = detail.bestMatch(for: token) {
          best = max(best, hit.score * Weight.detail)
        }
        guard best > 0 else { return nil }
        total += best
      }

      var score = total / Double(tokens.count)
      if allInTitle { score += 0.1 }
      if title.folded.hasPrefix(phrase) { score += 0.15 }
      if entry.isPage { score += 0.05 }
      guard score >= Weight.threshold else { return nil }

      return PreferencesSearchResult(
        entry: entry,
        score: score,
        titleHighlights: title.originalRanges(for: spans)
      )
    }
  }
}

// MARK: - Normalized Text

/// Folded characters of a string, with word boundaries and a map back to the original.
fileprivate struct SearchText {
  let chars: [Character]
  /// `origins[i]` is the original character range that produced `chars[i]`.
  let origins: [Range<String.Index>]
  let words: [Range<Int>]
  let folded: String

  init(_ text: String) {
    var chars: [Character] = []
    var origins: [Range<String.Index>] = []
    var index = text.startIndex

    while index < text.endIndex {
      let next = text.index(after: index)
      for character in Self.fold(text[index]) {
        chars.append(character)
        origins.append(index..<next)
      }
      index = next
    }

    var words: [Range<Int>] = []
    var start: Int?
    for (offset, character) in chars.enumerated() {
      let isWordCharacter = character.isLetter || character.isNumber
      if isWordCharacter, start == nil {
        start = offset
      } else if !isWordCharacter, let wordStart = start {
        words.append(wordStart..<offset)
        start = nil
      }
    }
    if let start { words.append(start..<chars.count) }

    self.chars = chars
    self.origins = origins
    self.words = words
    self.folded = words.map { String(chars[$0]) }.joined(separator: " ")
  }

  private static func fold(_ character: Character) -> String {
    let folded = String(character).folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: nil
    )
    // Vietnamese đ is a distinct letter, not d plus a diacritic, so folding keeps it.
    return folded == "đ" ? "d" : folded
  }

  func originalRanges(for spans: [Range<Int>]) -> [Range<String.Index>] {
    let covered = Set(spans.flatMap { $0 }).sorted()
    var ranges: [Range<String.Index>] = []
    for offset in covered {
      let origin = origins[offset]
      if let last = ranges.last, last.upperBound >= origin.lowerBound {
        ranges[ranges.count - 1] = last.lowerBound..<max(last.upperBound, origin.upperBound)
      } else {
        ranges.append(origin)
      }
    }
    return ranges
  }

  // MARK: Matching

  func bestMatch(for token: [Character]) -> PreferencesSearchEngine.TokenMatch? {
    typealias Tier = PreferencesSearchEngine.Tier
    var best: PreferencesSearchEngine.TokenMatch?

    func consider(_ score: Double, _ spans: [Range<Int>]) {
      if score > (best?.score ?? 0) { best = .init(score: score, spans: spans) }
    }

    for word in words {
      let wordChars = chars[word]
      if wordChars.elementsEqual(token) {
        consider(Tier.exact, [word])
        return best
      }
      if wordChars.starts(with: token) {
        // Longer prefixes are more specific: "scree" beats "s" against "screenshot".
        let coverage = Double(token.count) / Double(wordChars.count)
        consider(Tier.prefix - 0.1 * (1 - coverage), [word.lowerBound..<word.lowerBound + token.count])
      }
    }

    if token.count >= 2, let spans = initialsMatch(token) {
      consider(Tier.initials, spans)
    }

    if token.count >= 2 {
      for word in words where chars[word.lowerBound] == token[0] {
        if let spans = subsequence(token, in: word) {
          consider(Tier.abbreviation, spans)
        }
      }
    }

    // Mid-word hits of one or two latin letters match nearly everything, so they need three.
    let isIdeographic = token.contains { $0.isIdeographicOrKana }
    if isIdeographic || token.count >= 3, let start = firstOccurrence(of: token) {
      consider(isIdeographic ? Tier.ideographicSubstring : Tier.substring, [start..<start + token.count])
    }

    if best == nil, token.count >= 4 {
      let allowed = token.count >= 8 ? 2 : 1
      for word in words where chars[word].count >= 3 {
        let wordChars = Array(chars[word])
        let prefix = Array(wordChars.prefix(token.count))
        let distance = min(
          PreferencesSearchEngine.editDistance(token, wordChars, limit: allowed),
          PreferencesSearchEngine.editDistance(token, prefix, limit: allowed)
        )
        if distance <= allowed {
          consider(Tier.typo - 0.1 * Double(distance - 1), [word])
        }
      }
    }

    return best
  }

  /// "qa" → the first letters of consecutive words "Quick Access".
  private func initialsMatch(_ token: [Character]) -> [Range<Int>]? {
    guard words.count >= token.count else { return nil }
    for start in 0...(words.count - token.count) {
      let run = words[start..<start + token.count]
      if zip(run, token).allSatisfy({ chars[$0.lowerBound] == $1 }) {
        return run.map { $0.lowerBound..<$0.lowerBound + 1 }
      }
    }
    return nil
  }

  /// "fmt" → f, m, t in order within "format", anchored at the word start.
  private func subsequence(_ token: [Character], in word: Range<Int>) -> [Range<Int>]? {
    guard token.count < word.count else { return nil }
    var spans: [Range<Int>] = []
    var tokenIndex = 0
    for offset in word where tokenIndex < token.count && chars[offset] == token[tokenIndex] {
      spans.append(offset..<offset + 1)
      tokenIndex += 1
    }
    return tokenIndex == token.count ? spans : nil
  }

  private func firstOccurrence(of token: [Character]) -> Int? {
    guard token.count <= chars.count else { return nil }
    for start in 0...(chars.count - token.count)
    where chars[start..<start + token.count].elementsEqual(token) {
      return start
    }
    return nil
  }
}

// MARK: - Edit Distance

extension PreferencesSearchEngine {
  /// Optimal-string-alignment distance (Damerau-Levenshtein with adjacent transpositions),
  /// bailing out with `limit + 1` once every path exceeds `limit`.
  static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
    if abs(a.count - b.count) > limit { return limit + 1 }
    if a.isEmpty || b.isEmpty { return max(a.count, b.count) }

    var previousPrevious = [Int](repeating: 0, count: b.count + 1)
    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)

    for i in 1...a.count {
      current[0] = i
      var rowMinimum = current[0]
      for j in 1...b.count {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
        if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
          value = min(value, previousPrevious[j - 2] + 1)
        }
        current[j] = value
        rowMinimum = min(rowMinimum, value)
      }
      if rowMinimum > limit { return limit + 1 }
      (previousPrevious, previous, current) = (previous, current, previousPrevious)
    }
    return previous[b.count]
  }
}

private extension Character {
  var isIdeographicOrKana: Bool {
    unicodeScalars.contains {
      switch $0.value {
      case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF:
        return true
      default:
        return false
      }
    }
  }
}
