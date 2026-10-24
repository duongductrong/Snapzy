//
//  WindowListDisplaySnapshot.swift
//  Snapzy
//
//  Core Graphics display snapshots that leave out specific windows by ID
//

import CoreGraphics

/// Drop-in replacements for the Core Graphics fast paths (`CGDisplayCreateImage`,
/// `CGWindowListCreateImage(.optionOnScreenOnly)`) that leave out Snapzy's capture chrome.
///
/// Chrome stays visible to screen recorders, so it is no longer hidden from Core Graphics
/// by `sharingType`. When an excluded window is on screen, the snapshot composites every
/// other on-screen window instead (same cost as `CGDisplayCreateImage`, pixel-identical
/// elsewhere). When none is on screen, the original call runs unchanged.
enum WindowListDisplaySnapshot {
  /// Front-to-back on-screen window IDs minus `excluded`, or nil when no excluded window
  /// is on screen (the caller then uses the unfiltered Core Graphics call).
  nonisolated static func compositedWindowIDs(
    onScreenWindowIDs: [CGWindowID],
    excluding excluded: Set<CGWindowID>
  ) -> [CGWindowID]? {
    guard !excluded.isEmpty, onScreenWindowIDs.contains(where: excluded.contains) else {
      return nil
    }
    return onScreenWindowIDs.filter { !excluded.contains($0) }
  }

  /// `CGDisplayCreateImage(displayID)` without the `excluded` windows.
  nonisolated static func captureDisplay(
    _ displayID: CGDirectDisplayID,
    excluding excluded: Set<CGWindowID>
  ) -> CGImage? {
    guard let windowIDs = compositedWindowIDs(onScreenWindowIDs: onScreenWindowIDs(), excluding: excluded) else {
      return CGDisplayCreateImage(displayID)
    }
    return image(bounds: CGDisplayBounds(displayID), windowIDs: windowIDs, imageOption: .bestResolution)
  }

  /// `CGWindowListCreateImage(bounds, .optionOnScreenOnly, kCGNullWindowID, imageOption)`
  /// without the `excluded` windows.
  nonisolated static func captureOnScreenWindows(
    bounds: CGRect,
    imageOption: CGWindowImageOption,
    excluding excluded: Set<CGWindowID>
  ) -> CGImage? {
    guard let windowIDs = compositedWindowIDs(onScreenWindowIDs: onScreenWindowIDs(), excluding: excluded) else {
      return CGWindowListCreateImage(bounds, .optionOnScreenOnly, kCGNullWindowID, imageOption)
    }
    return image(bounds: bounds, windowIDs: windowIDs, imageOption: imageOption)
  }

  private nonisolated static func onScreenWindowIDs() -> [CGWindowID] {
    let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windowInfo.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
  }

  private nonisolated static func image(
    bounds: CGRect,
    windowIDs: [CGWindowID],
    imageOption: CGWindowImageOption
  ) -> CGImage? {
    var pointers = windowIDs.map { UnsafeRawPointer(bitPattern: UInt($0)) }
    let windowArray = pointers.withUnsafeMutableBufferPointer {
      CFArrayCreate(kCFAllocatorDefault, $0.baseAddress, $0.count, nil)
    }
    guard let windowArray else { return nil }
    return CGImage(windowListFromArrayScreenBounds: bounds, windowArray: windowArray, imageOption: imageOption)
  }
}
