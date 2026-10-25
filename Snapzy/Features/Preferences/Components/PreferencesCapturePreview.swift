//
//  PreferencesCapturePreview.swift
//  Snapzy
//
//  Animated preview above the Capture tab's segmented control. Shows the
//  top-right corner of a display and plays a short, looping simulation of the
//  active pane (area selection, screenshot, recording, OCR) using the live
//  preference values.
//

import SwiftUI

enum CaptureSettingsPreviewScene: Hashable {
  case general
  case screenshot
  case recording
  case ocr
}

struct CaptureSettingsPreview: View {
  let scene: CaptureSettingsPreviewScene

  // General
  @AppStorage(PreferencesKeys.screenshotShowSelectionAreaOverlay) private var showSelectionAreaOverlay = true
  @AppStorage(PreferencesKeys.screenshotAutoDetectWindowUnderCursor) private var autoDetectWindow = false
  @AppStorage(PreferencesKeys.screenshotAutoDetectElementUnderCursor) private var autoDetectElement = false
  @AppStorage(PreferencesKeys.screenshotShowMagnifierByDefault) private var showMagnifier = false
  @AppStorage(PreferencesKeys.screenshotShowMagnifierColorPanel) private var showMagnifierColorPanel = true
  @AppStorage(PreferencesKeys.screenshotMagnifierSize)
  private var magnifierSize = MagnifierSizeOption.defaultValue.rawValue

  // Screenshot
  @AppStorage(PreferencesKeys.screenshotShowCursor) private var screenshotShowCursor = false
  @AppStorage(PreferencesKeys.captureIncludeWindowShadow) private var includeWindowShadow = true
  @AppStorage(PreferencesKeys.screenshotDelayedCaptureSeconds)
  private var delayedCaptureSeconds = CaptureDelayOption.defaultValue.seconds
  @AppStorage(PreferencesKeys.screenshotFormat) private var screenshotFormat = "png"

  // Recording
  @AppStorage(PreferencesKeys.recordingFormat) private var recordingFormat = "mov"
  @AppStorage(PreferencesKeys.recordingFPS) private var fps = 30
  @AppStorage(PreferencesKeys.recordingQuality) private var quality = "high"
  @AppStorage(PreferencesKeys.recordingMaxResolution) private var maxResolution = "auto"
  @AppStorage(PreferencesKeys.recordingCaptureAudio) private var captureAudio = true
  @AppStorage(PreferencesKeys.recordingCaptureMicrophone) private var captureMicrophone = false
  @AppStorage(PreferencesKeys.recordingShowCursor) private var recordingShowCursor = true
  @AppStorage(PreferencesKeys.recordingDimNonSelectedArea) private var dimNonSelectedArea = true
  @AppStorage(PreferencesKeys.recordingHoverBarVisible) private var hoverBarVisible = true
  @AppStorage(PreferencesKeys.recordingShowTimeOnMenuBar) private var showTimeOnMenuBar = true
  @AppStorage(PreferencesKeys.mouseHighlightSize) private var highlightSize: Double = 50
  @AppStorage(PreferencesKeys.mouseHighlightAnimationDuration) private var highlightDuration: Double = 0.7
  @AppStorage(PreferencesKeys.mouseHighlightRippleCount) private var rippleCount: Int = 3
  @AppStorage(PreferencesKeys.mouseHighlightOpacity) private var highlightOpacity: Double = 0.5
  @AppStorage(PreferencesKeys.mouseHighlightColor) private var highlightColorData: Data?
  @AppStorage(PreferencesKeys.keystrokeFontSize) private var keystrokeFontSize: Double = 16
  @AppStorage(PreferencesKeys.keystrokePosition)
  private var keystrokePosition = KeystrokeOverlayPosition.bottomCenter.rawValue
  @AppStorage(PreferencesKeys.keystrokeDisplayDuration) private var keystrokeDuration: Double = 1.5

  // OCR
  @AppStorage(PreferencesKeys.ocrSuccessNotificationEnabled) private var ocrNotification = true
  @AppStorage(PreferencesKeys.ocrLinkDetectionEnabled) private var ocrLinkDetection = true

  @ObservedObject private var quickAccessActions = QuickAccessActionConfigurationStore.shared

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Current step of the scene's script; every visual is a pure function of it.
  @State private var step = 0
  /// Running clock for the recording timer.
  @State private var elapsed = 0
  /// Bumped on each simulated click so ripples restart.
  @State private var clickCount = 0

