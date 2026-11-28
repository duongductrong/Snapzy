//
//  VideoEditorTextOverlayHost.swift
//  Snapzy
//
//  Live-preview canvas host for timeline Text / Title Overlays (`Aa`).
//  Provides a CapCut / Figma interactive transform frame (left/right line-wrap width pills,
//  4-corner true vector CoreText resize handles with zero pixelation, interior drag with
//  center X/Y magnetic snap guides) and direct realtime inline on-canvas text editing.
//

import AppKit
import AVFoundation
import Combine
import SwiftUI

// MARK: - Pure Testable Canvas Transform Math

nonisolated enum VideoEditorTextCanvasTransformMath {
  static let centerSnapThreshold: CGFloat = 0.012

  /// Proportional vector font-size scaling from diagonal corner distance relative to `center`.
  static func scaledFontSize(
    startFontSize: CGFloat,
    center: CGPoint,
    startPoint: CGPoint,
    currentPoint: CGPoint
  ) -> CGFloat {
    let startDist = max(12, hypot(startPoint.x - center.x, startPoint.y - center.y))
    let currentDist = max(4, hypot(currentPoint.x - center.x, currentPoint.y - center.y))
    let raw = startFontSize * (currentDist / startDist)
    guard raw.isFinite else { return startFontSize }
    return min(
      VideoEditorCaptionSettings.fontSizeRange.upperBound,
      max(VideoEditorCaptionSettings.fontSizeRange.lowerBound, raw)
    )
  }

  /// Symmetric horizontal wrap-box adjustment (`0.18 ... 0.96`) for leading/trailing side pills.
  /// Anchors to the rendered logical width when narrower than `startMaxWidthFraction` so pulling
  /// inward wraps text on the very first drag pixel without dead-zone travel.
  static func adjustedMaxWidthFraction(
    startMaxWidthFraction: CGFloat,
    logicalWidth: CGFloat,
    canvasWidth: CGFloat,
    horizontalDelta: CGFloat,
    isLeadingHandle: Bool
  ) -> CGFloat {
    guard canvasWidth > 1 else {
      return VideoEditorCaptionSettings.clampMaxWidthFraction(startMaxWidthFraction)
    }
    let clampedStart = VideoEditorCaptionSettings.clampMaxWidthFraction(startMaxWidthFraction)
    let signedDelta = isLeadingHandle ? -horizontalDelta : horizontalDelta
    let anchor: CGFloat = if logicalWidth > 1 {
      min(
        clampedStart,
        max(
          VideoEditorCaptionSettings.maxWidthFractionRange.lowerBound,
          (logicalWidth / canvasWidth) + 0.012
        )
      )
    } else {
      clampedStart
    }
    let proposed = anchor + (signedDelta * 2.0) / canvasWidth
    return VideoEditorCaptionSettings.clampMaxWidthFraction(proposed)
  }

  /// Clamps `(rawNormalizedX, rawNormalizedY)` and applies magnetic center snapping (`0.5`).
  static func snappedCenter(
    rawNormalizedX: CGFloat,
    rawNormalizedY: CGFloat,
    snapThreshold: CGFloat = centerSnapThreshold
  ) -> (point: CGPoint, snappedX: Bool, snappedY: Bool) {
    let clampedX = VideoEditorTextOverlay.clampNormalizedX(rawNormalizedX)
    let clampedY = VideoEditorTextOverlay.clampNormalizedY(rawNormalizedY)
    let snapX = abs(clampedX - 0.5) <= snapThreshold
    let snapY = abs(clampedY - 0.5) <= snapThreshold
    return (
      point: CGPoint(x: snapX ? 0.5 : clampedX, y: snapY ? 0.5 : clampedY),
      snappedX: snapX,
      snappedY: snapY
    )
  }
}

// MARK: - Canvas Host View

struct VideoEditorTextOverlayHost: View {
  private static let canvasSpaceName = "videoEditorTextOverlayCanvas"
  private static let accentStrokeColor = Color(red: 0.22, green: 0.72, blue: 0.96)

  enum TransformHandle: Equatable {
    case move
    case widthLeading
    case widthTrailing
    case cornerTopLeading
    case cornerTopTrailing
    case cornerBottomLeading
    case cornerBottomTrailing

    var isWidthHandle: Bool {
      self == .widthLeading || self == .widthTrailing
    }

    var isCornerHandle: Bool {
      switch self {
      case .cornerTopLeading, .cornerTopTrailing, .cornerBottomLeading, .cornerBottomTrailing:
        true
      default:
        false
      }
    }
  }

  private struct ActiveTransformSession {
    let overlayId: UUID
    let handle: TransformHandle
    let beforeOverlays: [VideoEditorTextOverlay]
    let startNormalizedCenter: CGPoint
    let startCanvasCenter: CGPoint
    let startFontSize: CGFloat
    let startMaxWidthFraction: CGFloat
    let startLogicalWidth: CGFloat
    var didMutate: Bool = false
  }

  @ObservedObject var state: VideoEditorState
  @ObservedObject private var fontManager = VideoEditorFontManager.shared
  let canvasSize: CGSize

