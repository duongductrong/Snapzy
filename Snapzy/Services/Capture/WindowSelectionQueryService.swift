//
//  WindowSelectionQueryService.swift
//  Snapzy
//
//  Builds ordered window candidates for screenshot application mode.
//

import AppKit
import Foundation
import ScreenCaptureKit

struct WindowSelectionCandidate: Equatable, Sendable {
  let target: WindowCaptureTarget
  let ownerName: String
  let windowLayer: Int

  func contains(_ point: CGPoint) -> Bool {
    target.frame.contains(point)
  }
}

struct WindowSelectionSnapshot: Sendable {
  let orderedCandidates: [WindowSelectionCandidate]

  func hitTest(at point: CGPoint) -> WindowSelectionCandidate? {
    orderedCandidates.first { $0.contains(point) }
  }

  func merging(_ laterSnapshot: WindowSelectionSnapshot?) -> WindowSelectionSnapshot {
    guard let laterSnapshot else { return self }
    var seenWindowIDs = Set(orderedCandidates.map(\.target.windowID))
    return WindowSelectionSnapshot(
      orderedCandidates: orderedCandidates + laterSnapshot.orderedCandidates.filter {
        seenWindowIDs.insert($0.target.windowID).inserted
      }
    )
  }
}

@MainActor
enum WindowSelectionQueryService {
  struct RawWindowInfo: Sendable {
    let windowID: CGWindowID
    let layer: Int?
    let quartzBounds: CGRect?
    let alpha: Double
    let ownerPID: Int32?
    let ownerName: String?
    let title: String?
  }