  // MARK: - Canvas

  /// All geometry is authored on this canvas (the visible screen area) and
  /// scaled to the available width.
  private static let canvas = CGSize(width: 600, height: 230)
  private static let menuBarHeight: CGFloat = 18
  /// The Notes window runs past the bottom edge, like the crop itself.
  private static let windowRect = CGRect(x: 116, y: 38, width: 364, height: 240)
  /// Share button in the Notes toolbar, used for element detection.
  private static let elementRect = CGRect(
    x: windowRect.maxX - 12 - 20,
    y: windowRect.minY + 8,
    width: 20,
    height: 20
  )

  private static let selectionInk = Color(red: 0.06, green: 0.08, blue: 0.16)

  var body: some View {
    DisplayCornerFrame {
      GeometryReader { proxy in
        sceneCanvas
          // Top-leading: the Notes window deliberately runs past the bottom
          // edge, which grows the ZStack; centering would shift the whole scene
          // up and leave the bottom strip uncovered by dims and the spec scrim.
          .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
          // Cover, not fit, so sub-pixel rounding never leaves a sliver.
          .scaleEffect(
            max(proxy.size.width / Self.canvas.width, proxy.size.height / Self.canvas.height),
            anchor: .topLeading
          )
      }
      .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
    }
    .task(id: scriptID) { await runScript() }
    .accessibilityHidden(true)
  }

  private var sceneCanvas: some View {
    ZStack(alignment: .topLeading) {
      PaintedSkyBackdrop()

      notesWindow
      // Capture overlays sit above the menu bar, so dimming covers the whole display.
      menuBar

      switch scene {
      case .general: generalLayer
      case .screenshot: screenshotLayer
      case .recording: recordingLayer
      case .ocr: ocrLayer
      }

      specLine
    }
    .environment(\.colorScheme, .dark)
  }

  // MARK: - Script

  /// Restarts the loop whenever the pane or a timing-relevant value changes.
  private var scriptID: String {
    "\(scene)-\(keystrokeDuration)-\(reduceMotion)"
  }

  private var stepDurations: [Double] {
    switch scene {
    case .general: return [0.8, 0.9, 0.5, 1.3, 1.0, 0.6]
    case .screenshot: return [0.8, 0.8, 0.25, 0.9, 1.6, 0.6]
    case .recording: return Array(repeating: 1.0, count: 8)
    case .ocr: return [0.7, 0.45, 1.0, 1.0, 1.8, 0.5]
    }
  }

  /// Representative still frame when Reduce Motion is on.
  private var restingStep: Int {
    scene == .recording ? 2 : 4
  }

  @MainActor
  private func runScript() async {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { step = 0 }

    guard !reduceMotion else {
      withTransaction(transaction) { step = restingStep }
      return
    }

    // State changes only a few times a second; SwiftUI interpolates the rest
    // on the render server, so the loop itself costs almost nothing.
    let durations = stepDurations
    while !Task.isCancelled {
      for (index, duration) in durations.enumerated() {
        withAnimation(.easeInOut(duration: min(duration, 0.8))) { step = index }
        if scene == .recording {
          elapsed += 1
          if index == 1 || index == 4 { clickCount += 1 }
        }
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        if Task.isCancelled { return }
      }
    }
  }

  // MARK: - Desktop

  private var isCaptureActive: Bool {
    switch scene {
    case .general: return (1...4).contains(step)
    case .screenshot: return (1...2).contains(step)
    case .recording: return true
    case .ocr: return (1...3).contains(step)
    }
  }

  // MARK: - Menu Bar

  private var menuBar: some View {
    HStack(spacing: 12) {
      Spacer(minLength: 0)

      if scene == .recording && showTimeOnMenuBar {
        HStack(spacing: 4) {
          Circle().fill(Color.red).frame(width: 6, height: 6)
          Text(timerText).monospacedDigit()
        }
        .transition(.opacity)
      }

      Image(systemName: "wifi")
      Image(systemName: "battery.75percent")
      Text(Date(), format: .dateTime.weekday(.abbreviated).hour().minute())
        .padding(.trailing, 12)
    }
    .font(.system(size: 10, weight: .medium))
    .foregroundStyle(.white)
    .frame(width: Self.canvas.width, height: Self.menuBarHeight)
    .background(Color.white.opacity(0.12))
  }

