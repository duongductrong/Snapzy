//
//  ActiveWindowResolver.swift
//  Snapzy
//
//  Resolves the currently focused window for one-shot active-window capture.
//

import AppKit
import ApplicationServices
import Foundation

@MainActor
enum ActiveWindowResolver {
  /// Resolves the window that should be captured for the "capture active window" action.
  /// Intentionally never excludes Snapzy's own windows: if a Snapzy window is focused,
  /// capturing it is the whole point of triggering this action on it.
  static func resolveActiveWindowTarget(
    prefetchedContentTask: ShareableContentPrefetchTask? = nil
  ) async -> WindowCaptureTarget? {
    guard
      let snapshot = await WindowSelectionQueryService.prepareSnapshot(
        prefetchedContentTask: prefetchedContentTask,
        excludeOwnApplication: false
      )
    else {
      return nil
    }

    if let focusedTarget = focusedWindowTarget(in: snapshot) {
      return focusedTarget
    }

    return snapshot.orderedCandidates.first?.target
  }

  private static func focusedWindowTarget(
    in snapshot: WindowSelectionSnapshot
  ) -> WindowCaptureTarget? {
    guard AXIsProcessTrusted() else { return nil }
    guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else { return nil }
    guard let focusedFrame = focusedWindowFrame(forProcessIdentifier: frontmostApplication.processIdentifier) else {
      return nil
    }

    let bundleIdentifier = frontmostApplication.bundleIdentifier
    let sameAppCandidates = snapshot.orderedCandidates.filter { $0.target.bundleIdentifier == bundleIdentifier }
    guard !sameAppCandidates.isEmpty else { return nil }

    return sameAppCandidates.min {
      frameDistance($0.target.frame, focusedFrame) < frameDistance($1.target.frame, focusedFrame)
    }?.target
  }

  private static func focusedWindowFrame(forProcessIdentifier pid: pid_t) -> CGRect? {
    let appElement = AXUIElementCreateApplication(pid)

    var focusedWindowRef: CFTypeRef?
    let focusedWindowResult = AXUIElementCopyAttributeValue(
      appElement,
      kAXFocusedWindowAttribute as CFString,
      &focusedWindowRef
    )
    guard
      focusedWindowResult == .success,
      let focusedWindowRef,
      CFGetTypeID(focusedWindowRef) == AXUIElementGetTypeID()
    else { return nil }
    let focusedWindow = focusedWindowRef as! AXUIElement

    guard
      let position = pointValue(of: focusedWindow, attribute: kAXPositionAttribute),
      let size = sizeValue(of: focusedWindow, attribute: kAXSizeAttribute)
    else {
      return nil
    }

    // AX position/size are reported in top-left-origin global screen coordinates,
    // matching CGWindowList's coordinate space. Convert to AppKit's bottom-left origin
    // the same way WindowSelectionQueryService does, so frames compare directly.
    let quartzFrame = CGRect(origin: position, size: size)
    let mainScreenHeight = NSScreen.screens.first(where: { $0.displayID == CGMainDisplayID() })?.frame.height
      ?? CGDisplayBounds(CGMainDisplayID()).height

    return CGRect(
      x: quartzFrame.origin.x,
      y: mainScreenHeight - quartzFrame.maxY,
      width: quartzFrame.width,
      height: quartzFrame.height
    ).integral
  }

  private static func pointValue(
    of element: AXUIElement,
    attribute: String,
  ) -> CGPoint? {
    guard let axValue = axValue(of: element, attribute: attribute, type: .cgPoint) else { return nil }
    var value = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &value) else { return nil }
    return value
  }

  private static func sizeValue(
    of element: AXUIElement,
    attribute: String
  ) -> CGSize? {
    guard let axValue = axValue(of: element, attribute: attribute, type: .cgSize) else { return nil }
    var value = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &value) else { return nil }
    return value
  }

  private static func axValue(
    of element: AXUIElement,
    attribute: String,
    type: AXValueType
  ) -> AXValue? {
    var rawValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue) == .success,
      let rawValue,
      CFGetTypeID(rawValue) == AXValueGetTypeID()
    else {
      return nil
    }
    let axValue = rawValue as! AXValue
    guard AXValueGetType(axValue) == type else { return nil }
    return axValue
  }

  private static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let dx = lhs.midX - rhs.midX
    let dy = lhs.midY - rhs.midY
    return (dx * dx + dy * dy).squareRoot() + abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
  }
}
