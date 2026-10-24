//
//  CLIJSON.swift
//  SnapzyCLIProtocol
//
//  One JSON configuration for both ends of the socket and for CLI output, so
//  the wire format and what agents read stay byte-for-byte predictable.
//

import Foundation

public enum CLIJSON {
  public static func makeEncoder(prettyPrinted: Bool = false) -> JSONEncoder {
    let encoder = JSONEncoder()
    var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    if prettyPrinted {
      formatting.insert(.prettyPrinted)
    }
    encoder.outputFormatting = formatting
    return encoder
  }

  public static func makeDecoder() -> JSONDecoder {
    JSONDecoder()
  }
}