  private var timerText: String {
    String(format: "%02d:%02d", (elapsed / 60) % 60, elapsed % 60)
  }

  // MARK: - Notes Window

  private var notesWindow: some View {
    NotesWindowSnapshot(
      size: Self.windowRect.size,
      highlightsLink: scene == .ocr && ocrLinkDetection && step == 4,
      shadowOpacity: 0.32
    )
    .frame(width: Self.windowRect.width, height: Self.windowRect.height)
    .offset(x: Self.windowRect.minX, y: Self.windowRect.minY)
  }

  // MARK: - General (area selection)

  private var generalSelection: CGRect? {
    switch step {
    case 2: return CGRect(x: 226, y: 70, width: 0, height: 0)
    case 3, 4: return CGRect(x: 226, y: 70, width: 196, height: 112)
    default: return nil
    }
  }

  private var generalCursor: CGPoint {
    switch step {
    case 1:
      return autoDetectWindow && autoDetectElement
        ? CGPoint(x: Self.elementRect.midX, y: Self.elementRect.midY)
        : CGPoint(x: 330, y: 132)
    case 2: return CGPoint(x: 226, y: 70)
    case 3, 4: return CGPoint(x: 422, y: 182)
    default: return CGPoint(x: 512, y: 204)
    }
  }

  private var detectionRect: CGRect? {
    guard step == 1, autoDetectWindow else { return nil }
    return autoDetectElement ? Self.elementRect : Self.windowRect
  }

  private var generalLayer: some View {
    ZStack(alignment: .topLeading) {
      if isCaptureActive && showSelectionAreaOverlay {
        DimOutsideShape(hole: generalSelection ?? detectionRect ?? .zero)
          .fill(Color.black.opacity(0.4), style: FillStyle(eoFill: true))
          .transition(.opacity)
      }

      if let detectionRect {
        Rectangle()
          .fill(Color.accentColor.opacity(0.16))
          .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 1.5))
          .frame(width: detectionRect.width, height: detectionRect.height)
          .offset(x: detectionRect.minX, y: detectionRect.minY)
          .transition(.opacity)
      }

      if let selection = generalSelection {
        selectionFrame(selection)

        if selection.width > 0 {
          sizeIndicator(for: selection, at: generalCursor)
            .transition(.opacity)
        }
      }

      if showMagnifier && (2...4).contains(step) {
        magnifier
          .position(x: generalCursor.x - 74, y: generalCursor.y - 56)
          .transition(.opacity.combined(with: .scale(scale: 0.85)))
      }

