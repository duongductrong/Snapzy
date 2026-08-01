//
//  OCRScriptCoverage.swift
//  Snapzy
//
//  Script coverage analysis for PP-OCR character dictionaries.
//

import Foundation

/// A writing system probed against a recognition dictionary.
///
/// A PP-OCR recognizer can only ever emit characters that appear in its
/// `dict.txt`: the CTC head has exactly one class per dictionary line. Anything
/// outside that set is not rejected — the model emits the nearest glyph it does
/// know. That makes an incomplete dictionary look like an accuracy problem
/// rather than a capability one, which is what this analysis exists to expose.
///
/// The catalog's PP-OCRv6 dictionaries are the motivating case: they omit
/// almost all of the Vietnamese precomposed tone block (U+1EA0–U+1EF9), so
/// "Kết luận" comes back as "Kêt luân" with no error anywhere in the pipeline.
///
/// Cases are declared in display order.
enum OCRScript: String, CaseIterable, Sendable {
  case latin
  case vietnamese
  case chinese
  case japanese
  case korean
  case cyrillic
  case arabic
  case thai
  case devanagari
}

extension OCRScript {
  /// Representative characters for the script; coverage is the fraction of
  /// these the dictionary can emit.
  ///
  /// Vietnamese is probed with its full tone inventory rather than a sample,
  /// because the tone marks are precisely what the PP-OCRv6 dictionaries drop.
  /// Latin folds in the accented European letters, which every dictionary that
  /// carries basic Latin has so far also carried.
  static let probes: [OCRScript: Set<Character>] = probeTexts.mapValues(Set.init)

  private static let probeTexts: [OCRScript: String] = [
    .latin: """
      ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,:;!?'"()-\
      àáâäãåèéêëìíîïòóôöõùúûüçñýÀÁÂÄÃÈÉÊËÌÍÎÏÒÓÔÖÕÙÚÛÜÇÑ
      """,
    .vietnamese: """
      ăâêôơưđĂÂÊÔƠƯĐàáảãạằắẳẵặầấẩẫậèéẻẽẹềếểễệìíỉĩị\
      òóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ
      """,
    .chinese: """
      的一是在不了有和人这中大为上个国我以要他时来用们生到作地于出就分对成会\
      可主发年动同工也能下过子说产种面而方后多定行学法所民得经十三之进着等部\
      度家电力里如水化高自二理起小物现实加量都两体制机当使点从业本去把性好应\
      开它合还因由其些然前外天政四日那社义事平形相全表间样与关各重新线内数正\
      心反你明看原又么利比或但质气第向道命此变条只没结解问意建月公无系军很情\
      者最立代想已通并提直题党程展五果料象员革位入常文总次品式活设及管特件长
      """,
    .japanese: """
      あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめも\
      やゆよらりるれろわをんアイウエオカキクケコサシスセソタチツテトナニヌネ\
      ノハヒフヘホマミムメモヤユヨラリルレロワヲン
      """,
    .korean: "가나다라마바사아자차카타파하한국어글씨안녕세요",
    .cyrillic: """
      абвгдеёжзийклмнопрстуфхцчшщъыьэюя\
      АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЫЭЮЯ
      """,
    .arabic: "ابتثجحخدذرزسشصضطظعغفقكلمنهوي",
    .thai: "กขคฅฆงจฉชซญฎฏฐฑฒณดตถทธนบปผฝพฟภมยรลวศษสหอฮ",
    .devanagari: "अआइईउऊएऐओऔकखगघङचछजझञटठडढणतथदधनपफबभमयरलवशषसह",
  ]
}

/// How completely a dictionary can spell a script.
enum OCRScriptSupport: Sendable, Equatable {
  /// Effectively the whole probe set is present.
  case full
  /// Part of the probe set is missing. This is the failure mode users actually
  /// hit: the output reads almost right, with the unrepresentable characters
  /// quietly swapped for their closest in-dictionary neighbour.
  case partial
  /// The script is not represented at all.
  case unsupported
}

/// Per-script coverage of one recognition dictionary.
struct OCRScriptCoverageReport: Sendable, Equatable {
  /// Fraction of each script's probe set present in the dictionary, 0...1.
  let coverage: [OCRScript: Double]
  /// Number of character classes in the dictionary.
  let characterCount: Int

  /// At or above this fraction a script counts as fully spellable. Not 1.0:
  /// probe sets carry a few characters (typographic quotes, rare letters) that
  /// a perfectly usable dictionary may still omit.
  static let fullThreshold = 0.98
  /// Below this fraction the script is absent rather than merely incomplete.
  static let unsupportedThreshold = 0.05

  static func analyze(dictionary: [String]) -> OCRScriptCoverageReport {
    var available: Set<Character> = []
    for entry in dictionary {
      for character in entry {
        available.insert(character)
      }
    }

    var coverage: [OCRScript: Double] = [:]
    for script in OCRScript.allCases {
      guard let probe = OCRScript.probes[script], !probe.isEmpty else { continue }
      coverage[script] = Double(probe.intersection(available).count) / Double(probe.count)
    }
    return OCRScriptCoverageReport(coverage: coverage, characterCount: dictionary.count)
  }

  func support(for script: OCRScript) -> OCRScriptSupport {
    let fraction = coverage[script] ?? 0
    if fraction >= Self.fullThreshold { return .full }
    if fraction >= Self.unsupportedThreshold { return .partial }
    return .unsupported
  }

  var fullySupported: [OCRScript] {
    OCRScript.allCases.filter { support(for: $0) == .full }
  }

  /// Scripts the model will silently mangle — the ones worth surfacing.
  var partiallySupported: [OCRScript] {
    OCRScript.allCases.filter { support(for: $0) == .partial }
  }
}