  @Environment(\.displayScale) private var displayScale
  @State private var currentTimeSeconds: TimeInterval = 0
  @State private var isPlaying: Bool = false
  @State private var hoveredOverlayId: UUID?
  @State private var hoveredHandle: TransformHandle?
  @State private var activeTransform: ActiveTransformSession?
  @State private var dragPreviewOverlay: VideoEditorTextOverlay?
  @State private var snapGuideXActive: Bool = false
  @State private var snapGuideYActive: Bool = false
  @State private var lastTapOverlayId: UUID?
  @State private var lastTapUptime: TimeInterval = 0

  // Direct inline on-canvas text editing state
  @State private var inlineEditingOverlayId: UUID?
  @State private var inlineEditSnapshot: [VideoEditorTextOverlay]?
  @State private var inlineFocusGeneration: Int = 0

  @State private var cache = VideoEditorCaptionImageCache(capacity: 128)

  var body: some View {
    let _ = fontManager.revision
    let active = state.activeTextOverlays(at: currentTimeSeconds).map { overlay in
      if let preview = dragPreviewOverlay, preview.id == overlay.id {
        return preview
      }
      return overlay
    }

    ZStack {
      // Background tap catcher ONLY while inline text editing is active so underlying
      // zoom/cursor canvas interactions remain 100% unobstructed at all other times.
      if inlineEditingOverlayId != nil {
        Color.black.opacity(0.001)
          .frame(width: canvasSize.width, height: canvasSize.height)
          .contentShape(Rectangle())
          .onTapGesture {
            finishInlineEdit()
          }
      }

      if !isPlaying {
        snapGuidesOverlay
      }

      ForEach(active) { overlay in
        renderedOverlayItem(overlay)
      }

      if let editingId = inlineEditingOverlayId,
         let editingOverlay = active.first(where: { $0.id == editingId })
         ?? state.textOverlays.first(where: { $0.id == editingId }) {
        inlineKeyResponderOverlay(for: editingOverlay)
      }
    }
    .frame(width: canvasSize.width, height: canvasSize.height)
    .coordinateSpace(name: Self.canvasSpaceName)
    .clipped()
    .onAppear {
      currentTimeSeconds = CMTimeGetSeconds(state.playbackState.currentTime)
      isPlaying = state.playbackState.isPlaying
    }
    .onDisappear {
      if inlineEditingOverlayId != nil {
        finishInlineEdit()
      }
    }
    .onReceive(state.playbackState.$currentTime) { time in
      guard !state.textOverlays.isEmpty else { return }
      let sec = CMTimeGetSeconds(time)
      if isPlaying, abs(sec - currentTimeSeconds) < 0.016 {
        return
      }
      let prevActive = state.textOverlays.filter { $0.isEnabled && $0.contains(time: currentTimeSeconds) }
      let nextActive = state.textOverlays.filter { $0.isEnabled && $0.contains(time: sec) }
      guard !prevActive.isEmpty || !nextActive.isEmpty || !isPlaying else { return }

      // Coalesce/suppress 60Hz updates while playing through stationary hold windows
      // where the active overlay set and visual motion state are both completely static.
      if isPlaying,
         prevActive.map(\.id) == nextActive.map(\.id),
         !nextActive.isEmpty,
         nextActive
         .allSatisfy({ $0.isInStaticHoldWindow(at: currentTimeSeconds) && $0.isInStaticHoldWindow(at: sec) }) {
        return
      }
      currentTimeSeconds = sec
    }
    .onChange(of: state.textOverlays.count) { _ in
      currentTimeSeconds = CMTimeGetSeconds(state.playbackState.currentTime)
    }
    .onReceive(state.playbackState.$isPlaying.removeDuplicates()) { playing in
      isPlaying = playing
      if playing, inlineEditingOverlayId != nil {
        finishInlineEdit()
      }
    }
    .onChange(of: state.selectedTextOverlayId) { nextSelected in
      if let editingId = inlineEditingOverlayId, nextSelected != editingId {
        finishInlineEdit()
      }
    }
  }

  // MARK: - Magnetic Center Snap Guides

