//
//  LifecycleXMLParser.swift
//  Snapzy
//
//  Minimal XML parser to extract <Rule> blocks from S3 lifecycle configuration responses
//

import Foundation

/// Parses S3/R2 `GetBucketLifecycleConfiguration` XML responses
/// to extract individual `<Rule>` blocks as raw XML strings.
enum LifecycleXMLParser {

  /// Parse lifecycle XML data and return individual <Rule>...</Rule> strings.
  static func parseRules(from data: Data) -> [String] {
    guard let xmlString = String(data: data, encoding: .utf8) else { return [] }

    var rules: [String] = []
    var searchRange = xmlString.startIndex..<xmlString.endIndex

    while let startRange = xmlString.range(of: "<Rule>", range: searchRange) {
      guard let endRange = xmlString.range(of: "</Rule>", range: startRange.upperBound..<xmlString.endIndex)
      else { break }

      let ruleXML = String(xmlString[startRange.lowerBound...endRange.upperBound])
      // Trim but keep the closing tag
      let fullRule = String(xmlString[startRange.lowerBound..<endRange.upperBound]) + "</Rule>"
      rules.append(ruleXML)
      searchRange = endRange.upperBound..<xmlString.endIndex
    }

    return rules
  }
}