      cursor(at: generalCursor, crosshair: isCaptureActive)
    }
  }

  private var magnifierDiameter: CGFloat {
    switch MagnifierSizeOption(rawValue: magnifierSize) ?? .defaultValue {
    case .small: return 56
    case .medium: return 68
    case .large: return 84
    }
  }

  private var magnifier: some View {
    VStack(spacing: 4) {
      ZStack {
        Color.white
        PixelGrid()
          .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        Rectangle()
          .strokeBorder(Self.selectionInk, lineWidth: 1)
          .frame(width: 7, height: 7)
      }
      .frame(width: magnifierDiameter, height: magnifierDiameter)
      .clipShape(Circle())
      .overlay(Circle().strokeBorder(Self.selectionInk.opacity(0.85), lineWidth: 1.5))

      if showMagnifierColorPanel {
        HStack(spacing: 4) {
          RoundedRectangle(cornerRadius: 2) // radius-lint:allow tiny color swatch
            .fill(Color.white)
            .frame(width: 8, height: 8)
          Text("#FFFFFF")
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(Self.selectionInk.opacity(0.85)))
      }
    }
  }

  // MARK: - Screenshot (window capture → Quick Access)

  private static let quickAccessScale: CGFloat = 0.62
  private static let quickAccessOrigin = CGPoint(
    x: canvas.width - 14 - QuickAccessLayout.cardWidth * quickAccessScale,
    y: canvas.height - 14 - QuickAccessLayout.cardHeight * quickAccessScale
  )

  private var screenshotCursor: CGPoint {
    switch step {
    case 1, 2: return CGPoint(x: 330, y: 132)
    case 4:
      return CGPoint(
        x: Self.quickAccessOrigin.x + QuickAccessLayout.cardWidth * Self.quickAccessScale * 0.62,
        y: Self.quickAccessOrigin.y + QuickAccessLayout.cardHeight * Self.quickAccessScale * 0.7
      )
    default: return CGPoint(x: 512, y: 204)
    }
  }

  private var screenshotLayer: some View {
    ZStack(alignment: .topLeading) {
      if step == 1 {
        Rectangle()
          .fill(Color.accentColor.opacity(0.16))
          .frame(width: Self.windowRect.width, height: Self.windowRect.height)
          .offset(x: Self.windowRect.minX, y: Self.windowRect.minY)
          .transition(.opacity)
      }

      // Shutter flash over the captured window.
      Rectangle()
        .fill(Color.white)
        .frame(width: Self.windowRect.width, height: Self.windowRect.height)
        .offset(x: Self.windowRect.minX, y: Self.windowRect.minY)
        .opacity(step == 2 ? 0.8 : 0)

      if (3...4).contains(step) {
        quickAccessCard(isHovered: step == 4)
          .scaleEffect(Self.quickAccessScale, anchor: .topLeading)
          .offset(x: Self.quickAccessOrigin.x, y: Self.quickAccessOrigin.y)
          .transition(.offset(x: 140).combined(with: .opacity))
      }

      cursor(at: screenshotCursor, crosshair: false)
    }
  }

  /// Mirrors the real Quick Access card at its native size: captured image,
  /// hover scrim, configured center actions and corner buttons.
  private func quickAccessCard(isHovered: Bool) -> some View {
    let size = CGSize(width: QuickAccessLayout.cardWidth, height: QuickAccessLayout.cardHeight)

    return ZStack {
      capturedImage(in: size)

      if isHovered {
        Color.black.opacity(0.38)

        VStack(spacing: 8) {
          ForEach(QuickAccessActionSlot.centerSlots) { slot in
            if let action = enabledAction(in: slot) {
              Text(action.settingsTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule(style: .continuous).fill(Color.black.opacity(0.62)))
            }
          }
        }

        ForEach(QuickAccessActionSlot.cornerSlots) { slot in
          if let action = enabledAction(in: slot) {
            Image(systemName: action.systemImage)
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(.white)
              .frame(width: 20, height: 20)
              .background(Circle().fill(Color.black.opacity(0.62)))
              .padding(8)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cornerAlignment(slot))
          }
        }
      }
    }
    .frame(width: size.width, height: size.height)
    .clipShape(Radius.rect(Radius.card))
    .overlay(Radius.rect(Radius.card).stroke(Color.white.opacity(0.2), lineWidth: 1))
    .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
    .animation(.easeInOut(duration: 0.2), value: isHovered)
  }

  /// What the saved image contains: the window, plus its shadow margin and the
  /// pointer only when those options are on.
  private func capturedImage(in size: CGSize) -> some View {
    let window = Self.windowRect.size
    let margin: CGFloat = includeWindowShadow ? 22 : 0
    let fit = min(size.width / (window.width + margin * 2), size.height / (window.height + margin * 2))
    let fill = max(size.width / window.width, size.height / window.height)
    let scale = includeWindowShadow ? fit : fill
    let cursorPoint = CGPoint(x: 330 - Self.windowRect.minX, y: 132 - Self.windowRect.minY)

    return ZStack {
      // Transparent shadow margin shows the card's own dark backing.
      Color(white: includeWindowShadow ? 0.22 : 0.97)

      ZStack(alignment: .topLeading) {
        NotesWindowSnapshot(
          size: window,
          highlightsLink: false,
          shadowOpacity: includeWindowShadow ? 0.45 : 0
        )
        .frame(width: window.width, height: window.height)

        if screenshotShowCursor {
          Image(nsImage: NSCursor.arrow.image)
            .resizable()
            .frame(width: 14, height: 19)
            .offset(x: cursorPoint.x, y: cursorPoint.y)
        }
      }
      .frame(width: window.width, height: window.height)
      .scaleEffect(scale)
    }
    .frame(width: size.width, height: size.height)
    .clipped()
  }

  private func enabledAction(in slot: QuickAccessActionSlot) -> QuickAccessActionKind? {
    guard let action = quickAccessActions.action(in: slot),
          quickAccessActions.isEnabled(action) else { return nil }
    return action
  }

  private func cornerAlignment(_ slot: QuickAccessActionSlot) -> Alignment {
    switch slot {
    case .topLeading: return .topLeading
    case .topTrailing: return .topTrailing
    case .bottomLeading: return .bottomLeading
    case .bottomTrailing: return .bottomTrailing
    case .centerTop, .centerBottom: return .center
    }
  }

  // MARK: - Recording

  private static let recordingRect = CGRect(x: 132, y: 34, width: 320, height: 160)

  private static let recordingCursorPath: [CGPoint] = [
    CGPoint(x: 236, y: 84), CGPoint(x: 340, y: 120), CGPoint(x: 268, y: 156),
    CGPoint(x: 400, y: 82), CGPoint(x: 310, y: 148), CGPoint(x: 236, y: 172),
    CGPoint(x: 372, y: 170), CGPoint(x: 262, y: 104),
  ]

  private var recordingCursor: CGPoint {
    Self.recordingCursorPath[step % Self.recordingCursorPath.count]
  }

  private var highlightColor: Color {
    if let data = highlightColorData,
       let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
      return Color(nsColor: color)
    }
    return Color(nsColor: MouseHighlightConfiguration.defaultHighlightColor)
  }

  private var showsKeystroke: Bool {
    let length = max(1, Int(keystrokeDuration.rounded()))
    return (2..<(2 + length)).contains(step)
  }

  private var isClickStep: Bool {
    step == 1 || step == 4
  }

  private var recordingLayer: some View {
    let rect = Self.recordingRect

    return ZStack(alignment: .topLeading) {
      if dimNonSelectedArea {
        DimOutsideShape(hole: rect)
          .fill(Color.black.opacity(0.4), style: FillStyle(eoFill: true))
          .transition(.opacity)
      }
      // While recording the region has no border; only the dim marks it.

      ZStack {
        ForEach(0..<max(1, min(rippleCount, 5)), id: \.self) { index in
          ClickRipple(
            color: highlightColor,
            diameter: highlightSize * 0.7,
            opacity: highlightOpacity,
            duration: highlightDuration,
            delay: Double(index) * highlightDuration / Double(max(rippleCount, 1)) * 0.5
          )
        }
      }
      .id(clickCount)
      .position(Self.recordingCursorPath[isClickStep ? step : 1])
      .opacity(isClickStep ? 1 : 0)

      if showsKeystroke {
        keystrokeBadge
          .frame(width: rect.width - 20, height: rect.height - 20, alignment: keystrokeAlignment)
          .offset(x: rect.minX + 10, y: rect.minY + 10)
          .transition(.opacity)
      }

      if hoverBarVisible {
        recordingHoverBar
          .frame(width: rect.width)
          .offset(x: rect.minX, y: rect.maxY + 8)
      }

      cursor(at: recordingCursor, crosshair: false)
        .opacity(recordingShowCursor ? 1 : 0.35)
    }
  }

  private var keystrokeAlignment: Alignment {
    switch KeystrokeOverlayPosition(rawValue: keystrokePosition) ?? .bottomCenter {
    case .bottomCenter: return .bottom
    case .bottomLeft: return .bottomLeading
    case .bottomRight: return .bottomTrailing
    case .topCenter: return .top
    case .topLeft: return .topLeading
    case .topRight: return .topTrailing
    }
  }

  private var keystrokeBadge: some View {
    Text("⌘ ⇧ S")
      .font(.system(size: keystrokeFontSize * 0.7, weight: .semibold, design: .rounded))
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous) // radius-lint:allow mirrors keystroke overlay
          .fill(Color.black.opacity(0.72))
      )
  }

  private var recordingHoverBar: some View {
    HStack(spacing: 8) {
      Circle().fill(Color.red).frame(width: 7, height: 7)
      Text(timerText)
        .font(.system(size: 10, weight: .semibold))
        .monospacedDigit()
      Image(systemName: captureAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
      Image(systemName: captureMicrophone ? "mic.fill" : "mic.slash.fill")
      Image(systemName: "stop.fill")
    }
    .font(.system(size: 9))
    .foregroundStyle(.white)
    .padding(.horizontal, 10)
    .frame(height: 22)
    .background(Capsule().fill(Color.black.opacity(0.75)))
  }

  // MARK: - OCR

  /// Covers the note's body text and link.
  private static let ocrSelection = CGRect(x: 222, y: 106, width: 214, height: 66)

  private var ocrCursor: CGPoint {
    switch step {
    case 1: return CGPoint(x: Self.ocrSelection.minX, y: Self.ocrSelection.minY)
    case 2, 3: return CGPoint(x: Self.ocrSelection.maxX, y: Self.ocrSelection.maxY)
    default: return CGPoint(x: 512, y: 204)
    }
  }

  private var ocrLayer: some View {
    let selection = Self.ocrSelection

    return ZStack(alignment: .topLeading) {
      if (1...3).contains(step) {
        let rect = step == 1 ? CGRect(origin: selection.origin, size: .zero) : selection

        if showSelectionAreaOverlay {
          DimOutsideShape(hole: rect)
            .fill(Color.black.opacity(0.4), style: FillStyle(eoFill: true))
            .transition(.opacity)
        }
        selectionFrame(rect)
      }

      // Recognition sweep.
      if step == 3 {
        LinearGradient(
          colors: [Color.accentColor.opacity(0), Color.accentColor.opacity(0.4)],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(width: selection.width, height: 18)
        .offset(x: selection.minX, y: selection.maxY - 18)
        .transition(.asymmetric(insertion: .move(edge: .top), removal: .opacity))
      }

      if step == 4 && ocrNotification {
        notificationBanner
          .offset(x: 346, y: Self.menuBarHeight + 8)
          .transition(.offset(x: 260).combined(with: .opacity))
      }

      cursor(at: ocrCursor, crosshair: (1...3).contains(step))
    }
  }

  private var notificationBanner: some View {
    HStack(spacing: 8) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 22, height: 22)
      VStack(alignment: .leading, spacing: 1) {
        Text("Snapzy")
          .font(.system(size: 10, weight: .semibold))
        Text(L10n.OCR.notificationCopiedTitle)
          .font(.system(size: 9.5))
          .foregroundStyle(.white.opacity(0.75))
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .foregroundStyle(.white)
    .padding(8)
    .frame(width: 210)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous) // radius-lint:allow mirrors macOS notification
        .fill(Color(white: 0.16).opacity(0.94))
    )
  }

  // MARK: - Shared Pieces

  /// Matches AreaSelectionWindow: a 2pt white border. With the backdrop
  /// overlay off, the selection itself darkens instead (12% black fill and a
  /// 4pt 30% black edge under the border) so it still reads on light content.
  private func selectionFrame(_ rect: CGRect) -> some View {
    ZStack {
      if !showSelectionAreaOverlay {
        Rectangle()
          .fill(Color.black.opacity(0.12))
          .overlay(Rectangle().stroke(Color.black.opacity(0.3), lineWidth: 4))
      }
      Rectangle()
        .stroke(Color.white, lineWidth: 2)
    }
    .frame(width: rect.width, height: rect.height)
    .offset(x: rect.minX, y: rect.minY)
  }

  /// Two-line size readout beside the pointer, styled like the capture
  /// overlay's coordinate bubble: dark text with a crisp white offset shadow.
  private func sizeIndicator(for rect: CGRect, at point: CGPoint) -> some View {
    // Canvas points render at 2x on a Retina display.
    Text("\(Int(rect.width * 2))\n\(Int(rect.height * 2))")
      .font(.system(size: 10, weight: .medium))
      .monospacedDigit()
      .foregroundStyle(Color(white: 0.05))
      .shadow(color: .white, radius: 0.1, x: 0.5, y: 0.5)
      .fixedSize()
      .offset(x: point.x + 12, y: point.y - 30)
  }

  private func cursor(at point: CGPoint, crosshair: Bool) -> some View {
    Group {
      if crosshair {
        ZStack {
          Image(systemName: "plus")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
          Image(systemName: "plus")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Self.selectionInk)
        }
        .position(point)
      } else {
        Image(nsImage: NSCursor.arrow.image)
          .resizable()
          .frame(width: 14, height: 19)
          // Arrow hotspot sits at the image's top-left.
          .position(x: point.x + 6, y: point.y + 8)
      }
    }
  }

  // MARK: - Spec Line

  private var specValues: [String] {
    switch scene {
    case .general:
      return showMagnifier ? [(MagnifierSizeOption(rawValue: magnifierSize) ?? .defaultValue).displayName] : []
    case .screenshot:
      return [screenshotFormat.uppercased(), CaptureDelayOption.resolve(delayedCaptureSeconds).displayName]
    case .recording:
      return [
        recordingFormat.uppercased(),
        "\(fps) fps",
        quality.capitalized,
        maxResolution == "auto" ? "Auto" : maxResolution,
      ]
    case .ocr:
      return []
    }
  }

  private var specLine: some View {
    Text(specValues.joined(separator: "  ·  "))
      .font(.system(size: 10, weight: .semibold, design: .rounded))
      .monospacedDigit()
      .foregroundStyle(.white)
      .padding(.leading, 14)
      .padding(.bottom, 9)
      .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .bottomLeading)
      .background(alignment: .bottom) {
        // Legibility scrim over the bright cloud bank, not a container.
        LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
          .frame(height: 40)
      }
      .opacity(specValues.isEmpty ? 0 : 1)
      .allowsHitTesting(false)
  }
}