  private var snapGuidesOverlay: some View {
    ZStack {
      if snapGuideXActive {
        Rectangle()
          .fill(Self.accentStrokeColor.opacity(0.88))
          .frame(width: 1, height: canvasSize.height)
          .shadow(color: Color.black.opacity(0.45), radius: 1)
          .position(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
          .allowsHitTesting(false)
      }
      if snapGuideYActive {
        Rectangle()
          .fill(Self.accentStrokeColor.opacity(0.88))
          .frame(width: canvasSize.width, height: 1)
          .shadow(color: Color.black.opacity(0.45), radius: 1)
          .position(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
          .allowsHitTesting(false)
      }
    }
  }

  // MARK: - Rendered Overlay + CapCut / Figma Transform Frame

  @ViewBuilder
  private func renderedOverlayItem(_ overlay: VideoEditorTextOverlay) -> some View {
    let isInlineEditingThis = inlineEditingOverlayId == overlay.id
    let rawTrimmed = overlay.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let isGhostEmpty = isInlineEditingThis && rawTrimmed.isEmpty
    let renderText: String = {
      if isGhostEmpty {
        return L10n.VideoEditor.defaultTitleText
      }
      guard isInlineEditingThis else { return rawTrimmed }
      // Preserve live trailing spaces & newlines while typing directly on canvas.
      var live = overlay.text
      if live.hasSuffix("\n") {
        live += "\u{00A0}"
      } else if live.hasSuffix(" ") {
        live.removeLast()
        live += "\u{00A0}"
      }
      return live
    }()
    let scale = max(displayScale, 1)
    let pseudoSegment = CaptionSegment(
      id: overlay.id,
      sourceRange: overlay.safeTimeRange,
      text: renderText
    )
    let isSelected = state.selectedTextOverlayId == overlay.id || isInlineEditingThis
    let isActivelyTransformingThis = activeTransform?.overlayId == overlay.id
    let elapsed = max(0, currentTimeSeconds - overlay.startTime)
    let motion: VideoEditorCaptionMotionState =
      (!isPlaying && (elapsed < 0.03 || (isSelected && isActivelyTransformingThis)))
        ? .identity
        : overlay.motionState(at: currentTimeSeconds)

    let minPausedOpacity: CGFloat = isInlineEditingThis ? 0.90 : 0.35
    let minPausedReveal: CGFloat = isInlineEditingThis ? 0.92 : 0.25
    let baseOpacity = (!isPlaying && isSelected) ? max(motion.opacity, minPausedOpacity) : motion.opacity
    let effectiveOpacity = isGhostEmpty ? (baseOpacity * 0.30) : baseOpacity
    let effectiveWipe = (!isPlaying && isSelected) ? max(motion.wipeProgress, minPausedReveal) : motion.wipeProgress
    let effectiveVerticalReveal = (!isPlaying && isSelected)
      ? max(motion.verticalRevealProgress, minPausedReveal)
      : motion.verticalRevealProgress

    if !renderText.isEmpty,
       effectiveOpacity > 0.002,
       effectiveWipe > 0.002,
       effectiveVerticalReveal > 0.002,
       let entry = cache.entry(
         text: renderText,
         segment: pseudoSegment,
         sourceTime: currentTimeSeconds,
         settings: overlay.style,
         videoSize: canvasSize,
         subwordKind: motion.subwordKind,
         subwordProgress: motion.subwordProgress,
         scale: scale
       ) {
      let bmpSize = entry.layout.bitmapSize
      let logicalSize = entry.layout.size
      let dx = motion.offsetXFraction * canvasSize.height
      let dy = motion.offsetYFraction * canvasSize.height
      let blurPt = isInlineEditingThis ? min(motion.blurRadiusFraction * canvasSize.height, 1.2) :
        (motion.blurRadiusFraction * canvasSize.height)
      let centerX = overlay.normalizedX * canvasSize.width + dx
      let centerY = overlay.normalizedY * canvasSize.height + dy
      let frameW = max(logicalSize.width + 10, 44)
      let frameH = max(logicalSize.height + 8, 28)
      let showSelectionChrome = isSelected && !isPlaying

      ZStack {
        // CoreText @2x vector-rasterized graphic + interior move/select/double-click gesture
        renderedGraphic(
          entry: entry,
          size: bmpSize,
          scale: scale,
          shimmerProgress: motion.shimmerProgress
        )
        .mask(alignment: .topLeading) {
          Rectangle()
            .frame(
              width: bmpSize.width * effectiveWipe,
              height: bmpSize.height * effectiveVerticalReveal
            )
        }
        .scaleEffect(x: motion.scale * motion.scaleX, y: motion.scale * motion.scaleY)
        .modifier(ConditionalCanvasBlurModifier(radius: blurPt))
        .opacity(effectiveOpacity)
        .overlay {
          if isInlineEditingThis, !isPlaying {
            liveCanvasCaretOverlay(
              logicalSize: logicalSize,
              overlay: overlay,
              isGhostEmpty: isGhostEmpty
            )
            .scaleEffect(x: motion.scale * motion.scaleX, y: motion.scale * motion.scaleY)
            .allowsHitTesting(false)
          }
        }
        .overlay {
          if !showSelectionChrome,
             hoveredOverlayId == overlay.id,
             !isPlaying,
             activeTransform == nil,
             overlay.style.surfaceStyle != .selectionFrame {
            Radius.rect(Radius.ornament)
              .strokeBorder(Color.white.opacity(0.36), lineWidth: 0.8)
              .frame(width: frameW, height: frameH)
              .allowsHitTesting(false)
          }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
          hoveredOverlayId = hovering
            ? overlay.id
            : (hoveredOverlayId == overlay.id ? nil : hoveredOverlayId)
        }
        .gesture(interiorMoveAndClickGesture(for: overlay, logicalWidth: logicalSize.width))
        .accessibilityLabel(L10n.VideoEditor.textOverlayAccessibility(rawTrimmed))
        .accessibilityIdentifier("video-editor.canvas-text-overlay.\(overlay.id.uuidString)")

        // Sleek CapCut / Figma Transform Bounding Frame (shown ONLY when selected & paused)
        if showSelectionChrome {
          selectionTransformChrome(
            for: overlay,
            frameWidth: frameW,
            frameHeight: frameH,
            logicalWidth: logicalSize.width,
            centerY: centerY,
            isInlineEditing: isInlineEditingThis
          )
        }
      }
      .position(x: centerX, y: centerY)
    }
  }

  @ViewBuilder
  private func liveCanvasCaretOverlay(
    logicalSize: CGSize,
    overlay: VideoEditorTextOverlay,
    isGhostEmpty: Bool
  ) -> some View {
    let lines = overlay.text.components(separatedBy: "\n")
    let lineCount = max(1, lines.count)
    let singleLineHeight = max(14, min(logicalSize.height * 0.72, (logicalSize.height / CGFloat(lineCount)) * 0.78))
    let caretX: CGFloat = isGhostEmpty ? 0 : (logicalSize.width * 0.5 + 2)
    let caretY: CGFloat = lineCount > 1
      ? (logicalSize.height * 0.5 - singleLineHeight * 0.62)
      : 0

    TimelineView(.periodic(from: .now, by: 0.52)) { timeline in
      let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.52)
      let visible = (phase % 2) == 0
      Capsule(style: .continuous)
        .fill(Color.white)
        .frame(width: 2.0, height: singleLineHeight)
        .overlay(
          Capsule(style: .continuous)
            .strokeBorder(Self.accentStrokeColor, lineWidth: 0.6)
        )
        .shadow(color: Self.accentStrokeColor.opacity(0.85), radius: 3)
        .shadow(color: Color.black.opacity(0.65), radius: 1.5)
        .opacity(visible ? 1.0 : 0.12)
        .offset(x: caretX, y: caretY)
    }
  }

  // MARK: - CapCut / Figma Selection Chrome & Interactive Handles

  @ViewBuilder
  private func selectionTransformChrome(
    for overlay: VideoEditorTextOverlay,
    frameWidth: CGFloat,
    frameHeight: CGFloat,
    logicalWidth: CGFloat,
    centerY: CGFloat,
    isInlineEditing: Bool = false
  ) -> some View {
    let activeHandle = activeTransform?.overlayId == overlay.id ? activeTransform?.handle : nil
    let wrapBoxWidth = min(canvasSize.width - 8, overlay.style.maxWidthFraction * canvasSize.width)
    let placeAccessoryBelow = (centerY - frameHeight * 0.5) < 34
    let accessoryOffsetY = placeAccessoryBelow
      ? (frameHeight * 0.5 + 18)
      : -(frameHeight * 0.5 + 18)

    ZStack {
      // Live wrap-column guide while dragging left/right width pill handles
      if activeHandle?.isWidthHandle == true, wrapBoxWidth > frameWidth + 4 {
        Radius.rect(Radius.ornament)
          .strokeBorder(Self.accentStrokeColor.opacity(0.42), lineWidth: 0.85)
          .frame(width: wrapBoxWidth, height: frameHeight)
          .allowsHitTesting(false)
      }

      // Crisp bounding frame (switches to active studio accent glow while typing live on canvas)
      if overlay.style.surfaceStyle != .selectionFrame || isInlineEditing {
        Radius.rect(Radius.ornament)
          .strokeBorder(
            isInlineEditing ? Self.accentStrokeColor.opacity(0.96) : Color.white.opacity(0.94),
            lineWidth: isInlineEditing ? 1.35 : 1.0
          )
          .shadow(
            color: isInlineEditing ? Self.accentStrokeColor.opacity(0.35) : Color.black.opacity(0.55),
            radius: isInlineEditing ? 4 : 1.5,
            x: 0,
            y: isInlineEditing ? 0 : 0.5
          )
          .frame(width: frameWidth, height: frameHeight)
          .allowsHitTesting(false)
          .accessibilityIdentifier("video-editor.canvas-text-selection-frame")
      }

      // Left & Right Vertical Pill Handles (Max-Width / Line-Wrap Control)
      widthPillHandle(
        handle: .widthLeading,
        overlay: overlay,
        logicalWidth: logicalWidth,
        frameHeight: frameHeight,
        accessibilityId: "video-editor.canvas-text-handle.width-leading"
      )
      .offset(x: -frameWidth * 0.5, y: 0)

      widthPillHandle(
        handle: .widthTrailing,
        overlay: overlay,
        logicalWidth: logicalWidth,
        frameHeight: frameHeight,
        accessibilityId: "video-editor.canvas-text-handle.width-trailing"
      )
      .offset(x: frameWidth * 0.5, y: 0)

      // 4 Corner Circle Handles (True Vector Font Resize — rendered above side pills for priority)
      cornerCircleHandle(
        handle: .cornerTopLeading,
        overlay: overlay,
        logicalWidth: logicalWidth,
        accessibilityId: "video-editor.canvas-text-handle.corner-tl"
      )
      .offset(x: -frameWidth * 0.5, y: -frameHeight * 0.5)

      cornerCircleHandle(
        handle: .cornerTopTrailing,
        overlay: overlay,
        logicalWidth: logicalWidth,
        accessibilityId: "video-editor.canvas-text-handle.corner-tr"
      )
      .offset(x: frameWidth * 0.5, y: -frameHeight * 0.5)

      cornerCircleHandle(
        handle: .cornerBottomLeading,
        overlay: overlay,
        logicalWidth: logicalWidth,
        accessibilityId: "video-editor.canvas-text-handle.corner-bl"
      )
      .offset(x: -frameWidth * 0.5, y: frameHeight * 0.5)

      cornerCircleHandle(
        handle: .cornerBottomTrailing,
        overlay: overlay,
        logicalWidth: logicalWidth,
        accessibilityId: "video-editor.canvas-text-handle.corner-br"
      )
      .offset(x: frameWidth * 0.5, y: frameHeight * 0.5)

      // Floating accessory above (or below near top edge): live readout while transforming,
      // active WYSIWYG editing status pill while typing, or sleek `✎` inline-edit pill when idle.
      if let activeHandle, activeHandle.isWidthHandle || activeHandle.isCornerHandle {
        transformReadoutBadge(for: overlay, handle: activeHandle)
          .offset(y: accessoryOffsetY)
          .allowsHitTesting(false)
      } else if isInlineEditing {
        inlineEditingActiveBadge()
          .offset(y: accessoryOffsetY)
      } else if activeTransform == nil {
        inlineEditTriggerPill(for: overlay)
          .offset(y: accessoryOffsetY)
      }
    }
  }

  @ViewBuilder
  private func widthPillHandle(
    handle: TransformHandle,
    overlay: VideoEditorTextOverlay,
    logicalWidth: CGFloat,
    frameHeight: CGFloat,
    accessibilityId: String
  ) -> some View {
    let isActiveOrHovered = hoveredHandle == handle
      || (activeTransform?.overlayId == overlay.id && activeTransform?.handle == handle)
    let pillHeight = min(18, max(12, frameHeight * 0.46))
    let hitHeight = max(22, min(frameHeight - 10, 38))

    ZStack {
      Capsule(style: .continuous)
        .fill(Color.white)
        .frame(width: 5.5, height: pillHeight)
        .overlay {
          Capsule(style: .continuous)
            .strokeBorder(Self.accentStrokeColor, lineWidth: 1.1)
        }
        .shadow(color: Color.black.opacity(0.38), radius: 2, y: 0.5)
        .scaleEffect(isActiveOrHovered ? 1.16 : 1.0)
    }
    .frame(width: 20, height: hitHeight)
    .contentShape(Rectangle())
    .onHover { hovering in
      hoveredHandle = hovering ? handle : (hoveredHandle == handle ? nil : hoveredHandle)
    }
    .gesture(handleDragGesture(handle: handle, overlay: overlay, logicalWidth: logicalWidth))
    .accessibilityLabel(L10n.VideoEditor.textWrapHandleAccessibility)
    .accessibilityIdentifier(accessibilityId)
  }

  @ViewBuilder
  private func cornerCircleHandle(
    handle: TransformHandle,
    overlay: VideoEditorTextOverlay,
    logicalWidth: CGFloat,
    accessibilityId: String
  ) -> some View {
    let isActiveOrHovered = hoveredHandle == handle
      || (activeTransform?.overlayId == overlay.id && activeTransform?.handle == handle)

    ZStack {
      Circle()
        .fill(Color.white)
        .frame(width: 9, height: 9)
        .overlay {
          Circle()
            .strokeBorder(Self.accentStrokeColor, lineWidth: 1.3)
        }
        .shadow(color: Color.black.opacity(0.40), radius: 2, y: 0.5)
        .scaleEffect(isActiveOrHovered ? 1.20 : 1.0)
    }
    .frame(width: 22, height: 22)
    .contentShape(Rectangle())
    .onHover { hovering in
      hoveredHandle = hovering ? handle : (hoveredHandle == handle ? nil : hoveredHandle)
    }
    .gesture(handleDragGesture(handle: handle, overlay: overlay, logicalWidth: logicalWidth))
    .accessibilityLabel(L10n.VideoEditor.textScaleHandleAccessibility)
    .accessibilityIdentifier(accessibilityId)
  }

  private func inlineEditTriggerPill(for overlay: VideoEditorTextOverlay) -> some View {
    Button {
      beginInlineEdit(for: overlay)
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "pencil")
          .font(.system(size: 10, weight: .semibold))
      }
      .foregroundStyle(Color.white.opacity(0.95))
      .frame(width: 24, height: 20)
      .background(
        Capsule(style: .continuous)
          .fill(Color(red: 0.05, green: 0.07, blue: 0.11).opacity(0.88))
      )
      .overlay {
        Capsule(style: .continuous)
          .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
      }
      .shadow(color: Color.black.opacity(0.35), radius: 3, y: 1)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(L10n.VideoEditor.editTextOverlay)
    .accessibilityIdentifier("video-editor.canvas-text-edit-pill")
  }

