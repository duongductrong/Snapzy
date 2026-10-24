//
//  CaptureRequest.swift
//  SnapzyCLIProtocol
//
//  Params for the `capture.*` methods.
//

import Foundation

public enum CLIImageFormat: String, Codable, Sendable, CaseIterable {
  case png
  case jpeg
  case webp

  public init?(fileExtension: String) {
    switch fileExtension.lowercased() {
    case "png": self = .png
    case "jpg", "jpeg": self = .jpeg
    case "webp": self = .webp
    default: return nil
    }
  }

  public var fileExtension: String {
    switch self {
    case .png: "png"
    case .jpeg: "jpg"
    case .webp: "webp"
    }
  }
}

public struct CaptureOptions: Codable, Sendable, Equatable {
  public let format: CLIImageFormat
  /// 0…1, JPEG only. `nil` uses the app default.
  public let quality: Double?
  /// Downscale so the longest edge is at most this many pixels. Never upscales.
  public let maxDimension: Int?
  public let showCursor: Bool
  /// Window captures only.
  public let windowShadow: Bool

  public init(
    format: CLIImageFormat = .png,
    quality: Double? = nil,
    maxDimension: Int? = nil,
    showCursor: Bool = false,
    windowShadow: Bool = true
  ) {
    self.format = format
    self.quality = quality
    self.maxDimension = maxDimension
    self.showCursor = showCursor
    self.windowShadow = windowShadow
  }
}

/// JSON: `"main"`, `"all"`, or a display ID number.
public enum DisplaySelector: Codable, Sendable, Hashable, CustomStringConvertible {
  case main
  case all
  case id(UInt32)

  public init?(argument: String) {
    switch argument.lowercased() {
    case "main": self = .main
    case "all": self = .all
    default:
      guard let id = UInt32(argument) else { return nil }
      self = .id(id)
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let id = try? container.decode(UInt32.self) {
      self = .id(id)
      return
    }
    let string = try container.decode(String.self)
    switch string {
    case "main": self = .main
    case "all": self = .all
    default:
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected \"main\", \"all\" or a display ID, got \"\(string)\""
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .main: try container.encode("main")
    case .all: try container.encode("all")
    case .id(let id): try container.encode(id)
    }
  }

  public var description: String {
    switch self {
    case .main: "main"
    case .all: "all"
    case .id(let id): String(id)
    }
  }
}

/// Matches an app by exact bundle ID, then case-insensitive name, then name prefix.
public struct AppWindowQuery: Codable, Sendable, Hashable {
  public let app: String
  /// Regular expression matched against the window title.
  public let titlePattern: String?
  /// 0-based index into the matching windows, front to back.
  public let index: Int?

  public init(app: String, titlePattern: String? = nil, index: Int? = nil) {
    self.app = app
    self.titlePattern = titlePattern
    self.index = index
  }
}

/// JSON: `{"id": 42}`, `{"app": "Safari", "titlePattern": "…", "index": 0}` or `{"active": true}`.
public enum WindowSelector: Codable, Sendable, Hashable {
  case id(UInt32)
  case app(AppWindowQuery)
  case active

  private enum CodingKeys: String, CodingKey {
    case id
    case app
    case titlePattern
    case index
    case active
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let hasID = container.contains(.id)
    let hasApp = container.contains(.app)
    let isActive = try container.decodeIfPresent(Bool.self, forKey: .active) ?? false

    switch (hasID, hasApp, isActive) {
    case (true, false, false):
      self = try .id(container.decode(UInt32.self, forKey: .id))
    case (false, true, false):
      self = try .app(AppWindowQuery(from: decoder))
    case (false, false, true):
      self = .active
    default:
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Window selector needs exactly one of \"id\", \"app\" or \"active\""
        )
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .id(let id):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(id, forKey: .id)
    case .app(let query):
      try query.encode(to: encoder)
    case .active:
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(true, forKey: .active)
    }
  }
}

public struct CaptureScreenParams: Codable, Sendable, Equatable {
  public let display: DisplaySelector
  public let options: CaptureOptions

  public init(display: DisplaySelector = .main, options: CaptureOptions = CaptureOptions()) {
    self.display = display
    self.options = options
  }
}

public struct CaptureWindowParams: Codable, Sendable, Equatable {
  public let window: WindowSelector
  public let options: CaptureOptions

  public init(window: WindowSelector, options: CaptureOptions = CaptureOptions()) {
    self.window = window
    self.options = options
  }
}

public struct CaptureAreaParams: Codable, Sendable, Equatable {
  public let rect: CLIRect
  public let options: CaptureOptions

  public init(rect: CLIRect, options: CaptureOptions = CaptureOptions()) {
    self.rect = rect
    self.options = options
  }
}