// MARK: - Mock Notes Window

/// The Notes window with its drop shadow, rasterized once per variant and
/// shared. Text layout and the large shadow blur are the costliest parts of the
/// scene, so on screen they reduce to one static bitmap that animations never
/// invalidate. The image bleeds past the frame to carry the shadow without
/// affecting layout.
private struct NotesWindowSnapshot: View {
  let size: CGSize
  let highlightsLink: Bool
  let shadowOpacity: Double

  private static let bleed: CGFloat = 32
  @MainActor private static var cache: [String: CGImage] = [:]

  var body: some View {
    Color.clear
      .overlay {
        if let image = Self.image(size: size, highlightsLink: highlightsLink, shadowOpacity: shadowOpacity) {
          Image(decorative: image, scale: 2)
            .resizable()
            .frame(width: size.width + Self.bleed * 2, height: size.height + Self.bleed * 2)
        } else {
          Self.window(size: size, highlightsLink: highlightsLink, shadowOpacity: shadowOpacity)
        }
      }
  }

  private static func window(size: CGSize, highlightsLink: Bool, shadowOpacity: Double) -> some View {
    MockNotesWindow(highlightsLink: highlightsLink)
      .frame(width: size.width, height: size.height)
      .shadow(color: .black.opacity(shadowOpacity), radius: 14, x: 0, y: 8)
  }