  @ViewBuilder
  private func transformReadoutBadge(
    for overlay: VideoEditorTextOverlay,
    handle: TransformHandle
  ) -> some View {
    let label = if handle.isCornerHandle {
      L10n.VideoEditor.textCanvasFontSizePoints(Int((overlay.style.fontSize * 720.0).rounded()))
    } else {
      L10n.VideoEditor.textCanvasWrapPercent(Int((overlay.style.maxWidthFraction * 100.0).rounded()))
    }

    Text(label)
      .font(.system(size: 10, weight: .semibold, design: .monospaced))
      .foregroundStyle(Color.white.opacity(0.96))
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(
        Capsule(style: .continuous)
          .fill(Color(red: 0.05, green: 0.07, blue: 0.11).opacity(0.90))
      )
      .overlay {
        Capsule(style: .continuous)
          .strokeBorder(Self.accentStrokeColor.opacity(0.55), lineWidth: 0.8)
      }
      .shadow(color: Color.black.opacity(0.35), radius: 3, y: 1)
  }

  // MARK: - Direct Zero-Chrome WYSIWYG On-Canvas Key & IME Responder

  private func inlineEditingActiveBadge() -> some View {
    Button {
      finishInlineEdit()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "checkmark")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(Self.accentStrokeColor)
        Text(L10n.VideoEditor.textCanvasEditingBadge)
          .font(.system(size: 9.5, weight: .semibold))
          .lineLimit(1)
          .foregroundStyle(Color.white.opacity(0.96))
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 3.5)
      .background(
        Capsule(style: .continuous)
          .fill(Color(red: 0.04, green: 0.06, blue: 0.10).opacity(0.92))
      )
      .overlay {
        Capsule(style: .continuous)
          .strokeBorder(Self.accentStrokeColor.opacity(0.75), lineWidth: 0.85)
      }
      .shadow(color: Color.black.opacity(0.40), radius: 3, y: 1)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("video-editor.canvas-text-editing-badge")
  }

  @ViewBuilder
  private func inlineKeyResponderOverlay(for overlay: VideoEditorTextOverlay) -> some View {
    let anchorX = min(max(overlay.normalizedX * canvasSize.width, 12), max(12, canvasSize.width - 12))
    let anchorY = min(max(overlay.normalizedY * canvasSize.height, 12), max(12, canvasSize.height - 12))

    CanvasDirectTextResponder(
      text: inlineTextBinding(for: overlay.id),
      focusGeneration: inlineFocusGeneration,
      onCommit: {
        finishInlineEdit()
      }
    )
    .frame(width: 2, height: 2)
    .opacity(0.01)
    .allowsHitTesting(false)
    .accessibilityIdentifier("video-editor.canvas-text-inline-editor")
    .background {
      Button("") { finishInlineEdit() }
        .keyboardShortcut(.cancelAction)
        .opacity(0)
        .frame(width: 0, height: 0)

      Button("") { finishInlineEdit() }
        .keyboardShortcut(.return, modifiers: [.command])
        .opacity(0)
        .frame(width: 0, height: 0)
    }
    .position(x: anchorX, y: anchorY)
  }

  private func inlineTextBinding(for overlayId: UUID) -> Binding<String> {
    Binding(
      get: {
        state.textOverlays.first(where: { $0.id == overlayId })?.text ?? ""
      },
      set: { updatedText in
        state.updateTextOverlay(id: overlayId, recordUndo: false) { item in
          item.text = updatedText
        }
      }
    )
  }

  private func beginInlineEdit(for overlay: VideoEditorTextOverlay) {
    if inlineEditingOverlayId != nil, inlineEditingOverlayId != overlay.id {
      finishInlineEdit()
    }
    if state.playbackState.isPlaying {
      state.pause()
    }
    state.selectTextOverlay(id: overlay.id)
    state.leftSidebarPanel = .text
    state.isLeftSidebarVisible = true
    if inlineEditingOverlayId != overlay.id {
      inlineEditSnapshot = state.textOverlays
      inlineEditingOverlayId = overlay.id
      state.beginTextFieldEditing(token: "text-canvas")
    }
    inlineFocusGeneration &+= 1
  }

  private func finishInlineEdit() {
    guard inlineEditingOverlayId != nil else { return }
    let snapshot = inlineEditSnapshot
    inlineEditingOverlayId = nil
    inlineEditSnapshot = nil
    state.endTextFieldEditing(token: "text-canvas")
    if let snapshot {
      // Prevent leaving a completely blank invisible item if user accidentally cleared all text.
      for prior in snapshot {
        if let current = state.textOverlays.first(where: { $0.id == prior.id }),
           current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          state.updateTextOverlay(id: prior.id, recordUndo: false) { item in
            item.text = prior.text
          }
        }
      }
      state.commitTextOverlayEdit(previous: snapshot)
    }
    NSApp.keyWindow?.makeFirstResponder(nil)
  }

  // MARK: - Gestures (Stationary Canvas Coordinate Space)

  private func interiorMoveAndClickGesture(
    for overlay: VideoEditorTextOverlay,
    logicalWidth: CGFloat
  ) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpaceName))
      .onChanged { value in
        guard canvasSize.width > 1, canvasSize.height > 1 else { return }
        if activeTransform == nil {
          if inlineEditingOverlayId != nil, inlineEditingOverlayId != overlay.id {
            finishInlineEdit()
          }
          state.selectTextOverlay(id: overlay.id)
          activeTransform = ActiveTransformSession(
            overlayId: overlay.id,
            handle: .move,
            beforeOverlays: state.textOverlays,
            startNormalizedCenter: CGPoint(x: overlay.normalizedX, y: overlay.normalizedY),
            startCanvasCenter: CGPoint(
              x: overlay.normalizedX * canvasSize.width,
              y: overlay.normalizedY * canvasSize.height
            ),
            startFontSize: overlay.style.fontSize,
            startMaxWidthFraction: overlay.style.maxWidthFraction,
            startLogicalWidth: logicalWidth
          )
        }
        guard var session = activeTransform,
              session.overlayId == overlay.id,
              session.handle == .move
        else { return }

        let distance = hypot(value.translation.width, value.translation.height)
        guard distance > 2.0 else { return }
        session.didMutate = true
        activeTransform = session

        let rawX = session.startNormalizedCenter.x + value.translation.width / canvasSize.width
        let rawY = session.startNormalizedCenter.y + value.translation.height / canvasSize.height
        let snapped = VideoEditorTextCanvasTransformMath.snappedCenter(
          rawNormalizedX: rawX,
          rawNormalizedY: rawY
        )
        snapGuideXActive = snapped.snappedX
        snapGuideYActive = snapped.snappedY

        var preview = dragPreviewOverlay ?? overlay
        preview.normalizedX = snapped.point.x
        preview.normalizedY = snapped.point.y
        dragPreviewOverlay = preview
      }
      .onEnded { value in
        snapGuideXActive = false
        snapGuideYActive = false

        let session = activeTransform
        let committedPreview = dragPreviewOverlay
        activeTransform = nil
        dragPreviewOverlay = nil

        let moved = (session?.didMutate == true)
          || hypot(value.translation.width, value.translation.height) > 2.5
        if moved {
          if let committedPreview {
            state.updateTextOverlay(id: committedPreview.id, recordUndo: false) { item in
              item.normalizedX = committedPreview.normalizedX
              item.normalizedY = committedPreview.normalizedY
            }
          }
          if let prior = session?.beforeOverlays {
            state.commitTextOverlayEdit(previous: prior)
          }
        } else {
          state.selectTextOverlay(id: overlay.id)
          state.leftSidebarPanel = .text
          state.isLeftSidebarVisible = true

          let now = ProcessInfo.processInfo.systemUptime
          let doubleClickWindow = max(0.38, NSEvent.doubleClickInterval)
          let eventClickCount = NSApp.currentEvent?.clickCount ?? 1
          if inlineEditingOverlayId == overlay.id {
            inlineFocusGeneration &+= 1
          } else if eventClickCount >= 2
            || (lastTapOverlayId == overlay.id && (now - lastTapUptime) <= doubleClickWindow) {
            lastTapOverlayId = nil
            lastTapUptime = 0
            beginInlineEdit(for: overlay)
          } else {
            lastTapOverlayId = overlay.id
            lastTapUptime = now
          }
        }
      }
  }

  private func handleDragGesture(
    handle: TransformHandle,
    overlay: VideoEditorTextOverlay,
    logicalWidth: CGFloat
  ) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpaceName))
      .onChanged { value in
        guard canvasSize.width > 1, canvasSize.height > 1 else { return }
        if activeTransform == nil {
          if inlineEditingOverlayId != nil, inlineEditingOverlayId != overlay.id {
            finishInlineEdit()
          }
          state.selectTextOverlay(id: overlay.id)
          activeTransform = ActiveTransformSession(
            overlayId: overlay.id,
            handle: handle,
            beforeOverlays: state.textOverlays,
            startNormalizedCenter: CGPoint(x: overlay.normalizedX, y: overlay.normalizedY),
            startCanvasCenter: CGPoint(
              x: overlay.normalizedX * canvasSize.width,
              y: overlay.normalizedY * canvasSize.height
            ),
            startFontSize: overlay.style.fontSize,
            startMaxWidthFraction: overlay.style.maxWidthFraction,
            startLogicalWidth: logicalWidth
          )
        }
        guard var session = activeTransform,
              session.overlayId == overlay.id,
              session.handle == handle
        else { return }

        let distance = hypot(value.translation.width, value.translation.height)
        guard distance > 1.0 else { return }
        session.didMutate = true
        activeTransform = session

        if handle.isWidthHandle {
          let nextWidth = VideoEditorTextCanvasTransformMath.adjustedMaxWidthFraction(
            startMaxWidthFraction: session.startMaxWidthFraction,
            logicalWidth: session.startLogicalWidth,
            canvasWidth: canvasSize.width,
            horizontalDelta: value.translation.width,
            isLeadingHandle: handle == .widthLeading
          )
          var preview = dragPreviewOverlay ?? overlay
          preview.style.maxWidthFraction = nextWidth
          dragPreviewOverlay = preview
        } else if handle.isCornerHandle {
          let nextFontSize = VideoEditorTextCanvasTransformMath.scaledFontSize(
            startFontSize: session.startFontSize,
            center: session.startCanvasCenter,
            startPoint: value.startLocation,
            currentPoint: value.location
          )
          var preview = dragPreviewOverlay ?? overlay
          preview.style.fontSize = nextFontSize
          preview.syncLegacyMirrorFromStyle()
          preview.style.fontSize = nextFontSize
          dragPreviewOverlay = preview
        }
      }
      .onEnded { _ in
        let committedPreview = dragPreviewOverlay
        dragPreviewOverlay = nil
        if let session = activeTransform, session.didMutate {
          if let committedPreview {
            state.updateTextOverlay(id: committedPreview.id, recordUndo: false) { item in
              item.style.maxWidthFraction = committedPreview.style.maxWidthFraction
              item.style.fontSize = committedPreview.style.fontSize
              item.syncLegacyMirrorFromStyle()
              item.style.fontSize = committedPreview.style.fontSize
            }
          }
          state.commitTextOverlayEdit(previous: session.beforeOverlays)
        }
        activeTransform = nil
      }
  }

  // MARK: - Bitmap Graphic + Specular Shimmer

  @ViewBuilder
  private func renderedGraphic(
    entry: VideoEditorCaptionImageCache.Entry,
    size: CGSize,
    scale: CGFloat,
    shimmerProgress: CGFloat?
  ) -> some View {
    let baseImage = Image(decorative: entry.image, scale: scale)
      .resizable()
      .interpolation(.high)
      .frame(width: size.width, height: size.height)

    if let s = shimmerProgress {
      let bandW = max(24, size.width * 0.34)
      let sweepX = -size.width * 0.65 + (size.width * 1.30 + bandW) * s
      baseImage
        .overlay {
          LinearGradient(
            stops: [
              .init(color: .white.opacity(0), location: 0.0),
              .init(color: .white.opacity(0.62), location: 0.5),
              .init(color: .white.opacity(0), location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: bandW, height: size.height * 1.8)
          .rotationEffect(.degrees(18))
          .offset(x: sweepX)
          .blendMode(.plusLighter)
          .mask(baseImage)
        }
    } else {
      baseImage
    }
  }
}

/// Applies Gaussian blur only when radius exceeds perceptibility threshold so stationary
/// frames pay zero CoreAnimation `CAFilter` offscreen rasterization cost on 120Hz displays.
private struct ConditionalCanvasBlurModifier: ViewModifier {
  let radius: CGFloat

  func body(content: Content) -> some View {
    if radius > 0.05 {
      content.blur(radius: radius)
    } else {
      content
    }
  }
}

// MARK: - Native AppKit Zero-Chrome Key & IME Responder (Vietnamese Telex/VNI + Multiline)

private final class DirectCanvasNSTextView: NSTextView {
  var onResignFocus: (() -> Void)?
  var onLiveStringChange: ((String) -> Void)?

  override func didChangeText() {
    super.didChangeText()
    onLiveStringChange?(string)
  }

  override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    onLiveStringChange?(self.string)
  }

  override func unmarkText() {
    super.unmarkText()
    onLiveStringChange?(string)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window else { return }
    DispatchQueue.main.async { [weak self, weak window] in
      guard let self, let window else { return }
      if window.firstResponder !== self {
        window.makeFirstResponder(self)
      }
      let end = (string as NSString).length
      setSelectedRange(NSRange(location: end, length: 0))
    }
  }

  override func resignFirstResponder() -> Bool {
    let ok = super.resignFirstResponder()
    if ok {
      onResignFocus?()
    }
    return ok
  }
}