  static func prepareSnapshot(
    prefetchedContentTask: ShareableContentPrefetchTask?,
    excludeOwnApplication: Bool
  ) async -> WindowSelectionSnapshot? {
    do {
      let content = try await loadShareableContent(prefetchedContentTask: prefetchedContentTask)
      let shareableWindowsByID = Dictionary(
        uniqueKeysWithValues: content.windows.filter { $0.isOnScreen }.map { ($0.windowID, $0) }
      )
      let ownBundleIdentifier = Bundle.main.bundleIdentifier

      let rawWindowInfoList = await Task.detached {
        guard
          let rawWindowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
          ) as? [[String: Any]]
        else {
          return [RawWindowInfo]()
        }

        return rawWindowInfo.compactMap { windowInfo -> RawWindowInfo? in
          guard let number = windowInfo[kCGWindowNumber as String] as? NSNumber else { return nil }
          let windowID = CGWindowID(number.uint32Value)
          
          let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue
          
          var quartzBounds: CGRect? = nil
          if let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary {
            quartzBounds = CGRect(dictionaryRepresentation: boundsDictionary)?.standardized
          }
          
          let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
          let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
          let ownerName = windowInfo[kCGWindowOwnerName as String] as? String
          let title = windowInfo[kCGWindowName as String] as? String

          return RawWindowInfo(
            windowID: windowID,
            layer: layer,
            quartzBounds: quartzBounds,
            alpha: alpha,
            ownerPID: ownerPID,
            ownerName: ownerName,
            title: title
          )
        }
      }.value

      var seenWindowIDs = Set<CGWindowID>()
      var orderedCandidates: [WindowSelectionCandidate] = []

      for info in rawWindowInfoList {
        let windowID = info.windowID
        guard seenWindowIDs.insert(windowID).inserted else { continue }
        let shareableWindow = shareableWindowsByID[windowID]
        
        let windowLayer = info.layer ?? shareableWindow?.windowLayer ?? 0
        guard let quartzBounds = info.quartzBounds else { continue }
        let frame = appKitGlobalRect(fromQuartzGlobalRect: quartzBounds).integral
        guard frame.width > 32, frame.height > 32 else { continue }
        guard let displayID = displayID(for: frame) else { continue }
        guard info.alpha > 0 else { continue }

        let bundleIdentifier = shareableWindow?.owningApplication?.bundleIdentifier
          ?? info.ownerPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        
        let isOwnApplication = bundleIdentifier == ownBundleIdentifier
        if excludeOwnApplication, isOwnApplication {
          continue
        }

        let title = (shareableWindow?.title?.isEmpty == false) ? shareableWindow?.title : (info.title?.isEmpty == false ? info.title : nil)
        let ownerNameVal = (shareableWindow?.owningApplication?.applicationName.isEmpty == false
          ? shareableWindow?.owningApplication?.applicationName
          : nil) ?? info.ownerName ?? ""
        let targetKind = WindowCaptureSelectionPolicy.targetKind(
          windowLayer: windowLayer,
          frame: frame,
          visibleFrame: NSScreen.screens.first(where: { $0.displayID == displayID })?.visibleFrame,
          alpha: info.alpha,
          isOwnApplication: isOwnApplication,
          isSystemOwned: WindowCaptureSelectionPolicy.isSystemOwned(
            bundleIdentifier: bundleIdentifier,
            ownerName: ownerNameVal
          )
        )
        guard let targetKind else { continue }
        // Nonzero-layer popovers are intentionally accepted only by the synchronous
        // pre-overlay collector. Adding them from this later live query would broaden the
        // feature beyond UI that was already visible when capture began.
        guard targetKind != .menuBarPopover else { continue }

        orderedCandidates.append(
          WindowSelectionCandidate(
            target: WindowCaptureTarget(
              windowID: windowID,
              frame: frame,
              displayID: displayID,
              title: title,
              bundleIdentifier: bundleIdentifier,
              ownerPID: info.ownerPID,
              kind: targetKind
            ),
            ownerName: ownerNameVal,
            windowLayer: windowLayer
          )
        )
      }

      return WindowSelectionSnapshot(orderedCandidates: orderedCandidates)
    } catch {
      DiagnosticLogger.shared.logError(
        .capture,
        error,
        "Failed to prepare application mode window candidates"
      )
      return nil
    }
  }

  /// Retain a visible third-party menu-bar popover before Snapzy creates selection windows.
  /// Menu extras may close as a side effect of global-hotkey handling, so a later async query
  /// cannot reliably discover or capture them.
  static func captureImmediateMenuBarPopoverCaptures(
    excludeOwnApplication: Bool
  ) -> [ImmediateMenuBarPopoverCapture] {
    let ownBundleIdentifier = Bundle.main.bundleIdentifier
    var captures: [ImmediateMenuBarPopoverCapture] = []
    var displaySnapshots: [CGDirectDisplayID: CGImage] = [:]

    for info in rawWindowInfoList() {
      let windowLayer = info.layer ?? 0
      guard windowLayer != 0, let quartzBounds = info.quartzBounds else { continue }

      let frame = appKitGlobalRect(fromQuartzGlobalRect: quartzBounds).integral
      guard frame.width > 32, frame.height > 32, info.alpha > 0 else { continue }
      guard let displayID = displayID(for: frame) else { continue }
      guard let display = NSScreen.screens.first(where: { $0.displayID == displayID }) else { continue }

      let bundleIdentifier = info.ownerPID.flatMap {
        NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
      }
      let isOwnApplication = bundleIdentifier == ownBundleIdentifier
      if excludeOwnApplication, isOwnApplication { continue }

      let ownerName = info.ownerName ?? ""
      guard WindowCaptureSelectionPolicy.targetKind(
        windowLayer: windowLayer,
        frame: frame,
        visibleFrame: display.visibleFrame,
        alpha: info.alpha,
        isOwnApplication: isOwnApplication,
        isSystemOwned: WindowCaptureSelectionPolicy.isSystemOwned(
          bundleIdentifier: bundleIdentifier,
          ownerName: ownerName
        )
      ) == .menuBarPopover else {
        continue
      }

      // These transient WindowServer windows can be enumerated but cannot always be
      // independently rendered by Core Graphics. Capture the containing display before
      // Snapzy presents any overlay, then retain only this popover's already-visible pixels.
      let displayImage: CGImage
      if let snapshot = displaySnapshots[displayID] {
        displayImage = snapshot
      } else if let snapshot = CGDisplayCreateImage(displayID) {
        displaySnapshots[displayID] = snapshot
        displayImage = snapshot
      } else {
        continue
      }
      guard let cropRect = WindowCaptureSelectionPolicy.displaySnapshotCropRect(
        frame: frame,
        displayFrame: display.frame,
        imagePixelWidth: displayImage.width,
        imagePixelHeight: displayImage.height
      ), let croppedImage = displayImage.cropping(to: cropRect) else {
        continue
      }

      let target = WindowCaptureTarget(
        windowID: info.windowID,
        frame: frame,
        displayID: displayID,
        title: info.title,
        bundleIdentifier: bundleIdentifier,
        ownerPID: info.ownerPID,
        kind: .menuBarPopover
      )
      let scaleFactor = max(
        CGFloat(croppedImage.width) / max(frame.width, 1),
        CGFloat(croppedImage.height) / max(frame.height, 1),
        1
      )
      guard let image = WindowCaptureSelectionPolicy.alphaMaskedMenuBarPopoverImage(
        croppedImage,
        scaleFactor: scaleFactor
      ) else {
        continue
      }
      captures.append(ImmediateMenuBarPopoverCapture(target: target, image: image, scaleFactor: scaleFactor))
    }

    return captures
  }

  static func resolveWindow(
    windowID: CGWindowID,
    prefetchedContentTask: ShareableContentPrefetchTask?
  ) async -> SCWindow? {
    do {
      let content = try await loadShareableContent(prefetchedContentTask: prefetchedContentTask)
      if let prefetchedMatch = content.windows.first(where: { $0.windowID == windowID && $0.isOnScreen }) {
        return prefetchedMatch
      }

      let refreshedContent = try await SCShareableContent.current
      return refreshedContent.windows.first { $0.windowID == windowID && $0.isOnScreen }
    } catch {
      DiagnosticLogger.shared.logError(
        .capture,
        error,
        "Failed to resolve shareable window \(windowID)"
      )
      return nil
    }
  }

  /// Uses WindowServer's raw list rather than ScreenCaptureKit: eligible menu-bar popovers
  /// are frequently not shareable even while they remain visible.
  nonisolated static func visibleWindowIDs(for targets: [WindowCaptureTarget]) -> Set<CGWindowID> {
    let infosByID = Dictionary(uniqueKeysWithValues: rawWindowInfoList().map { ($0.windowID, $0) })
    return Set(targets.compactMap { target in
      guard let info = infosByID[target.windowID] else { return nil }
      guard info.alpha > 0, info.quartzBounds?.isEmpty == false else { return nil }
      if let expectedOwnerPID = target.ownerPID, let actualOwnerPID = info.ownerPID,
         expectedOwnerPID != actualOwnerPID {
        return nil
      }
      return target.windowID
    })
  }

  private static func loadShareableContent(
    prefetchedContentTask: ShareableContentPrefetchTask?
  ) async throws -> SCShareableContent {
    if let prefetchedContentTask {
      return try await prefetchedContentTask.value
    }
    return try await SCShareableContent.current
  }

  private static func displayID(for frame: CGRect) -> CGDirectDisplayID? {
    let midpoint = CGPoint(x: frame.midX, y: frame.midY)
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) {
      return screen.displayID
    }

    var bestDisplayID: CGDirectDisplayID?
    var bestIntersectionArea: CGFloat = 0
    for screen in NSScreen.screens {
      let intersection = screen.frame.intersection(frame)
      let area = intersection.width * intersection.height
      if area > bestIntersectionArea {
        bestIntersectionArea = area
        bestDisplayID = screen.displayID
      }
    }
    return bestDisplayID
  }

  private static func appKitGlobalRect(fromQuartzGlobalRect rect: CGRect) -> CGRect {
    let mainScreenHeight = NSScreen.screens.first(where: { $0.displayID == CGMainDisplayID() })?.frame.height
      ?? CGDisplayBounds(CGMainDisplayID()).height

    return CGRect(
      x: rect.origin.x,
      y: mainScreenHeight - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }

  nonisolated private static func rawWindowInfoList() -> [RawWindowInfo] {
    guard
      let rawWindowInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return []
    }

    return rawWindowInfo.compactMap { windowInfo in
      guard let number = windowInfo[kCGWindowNumber as String] as? NSNumber else { return nil }
      let quartzBounds = (windowInfo[kCGWindowBounds as String] as? NSDictionary)
        .flatMap { CGRect(dictionaryRepresentation: $0)?.standardized }
      return RawWindowInfo(
        windowID: CGWindowID(number.uint32Value),
        layer: (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue,
        quartzBounds: quartzBounds,
        alpha: (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0,
        ownerPID: (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
        ownerName: windowInfo[kCGWindowOwnerName as String] as? String,
        title: windowInfo[kCGWindowName as String] as? String
      )
    }
  }
}
