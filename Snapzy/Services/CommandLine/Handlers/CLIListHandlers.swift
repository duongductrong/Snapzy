//
//  CLIListHandlers.swift
//  Snapzy
//
//  `list.displays`, `list.windows`, `list.apps`. Windows come from the same
//  candidate source as application-mode capture, so the IDs and front-to-back
//  order agree with what `capture window` resolves.
//

import AppKit
import ScreenCaptureKit
import SnapzyCLIProtocol

nonisolated struct CLIListDisplaysHandler: CLIRequestHandling {
  func handle(_: CLIEmpty, context _: CLIRequestContext) async throws -> CLIDisplayList {
    await Self.displays()
  }

  @MainActor
  private static func displays() -> CLIDisplayList {
    let mainDisplayHeight = CLICoordinateSpace.mainDisplayHeight
    let displays = NSScreen.screens.compactMap { screen -> CLIDisplay? in
      guard let displayID = screen.displayID else { return nil }
      return CLIDisplay(
        id: displayID,
        name: screen.localizedName,
        frame: CLICoordinateSpace.topLeftRect(fromAppKit: screen.frame, mainDisplayHeight: mainDisplayHeight),
        scale: screen.backingScaleFactor,
        isMain: displayID == CGMainDisplayID()
      )
    }
    return CLIDisplayList(displays: displays)
  }
}

nonisolated struct CLIListWindowsHandler: CLIRequestHandling {
  func handle(_ params: ListWindowsParams, context _: CLIRequestContext) async throws -> CLIWindowList {
    var windows = try await CLIWindowSource.onScreenWindows()
    if params.includeOffscreen {
      windows += try await CLIWindowSource.offscreenWindows(excluding: Set(windows.map(\.id)))
    }
    if let app = params.app {
      windows = AppNameMatcher.filter(windows, query: app, name: \.app.name, bundleID: \.app.bundleID)
    }
    return CLIWindowList(windows: windows)
  }
}

nonisolated struct CLIListAppsHandler: CLIRequestHandling {
  func handle(_: CLIEmpty, context _: CLIRequestContext) async throws -> CLIAppList {
    let windows = try await CLIWindowSource.onScreenWindows()
    return CLIAppList(apps: CLIWindowSource.apps(from: windows))
  }
}

/// Window enumeration shared by the list handlers. Mapping is pure and
/// separate from the system queries so it is unit-testable.
nonisolated enum CLIWindowSource {
  struct Candidate: Equatable, Sendable {
    let windowID: CGWindowID
    let title: String?
    let ownerName: String
    let bundleID: String?
    let ownerPID: Int32?
    /// AppKit global coordinates (bottom-left origin).
    let frame: CGRect
    let displayID: CGDirectDisplayID
  }

  static let permissionError = CLIError(
    .permissionDenied,
    "Snapzy does not have Screen Recording permission",
    hint: "Grant it in System Settings → Privacy & Security → Screen & System Audio Recording, "
      + "then relaunch Snapzy if it was granted while Snapzy was running"
  )

  static func onScreenWindows() async throws -> [CLIWindow] {
    guard CGPreflightScreenCaptureAccess() else { throw permissionError }

    let snapshot = await WindowSelectionQueryService.prepareSnapshot(
      prefetchedContentTask: nil,
      excludeOwnApplication: true
    )
    guard let snapshot else {
      throw CLIError(.internal, "Could not read the window list", hint: "Run `snapzy doctor`")
    }

    let context = await MainActor.run {
      (CLICoordinateSpace.mainDisplayHeight, NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }
    let candidates = snapshot.orderedCandidates.map {
      Candidate(
        windowID: $0.target.windowID,
        title: $0.target.title,
        ownerName: $0.ownerName,
        bundleID: $0.target.bundleIdentifier,
        ownerPID: $0.target.ownerPID,
        frame: $0.target.frame,
        displayID: $0.target.displayID
      )
    }
    return windows(from: candidates, frontmostPID: context.1, mainDisplayHeight: context.0)
  }

  /// Minimized windows and windows on other Spaces. `SCWindow.frame` is
  /// already top-left global points.
  static func offscreenWindows(excluding knownIDs: Set<UInt32>) async throws -> [CLIWindow] {
    let content: SCShareableContent
    do {
      content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
    } catch {
      guard CGPreflightScreenCaptureAccess() else { throw permissionError }
      throw CLIError(.internal, "Could not read off-screen windows: \(error.localizedDescription)")
    }

    let ownBundleID = Bundle.main.bundleIdentifier
    return content.windows.compactMap { window -> CLIWindow? in
      guard
        !window.isOnScreen,
        window.windowLayer == 0,
        !knownIDs.contains(window.windowID),
        window.frame.width > 32, window.frame.height > 32,
        let owner = window.owningApplication,
        owner.bundleIdentifier != ownBundleID
      else { return nil }

      return CLIWindow(
        id: window.windowID,
        title: window.title?.isEmpty == false ? window.title : nil,
        app: CLIWindowOwner(name: owner.applicationName, bundleID: owner.bundleIdentifier, pid: owner.processID),
        frame: CLICoordinateSpace.cliRect(window.frame),
        displayID: nil,
        isOnScreen: false,
        isActive: false
      )
    }
  }

  /// The frontmost app's frontmost window is the active one.
  static func windows(
    from candidates: [Candidate],
    frontmostPID: pid_t?,
    mainDisplayHeight: CGFloat
  ) -> [CLIWindow] {
    var activeWindowID: CGWindowID?
    if let frontmostPID {
      activeWindowID = candidates.first { $0.ownerPID == frontmostPID }?.windowID
    }

    return candidates.map { candidate in
      CLIWindow(
        id: candidate.windowID,
        title: candidate.title,
        app: CLIWindowOwner(name: candidate.ownerName, bundleID: candidate.bundleID, pid: candidate.ownerPID ?? 0),
        frame: CLICoordinateSpace.topLeftRect(fromAppKit: candidate.frame, mainDisplayHeight: mainDisplayHeight),
        displayID: candidate.displayID,
        isOnScreen: true,
        isActive: candidate.windowID == activeWindowID
      )
    }
  }

  /// Apps in the order their first window appears, front to back. Windows
  /// with an unknown owner PID (reported as 0) group by app name instead of
  /// merging every such window into one app.
  static func apps(from windows: [CLIWindow]) -> [CLIApp] {
    var order: [String] = []
    var grouped: [String: [CLIWindow]] = [:]
    for window in windows {
      let key = window.app.pid > 0 ? "pid:\(window.app.pid)" : "name:\(window.app.bundleID ?? window.app.name)"
      if grouped[key] == nil {
        order.append(key)
      }
      grouped[key, default: []].append(window)
    }

    return order.compactMap { key in
      guard let appWindows = grouped[key], let first = appWindows.first else { return nil }
      return CLIApp(
        name: first.app.name,
        bundleID: first.app.bundleID,
        pid: first.app.pid,
        windowCount: appWindows.count,
        isActive: appWindows.contains(where: \.isActive)
      )
    }
  }
}