private struct CanvasDirectTextResponder: NSViewRepresentable {
  @Binding var text: String
  var focusGeneration: Int
  var onCommit: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> DirectCanvasNSTextView {
    let tv = DirectCanvasNSTextView(frame: NSRect(x: 0, y: 0, width: 2, height: 2))
    tv.delegate = context.coordinator
    tv.isEditable = true
    tv.isSelectable = true
    tv.isRichText = false
    tv.importsGraphics = false
    tv.drawsBackground = false
    tv.isAutomaticQuoteSubstitutionEnabled = false
    tv.isAutomaticDashSubstitutionEnabled = false
    tv.isAutomaticTextReplacementEnabled = false
    tv.isContinuousSpellCheckingEnabled = false
    tv.isHorizontallyResizable = true
    tv.isVerticallyResizable = true
    tv.textContainer?.widthTracksTextView = false
    tv.textContainer?.heightTracksTextView = false
    tv.textContainer?.containerSize = NSSize(width: 4096, height: 4096)
    tv.textColor = .clear
    tv.insertionPointColor = .clear
    tv.string = text
    let end = (text as NSString).length
    tv.setSelectedRange(NSRange(location: end, length: 0))
    tv.onLiveStringChange = { [weak coordinator = context.coordinator] updated in
      coordinator?.handleLiveTextChange(updated)
    }
    tv.onResignFocus = { [weak coordinator = context.coordinator] in
      coordinator?.handleFocusLost()
    }
    return tv
  }