  @MainActor
  private static func image(size: CGSize, highlightsLink: Bool, shadowOpacity: Double) -> CGImage? {
    let key = "\(size.width)x\(size.height)-\(highlightsLink)-\(shadowOpacity)"
    if let cached = cache[key] { return cached }

    let renderer = ImageRenderer(
      content: window(size: size, highlightsLink: highlightsLink, shadowOpacity: shadowOpacity)
        .padding(bleed)
    )
    renderer.scale = 2
    guard let image = renderer.cgImage else { return nil }
    cache[key] = image
    return image
  }
}

/// A trimmed macOS Notes window: inset sidebar, toolbar, and a note with a
/// checklist and a link.
private struct MockNotesWindow: View {
  let highlightsLink: Bool

  private static let notesYellow = Color(red: 0.89, green: 0.68, blue: 0.0)
  private static let ink = Color(white: 0.12)
  private static let secondaryInk = Color(white: 0.52)

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      editor
    }
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) // radius-lint:allow mimics macOS 26 window
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous) // radius-lint:allow mimics macOS 26 window
        .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
    )
    .environment(\.colorScheme, .light)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 5) {
        Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
        Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
        Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
      }
      .frame(width: 40, height: 9)
      .padding(.bottom, 12)

      Text("iCloud")
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(Self.secondaryInk)
        .padding(.leading, 4)

      sidebarRow("All iCloud", count: 24, selected: false)
      sidebarRow("Notes", count: 12, selected: true)
      sidebarRow("Ideas", count: 5, selected: false)

      Spacer(minLength: 0)
    }
    .padding(9)
    .frame(width: 96)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(
      RoundedRectangle(cornerRadius: 9, style: .continuous) // radius-lint:allow mimics macOS 26 inset sidebar
        .fill(Color(white: 0.94))
        .padding(5)
    )
  }

  private func sidebarRow(_ title: String, count: Int, selected: Bool) -> some View {
    HStack(spacing: 5) {
      Image(systemName: "folder")
        .font(.system(size: 9))
        .foregroundStyle(Self.notesYellow)
      Text(title)
        .font(.system(size: 9))
        .foregroundStyle(Self.ink)
      Spacer(minLength: 0)
      Text("\(count)")
        .font(.system(size: 8))
        .foregroundStyle(Self.secondaryInk)
    }
    .padding(.horizontal, 5)
    .frame(height: 18)
    .background(
      RoundedRectangle(cornerRadius: 5, style: .continuous) // radius-lint:allow mimics sidebar selection
        .fill(selected ? Color.black.opacity(0.08) : Color.clear)
    )
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 4) {
        Spacer()
        ForEach(["textformat", "checklist", "tablecells", "square.and.arrow.up"], id: \.self) { symbol in
          Image(systemName: symbol)
            .font(.system(size: 10))
            .foregroundStyle(Self.secondaryInk)
            .frame(width: 20, height: 20)
        }
      }
      .padding(.top, 8)
      .padding(.trailing, 12)

      Text("25 October 2026 at 09:41")
        .font(.system(size: 7.5))
        .foregroundStyle(Self.secondaryInk)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)

      VStack(alignment: .leading, spacing: 5) {
        Text("Launch checklist")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(Self.ink)
          .padding(.bottom, 2)

        Text("Ship the capture previews before the")
        Text("weekly build, then share the changelog:")

        Text("snapzy.app/changelog")
          .foregroundStyle(highlightsLink ? Color.accentColor : Self.ink)
          .underline(highlightsLink)

        checklistRow("Record the demo", done: true)
        checklistRow("Update screenshots", done: false)
        checklistRow("Post release notes", done: false)
      }
      .font(.system(size: 9.5))
      .foregroundStyle(Self.ink)
      .padding(.horizontal, 18)
      .padding(.top, 8)

      Spacer(minLength: 0)
    }
  }

  private func checklistRow(_ title: String, done: Bool) -> some View {
    HStack(spacing: 6) {
      Image(systemName: done ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 10))
        .foregroundStyle(done ? Self.notesYellow : Self.secondaryInk)
      Text(title)
        .strikethrough(done, color: Self.secondaryInk)
        .foregroundStyle(done ? Self.secondaryInk : Self.ink)
    }
  }
}

