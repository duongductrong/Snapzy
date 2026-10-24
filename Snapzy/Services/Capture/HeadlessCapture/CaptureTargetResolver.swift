//
//  CaptureTargetResolver.swift
//  Snapzy
//
//  Turns a headless display/window/area selection into a concrete target.
//  Pure functions over injected candidates and screen frames, so every
//  matching rule is unit-testable without ScreenCaptureKit.
//

import AppKit

nonisolated enum CaptureTargetResolver {
  struct ResolvedWindow: Equatable {
    let candidate: WindowSelectionCandidate
    /// Windows that matched an app selector before `index` picked one.
    let matchedCandidates: Int?
  }

  /// `candidates` are front to back, as from `WindowSelectionQueryService.prepareSnapshot`.
  static func window(
    _ selection: HeadlessCaptureRequest.WindowSelection,
    in candidates: [WindowSelectionCandidate]
  ) throws -> ResolvedWindow {
    switch selection {
    case .id(let windowID):
      guard let candidate = candidates.first(where: { $0.target.windowID == windowID }) else {
        throw HeadlessCaptureError.targetNotFound(
          "No capturable on-screen window with ID \(windowID). Run `snapzy list windows` for current IDs"
        )
      }
      return ResolvedWindow(candidate: candidate, matchedCandidates: nil)

    case .app(let app, let titlePattern, let index):
      var matches = AppNameMatcher.filter(
        candidates,
        query: app,
        name: \.ownerName,
        bundleID: \.target.bundleIdentifier
      )
      guard !matches.isEmpty else {
        throw HeadlessCaptureError.targetNotFound(
          "No on-screen window belongs to an app matching \"\(app)\". Run `snapzy list apps`"
        )
      }

      if let titlePattern {
        let expression: NSRegularExpression
        do {
          expression = try NSRegularExpression(pattern: titlePattern)
        } catch {
          throw HeadlessCaptureError.invalidRequest("Invalid title pattern: \(error.localizedDescription)")
        }
        matches = matches.filter { candidate in
          let title = candidate.target.title ?? ""
          return expression.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
        }
        guard !matches.isEmpty else {
          throw HeadlessCaptureError.targetNotFound(
            "No \(app) window title matches /\(titlePattern)/. Run `snapzy list windows --app '\(app)'`"
          )
        }
      }

      let position = index ?? 0
      guard matches.indices.contains(position) else {
        throw HeadlessCaptureError.targetNotFound(
          "Index \(position) is out of range: \(matches.count) matching window(s)"
        )
      }
      return ResolvedWindow(candidate: matches[position], matchedCandidates: matches.count)

    case .active:
      throw HeadlessCaptureError.invalidRequest("The active window is resolved by ActiveWindowResolver")
    }
  }

  /// Display IDs to capture, in screen order.
  static func displays(
    _ selection: HeadlessCaptureRequest.DisplaySelection,
    available displayIDs: [CGDirectDisplayID],
    mainDisplayID: CGDirectDisplayID
  ) throws -> [CGDirectDisplayID] {
    switch selection {
    case .main:
      guard displayIDs.contains(mainDisplayID) else {
        throw HeadlessCaptureError.targetNotFound("The main display is not available")
      }
      return [mainDisplayID]
    case .all:
      guard !displayIDs.isEmpty else {
        throw HeadlessCaptureError.targetNotFound("No displays are available")
      }
      return displayIDs
    case .id(let displayID):
      guard displayIDs.contains(displayID) else {
        throw HeadlessCaptureError.targetNotFound(
          "No display with ID \(displayID). Run `snapzy list displays`"
        )
      }
      return [displayID]
    }
  }

  /// The whole area must be on screen: the capture path clamps to display
  /// bounds, so a partly off-screen rect would silently come back smaller.
  /// `rect.size` is checked before standardizing so negative sizes are rejected.
  static func validateArea(_ rect: CGRect, screenFrames: [CGRect]) throws {
    guard rect.size.width >= 1, rect.size.height >= 1 else {
      throw HeadlessCaptureError.invalidRequest("The area must be at least 1×1 point")
    }

    // Displays never overlap, so summed intersections measure on-screen coverage.
    let coveredArea = screenFrames.reduce(0.0) { total, frame in
      let overlap = frame.intersection(rect)
      return overlap.isNull ? total : total + Double(overlap.width * overlap.height)
    }
    guard coveredArea > 0 else {
      throw HeadlessCaptureError.targetNotFound(
        "The area is not on any display. Run `snapzy list displays` for display frames"
      )
    }
    guard coveredArea >= Double(rect.width * rect.height) - 1 else {
      throw HeadlessCaptureError.invalidRequest(
        "Part of the area is off screen. Keep it inside the frames from `snapzy list displays`"
      )
    }
  }
}