  func updateNSView(_ nsView: DirectCanvasNSTextView, context: Context) {
    context.coordinator.parent = self
    // Do not clobber active IME marked text composition mid-keystroke.
    if !nsView.hasMarkedText(), nsView.string != text {
      context.coordinator.isProgrammaticUpdate = true
      nsView.string = text
      let end = (text as NSString).length
      nsView.setSelectedRange(NSRange(location: end, length: 0))
      context.coordinator.isProgrammaticUpdate = false
    }
    if context.coordinator.lastFocusGeneration != focusGeneration {
      context.coordinator.lastFocusGeneration = focusGeneration
      DispatchQueue.main.async { [weak nsView] in
        guard let nsView, let window = nsView.window else { return }
        if window.firstResponder !== nsView {
          window.makeFirstResponder(nsView)
        }
      }
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: CanvasDirectTextResponder
    var isProgrammaticUpdate = false
    var lastFocusGeneration = -1
    private var didCommit = false

    init(_ parent: CanvasDirectTextResponder) {
      self.parent = parent
    }

    func handleLiveTextChange(_ updated: String) {
      guard !isProgrammaticUpdate, parent.text != updated else { return }
      parent.text = updated
    }

    func textDidChange(_ notification: Notification) {
      guard !isProgrammaticUpdate,
            let tv = notification.object as? NSTextView
      else { return }
      handleLiveTextChange(tv.string)
    }

    func handleFocusLost() {
      guard !didCommit else { return }
      didCommit = true
      let commit = parent.onCommit
      DispatchQueue.main.async {
        commit()
      }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        if textView.hasMarkedText() {
          return false
        }
        guard !didCommit else { return true }
        didCommit = true
        parent.onCommit()
        return true
      }
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        if let event = NSApp.currentEvent, event.modifierFlags.contains(.command) {
          guard !didCommit else { return true }
          didCommit = true
          parent.onCommit()
          return true
        }
        textView.insertNewlineIgnoringFieldEditor(nil)
        return true
      }
      return false
    }
  }
}
