//
//  CLIListModels.swift
//  SnapzyCLIProtocol
//
//  Displays, windows and apps returned by the `list.*` methods. Lists are
//  wrapped in an object so fields can be added without breaking readers.
//

import Foundation

public struct CLIDisplay: Codable, Sendable, Equatable {
  public let id: UInt32
  public let name: String
  public let frame: CLIRect
  /// Backing pixels per point.
  public let scale: Double
  public let isMain: Bool

  public init(id: UInt32, name: String, frame: CLIRect, scale: Double, isMain: Bool) {
    self.id = id
    self.name = name
    self.frame = frame
    self.scale = scale
    self.isMain = isMain
  }
}

public struct CLIWindowOwner: Codable, Sendable, Equatable {
  public let name: String
  public let bundleID: String?
  public let pid: Int32

  public init(name: String, bundleID: String?, pid: Int32) {
    self.name = name
    self.bundleID = bundleID
    self.pid = pid
  }
}

public struct CLIWindow: Codable, Sendable, Equatable {
  public let id: UInt32
  public let title: String?
  public let app: CLIWindowOwner
  public let frame: CLIRect
  public let displayID: UInt32?
  public let isOnScreen: Bool
  public let isActive: Bool

  public init(
    id: UInt32,
    title: String?,
    app: CLIWindowOwner,
    frame: CLIRect,
    displayID: UInt32?,
    isOnScreen: Bool,
    isActive: Bool
  ) {
    self.id = id
    self.title = title
    self.app = app
    self.frame = frame
    self.displayID = displayID
    self.isOnScreen = isOnScreen
    self.isActive = isActive
  }
}

public struct CLIApp: Codable, Sendable, Equatable {
  public let name: String
  public let bundleID: String?
  public let pid: Int32
  public let windowCount: Int
  public let isActive: Bool

  public init(name: String, bundleID: String?, pid: Int32, windowCount: Int, isActive: Bool) {
    self.name = name
    self.bundleID = bundleID
    self.pid = pid
    self.windowCount = windowCount
    self.isActive = isActive
  }
}

public struct CLIDisplayList: Codable, Sendable, Equatable {
  public let displays: [CLIDisplay]

  public init(displays: [CLIDisplay]) {
    self.displays = displays
  }
}

/// Windows are ordered front to back.
public struct CLIWindowList: Codable, Sendable, Equatable {
  public let windows: [CLIWindow]

  public init(windows: [CLIWindow]) {
    self.windows = windows
  }
}

public struct CLIAppList: Codable, Sendable, Equatable {
  public let apps: [CLIApp]

  public init(apps: [CLIApp]) {
    self.apps = apps
  }
}