// MARK: - Shapes & Effects

/// Full-canvas dim with an animatable rectangular hole.
private struct DimOutsideShape: Shape {
  var hole: CGRect

  var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
    get { .init(.init(hole.minX, hole.minY), .init(hole.width, hole.height)) }
    set {
      hole = CGRect(
        x: newValue.first.first,
        y: newValue.first.second,
        width: newValue.second.first,
        height: newValue.second.second
      )
    }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path(rect)
    if hole.width > 0, hole.height > 0 {
      path.addRect(hole)
    }
    return path
  }
}

private struct PixelGrid: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let cell: CGFloat = 7
    var x = rect.midX.truncatingRemainder(dividingBy: cell) - cell / 2
    while x < rect.maxX {
      path.move(to: CGPoint(x: x, y: rect.minY))
      path.addLine(to: CGPoint(x: x, y: rect.maxY))
      x += cell
    }
    var y = rect.midY.truncatingRemainder(dividingBy: cell) - cell / 2
    while y < rect.maxY {
      path.move(to: CGPoint(x: rect.minX, y: y))
      path.addLine(to: CGPoint(x: rect.maxX, y: y))
      y += cell
    }
    return path
  }
}

/// One expanding ring; recreated per click via `.id`, so it animates exactly once.
private struct ClickRipple: View {
  let color: Color
  let diameter: CGFloat
  let opacity: Double
  let duration: Double
  let delay: Double

  @State private var progress: CGFloat = 0

  var body: some View {
    Circle()
      .stroke(color, lineWidth: 2)
      .background(Circle().fill(color.opacity(0.35)))
      .frame(width: diameter, height: diameter)
      .scaleEffect(0.2 + progress * 0.8)
      .opacity(opacity * Double(1 - progress))
      .onAppear {
        withAnimation(.easeOut(duration: duration).delay(delay)) { progress = 1 }
      }
  }
}

#Preview {
  CaptureSettingsPreview(scene: .screenshot)
    .frame(width: 600)
}
