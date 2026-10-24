//
//  AppNameMatcher.swift
//  Snapzy
//
//  How a user-typed app name selects windows for headless capture and
//  `snapzy list windows --app`: exact bundle ID, else exact name, else name
//  prefix — all case-insensitive. Only the best tier that matches is kept,
//  so "Code" never mixes VS Code with "Codex".
//

import Foundation

nonisolated enum AppNameMatcher {
  static func filter<Item>(
    _ items: [Item],
    query: String,
    name: (Item) -> String,
    bundleID: (Item) -> String?
  ) -> [Item] {
    let needle = query.trimmingCharacters(in: .whitespaces)
    guard !needle.isEmpty else { return [] }

    let tiers = items.map { tier(needle: needle, name: name($0), bundleID: bundleID($0)) }
    guard let best = tiers.compactMap({ $0 }).min() else { return [] }
    return zip(items, tiers).filter { $0.1 == best }.map(\.0)
  }

  /// 0 = bundle ID, 1 = exact name, 2 = name prefix, `nil` = no match.
  private static func tier(needle: String, name: String, bundleID: String?) -> Int? {
    if bundleID?.caseInsensitiveCompare(needle) == .orderedSame { return 0 }
    if name.caseInsensitiveCompare(needle) == .orderedSame { return 1 }
    if name.range(of: needle, options: [.caseInsensitive, .anchored]) != nil { return 2 }
    return nil
  }
}
