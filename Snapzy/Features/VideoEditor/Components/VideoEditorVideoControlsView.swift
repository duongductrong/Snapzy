//
//  VideoEditorVideoControlsView.swift
//  Snapzy
//
//  Playback controls with play/pause button and time display
//

import AppKit
import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

private enum VideoControlsLayoutStyle {
  case compact
  case regular
  case expanded

  static func forWidth(_ width: CGFloat) -> Self {
    switch width {
    case ..<640:
      .compact
    case ..<920:
      .regular
    default:
      .expanded
    }
  }

  var outerSpacing: CGFloat {
    switch self {
    case .compact: 12
    case .regular: 14
    case .expanded: 16
    }
  }

  var centerSpacing: CGFloat {
    switch self {
    case .compact: 10
    case .regular: 12
    case .expanded: 14
    }
  }

  var verticalPadding: CGFloat {
    switch self {
    case .compact: 6
    case .regular: 7
    case .expanded: 8
    }
  }

  var metadataSpacing: CGFloat {
    switch self {
    case .compact: 6
    case .regular: 7
    case .expanded: 8
    }
  }

  var timeLabelWidth: CGFloat {
    switch self {
    case .compact: 42
    case .regular: 46
    case .expanded: 50
    }
  }

  var timeFontSize: CGFloat {
    switch self {
    case .compact: 12
    case .regular, .expanded: 13
    }
  }

  var transportButtonSize: CGFloat {
    switch self {
    case .compact: 24
    case .regular: 26
    case .expanded: 28
    }
  }

  var transportIconSize: CGFloat {
    switch self {
    case .compact: 15
    case .regular: 16
    case .expanded: 18
    }
  }

  var playButtonSize: CGFloat {
    switch self {
    case .compact: 40
    case .regular: 42
    case .expanded: 44
    }
  }

  var playIconSize: CGFloat {
    switch self {
    case .compact: 16
    case .regular: 18
    case .expanded: 20
    }
  }

  var badgeIconSize: CGFloat {
    switch self {
    case .compact: 10
    case .regular, .expanded: 11
    }
  }

  var badgeFontSize: CGFloat {
    switch self {
    case .compact: 10
    case .regular, .expanded: 11
    }
  }
}

private enum VideoControlsPart: Hashable {
  case status, zoom, trailingFrame
}

/// The one rule the status badges are shown under: their group has to fit the width the trailing
/// side of the row was actually given.
///
/// That width is measured from the laid-out side frame rather than derived, because the row's
/// division is the only thing the badges are judged against and it is not something the row can
/// promise: the transport is centred by two equally flexible side frames, a side that needs more
/// than its half takes it, and the widths involved (spacings, glyph sizes, the layout style the
/// row switches between) all move with the theme and the zoom level.
///
/// What the measurement does capture is the asymmetry that produced issue #780. The badges are
/// wrapped in `.frame(minWidth: 0)` on purpose, so the row's minimum keeps no room for them and
/// an over-wide badge group can neither buy width from the leading side nor push the row wider —
/// it keeps its `.fixedSize()` width and paints over the duration readout. A cluster that is part
/// of the minimum behaves differently: it grows its frame, which costs the transport its centring
/// but never overlaps. Comparing the group with the container instead — the old check — prices the
/// badges as though they were part of the minimum, and at the reported size the row really does
/// pack into 530 pt with them on while the trailing frame is only 147 pt of it.
enum VideoControlsFitPolicy {
  /// Whether the zoom cluster and the status badges fit inside the trailing side's measured width.
  /// An unknown or empty measurement shows the badges, matching the first layout pass.
  static func showsStatus(
    trailingWidth: CGFloat,
    zoomWidth: CGFloat,
    statusWidth: CGFloat,
    badgeSpacing: CGFloat
  ) -> Bool {
    guard trailingWidth > 0, zoomWidth > 0, statusWidth > 0 else { return true }
    return trailingWidth >= zoomWidth + badgeSpacing + statusWidth
  }
}

private struct VideoControlsPartWidthKey: PreferenceKey {
  static var defaultValue: [VideoControlsPart: CGFloat] = [:]

  static func reduce(
    value: inout [VideoControlsPart: CGFloat],
    nextValue: () -> [VideoControlsPart: CGFloat]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

private extension View {
  func measureVideoControlsPart(_ part: VideoControlsPart) -> some View {
    background(
      GeometryReader { proxy in
        Color.clear.preference(key: VideoControlsPartWidthKey.self, value: [part: proxy.size.width])
      }
    )
  }
}

private struct VideoControlsContainerWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

/// Playback controls view with play/pause and time display
///
/// The bar observes the editor state only. The playhead-driven parts (current time,
/// play/pause glyph, auto-zoom badge) are leaf views that subscribe to the playback
/// stream themselves, so a playback tick never re-runs this whole glass row.
struct VideoControlsView: View {
  @ObservedObject var state: VideoEditorState
  private let playbackState: VideoEditorPlaybackState
  /// While the AI runs, the clip tools lock (play and stepping stay live). Follows the
  /// agent's `chrome` snapshot only, so status, transcript and focus-request updates
  /// during a run don't re-render the bar.
  private let agent: VideoEditorAgentController
  @State private var aiChrome = VideoEditorAgentController.Chrome()
  private let stepIntervalSeconds: Double = 1.0
  @State private var containerWidth: CGFloat = 0
  /// Natural widths of the row's parts. None depends on whether the status badges show,
  /// so the show/hide decision can't feed back into its own inputs.
  @State private var partWidths: [VideoControlsPart: CGFloat] = [:]

  init(state: VideoEditorState) {
    _state = ObservedObject(wrappedValue: state)
    playbackState = state.playbackState
    agent = state.agent
    _aiChrome = State(initialValue: state.agent.chrome)
  }

  var body: some View {
    let _ = VideoEditorRenderRateGuard.record("VideoControlsView", isPlaying: playbackState.isPlaying)
    // Both sides are equally flexible, so the transport stays centred whenever each half
    // fits its side; when it doesn't, the row goes asymmetric and then drops the status
    // badges instead of demanding width. The bar must stay compressible: its minimum
    // width feeds the window's content minimum (NSHostingView `.minSize`), and a rigid
    // row made ⌘K's sidebar reservation grow the window instead of narrowing the editor.
    // (Not `ViewThatFits`: probing both glass candidates on every layout pass made each
    // editor layout ~15× slower.)
    HStack(spacing: controlsLayout.outerSpacing) {
      leftActions
        .disabled(aiChrome.isRunning)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)

      centerTransport
        .fixedSize(horizontal: true, vertical: false)

      rightActions(showsStatus: showsStatus)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .measureVideoControlsPart(.trailingFrame)
    }
    .onPreferenceChange(VideoControlsPartWidthKey.self) { widths in
      if partWidths != widths { partWidths = widths }
    }
    .padding(.vertical, controlsLayout.verticalPadding)
    .frame(maxWidth: .infinity)
    .background(
      GeometryReader { proxy in
        Color.clear.preference(key: VideoControlsContainerWidthKey.self, value: proxy.size.width)
      }
    )
    .onPreferenceChange(VideoControlsContainerWidthKey.self) { width in
      containerWidth = width
    }
    .onReceive(agent.chromePublisher) { aiChrome = $0 }
  }

  /// Whether the status badges fit beside the zoom cluster inside the width the trailing side was
  /// laid out in. See `VideoControlsFitPolicy` for why that measured frame, and not the row's
  /// leftover space, is what the badges have to live in.
  private var showsStatus: Bool {
    guard let trailing = partWidths[.trailingFrame],
          let zoom = partWidths[.zoom],
          let status = partWidths[.status]
    else { return true }
    return VideoControlsFitPolicy.showsStatus(
      trailingWidth: trailing,
      zoomWidth: zoom,
      statusWidth: status,
      badgeSpacing: controlsLayout.metadataSpacing
    )
  }

  private var controlsLayout: VideoControlsLayoutStyle {
    VideoControlsLayoutStyle.forWidth(containerWidth > 0 ? containerWidth : 920)
  }

  private var leftActions: some View {
    // Clip-editing (cut) controls share one quiet glass capsule — same treatment and
    // metrics as the zoom cluster on the trailing edge — so the row reads as a
    // matching pair of grouped instrument chips.
    HStack(spacing: 4) {
      cutButton(icon: "scissors", isDisabled: !state.canSplitAtPlayhead) {
        state.splitAtPlayhead()
      }
      .keyboardShortcut(aiChrome.allowsPlainKeyShortcuts ? KeyboardShortcut("s", modifiers: []) : nil)
      .help(L10n.VideoEditor.splitAtPlayheadHint)

      cutButton(icon: "trash", isDisabled: !state.canDeleteSelectedClip) {
        state.deleteSelectedClip()
      }
      .keyboardShortcut(aiChrome.allowsPlainKeyShortcuts ? KeyboardShortcut(.delete, modifiers: []) : nil)
      .help(L10n.VideoEditor.deleteClipHint)

      cutButton(icon: "plus.viewfinder", isDisabled: false) {
        insertClipsViaPicker()
      }
      .help(L10n.VideoEditor.addClipHint)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .liquidGlassChrome(
      shape: Capsule(style: .continuous),
      isVisible: true,
      isActive: false
    )
  }

  /// Icon control inside the cut group capsule, sized down from the transport cluster
  /// (which is tuned for the big play button) to the compact chip scale of
  /// `TimelineZoomControls`. Disabled dimming lives on the glyph only, never as an
  /// `.opacity()` around the glass surface (Rule 2).
  private func cutButton(
    icon: String,
    isDisabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(isDisabled ? Color.primary.opacity(0.4) : .primary)
        // Square frames keep each hit target equal and give the glyphs even breathing
        // room, so the group's rhythm does not follow each symbol's natural width.
        .frame(width: 16, height: 14)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
  }

  private func insertClipsViaPicker() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = ["mov", "mp4", "m4v"].compactMap { UTType(filenameExtension: $0) }
    panel.message = L10n.VideoEditor.addClipPickerMessage
    guard panel.runModal() == .OK else { return }
    // Insert at the playhead, keeping the picker's order for a multi-file selection.
    Task { @MainActor in
      var index = state.insertionIndexAtPlayhead
      for url in panel.urls {
        if await state.insertClip(url: url, at: index) != nil {
          index += 1
        }
      }
    }
  }

  private var centerTransport: some View {
    HStack(spacing: controlsLayout.centerSpacing) {
      VideoControlsCurrentTimeLabel(playbackState: playbackState) { text in
        timeLabel(text, alignment: .trailing)
      }

      transportButton(systemName: "backward.fill") {
        state.stepTimeline(by: -stepIntervalSeconds)
      }

      playPauseButton

      transportButton(systemName: "forward.fill") {
        state.stepTimeline(by: stepIntervalSeconds)
      }

      timeLabel(state.formattedDuration, alignment: .leading)
    }
    // Transport siblings merge optically on macOS 26+ and sample once.
    .liquidGlassGroup(spacing: controlsLayout.centerSpacing)
  }

  private func rightActions(showsStatus: Bool) -> some View {
    HStack(spacing: controlsLayout.metadataSpacing) {
      if showsStatus, hasStatusBadges {
        // Natural width when shown, but no contribution to the row's minimum: otherwise
        // the editor's minimum would keep room for the badges, the AI slot would give up
        // that room, and the badges would "fit" forever with the panel over the editor.
        statusBadges
          .fixedSize(horizontal: true, vertical: false)
          .measureVideoControlsPart(.status)
          .frame(minWidth: 0, alignment: .trailing)
      }

      // Timeline zoom cluster lives with the other transport controls so it
      // never occludes the ruler or tracks underneath it.
      TimelineZoomControls(viewport: state.timelineViewport) { [playbackState] in
        CMTimeGetSeconds(playbackState.currentTime)
      }
      .fixedSize(horizontal: true, vertical: false)
      .measureVideoControlsPart(.zoom)
    }
    // Hidden badges are still measured (one invisible copy, only while narrow) so a badge
    // added or removed while hidden updates the decision.
    .background(alignment: .trailing) {
      if !showsStatus, hasStatusBadges {
        statusBadges
          .fixedSize(horizontal: true, vertical: false)
          .hidden()
          .measureVideoControlsPart(.status)
          .allowsHitTesting(false)
      }
    }
  }

  /// Mirrors `statusMetadata`'s conditions, so an empty badge group adds no spacing.
  private var hasStatusBadges: Bool {
    !state.zoomSegments.isEmpty || state.hasUnsavedChanges || state.hasSpeedSegments
  }

  private var statusBadges: some View {
    HStack(spacing: controlsLayout.metadataSpacing) {
      statusMetadata
    }
  }

  /// The transport is the one always-lit surface in the editor, so it keeps its glass at rest
  /// rather than materialising on hover — it is the primary control of the window.
  private var playPauseButton: some View {
    Button(action: { state.togglePlayback() }) {
      VideoControlsPlayPauseGlyph(playbackState: playbackState)
        .font(.system(size: controlsLayout.playIconSize, weight: .bold))
        // Accent-tinted glass, so the glyph is resolved against the tint rather than the app
        // appearance — adaptive ink drew a black triangle on the blue transport in Light theme.
        .foregroundColor(LiquidGlassTokens.inkOnAccent)
        .frame(width: controlsLayout.playButtonSize, height: controlsLayout.playButtonSize)
        .liquidGlassChrome(
          shape: Circle(),
          isVisible: true,
          isActive: true,
          glassTint: .accentColor
        )
    }
    .buttonStyle(.plain)
  }

  private func transportButton(systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: controlsLayout.transportIconSize, weight: .semibold))
        .foregroundColor(LiquidGlassTokens.inkBody)
        .frame(
          width: controlsLayout.transportButtonSize,
          height: controlsLayout.transportButtonSize
        )
        .liquidGlassControl(isActive: false, in: Circle())
    }
    .buttonStyle(.plain)
  }

  private func timeLabel(_ value: String, alignment: Alignment) -> some View {
    Text(value)
      .font(.system(size: controlsLayout.timeFontSize, weight: .semibold, design: .monospaced))
      .foregroundColor(.secondary)
      .frame(width: controlsLayout.timeLabelWidth, alignment: alignment)
  }

  @ViewBuilder
  private var statusMetadata: some View {
    if !state.zoomSegments.isEmpty {
      // The auto badge follows the playhead inside this leaf; the bar itself only
      // re-renders when the segments change.
      VideoControlsZoomBadges(
        playbackState: playbackState,
        zoomSegments: state.zoomSegments,
        spacing: controlsLayout.metadataSpacing,
        countBadge: {
          statusBadge(systemName: "plus.magnifyingglass", text: "\(state.zoomSegments.count)")
        },
        autoBadge: {
          statusBadge(systemName: "camera.metering.center.weighted", text: L10n.VideoEditor.auto)
        }
      )
    }

    if state.hasUnsavedChanges {
      statusBadge(systemName: "scissors", text: state.formattedTrimmedDuration)
    }

    // Output length reflects per-segment speed scaling (timelapse).
    if state.hasSpeedSegments {
      statusBadge(systemName: "gauge.with.dots.needle.67percent", text: state.formattedOutputDuration)
    }
  }

  /// Uniform neutral stat chip for the controls bar — secondary glyph + primary value on one
  /// quiet glass capsule, matching the GIF info metadata badges. All metadata shares one
  /// treatment so the row reads as instrument readouts, not a set of colored alerts.
  private func statusBadge(systemName: String, text: String) -> some View {
    HStack(spacing: 5) {
      Image(systemName: systemName)
        .font(.system(size: controlsLayout.badgeIconSize, weight: .medium))
        .foregroundColor(.secondary)

      Text(text)
        .font(.system(size: controlsLayout.badgeFontSize, weight: .medium))
        .foregroundColor(.primary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .monospacedDigit()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .liquidGlassChrome(
      shape: Capsule(style: .continuous),
      isVisible: true,
      isActive: false
    )
  }
}

// MARK: - Playhead-driven leaves

/// Current-time readout. The label shows whole seconds, so it re-renders once per second
/// rather than on every 30 Hz playback tick.
private struct VideoControlsCurrentTimeLabel<Label: View>: View {
  let playbackState: VideoEditorPlaybackState
  @ViewBuilder let label: (String) -> Label
  @State private var text: String

  init(playbackState: VideoEditorPlaybackState, @ViewBuilder label: @escaping (String) -> Label) {
    self.playbackState = playbackState
    self.label = label
    _text = State(initialValue: playbackState.formattedCurrentTime)
  }

  var body: some View {
    label(text)
      .onReceive(
        playbackState.$currentTime
          .map(VideoEditorPlaybackState.formatTime)
          .removeDuplicates()
      ) { text = $0 }
  }
}

/// Play/pause glyph; re-renders only when the transport starts or stops.
private struct VideoControlsPlayPauseGlyph: View {
  @State private var isPlaying: Bool
  private let playbackState: VideoEditorPlaybackState

  init(playbackState: VideoEditorPlaybackState) {
    self.playbackState = playbackState
    _isPlaying = State(initialValue: playbackState.isPlaying)
  }

  var body: some View {
    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
      .onReceive(playbackState.$isPlaying.removeDuplicates()) { isPlaying = $0 }
  }
}

/// Zoom count badge plus the auto (Follow Mouse) badge, shown while the playhead sits in
/// an auto zoom block. Only the in/out flip re-renders, not every tick.
/// The subscriptions hang off the always-present count badge's row, never an empty view.
private struct VideoControlsZoomBadges<Count: View, Auto: View>: View {
  let playbackState: VideoEditorPlaybackState
  let zoomSegments: [ZoomSegment]
  let spacing: CGFloat
  @ViewBuilder let countBadge: () -> Count
  @ViewBuilder let autoBadge: () -> Auto
  @State private var isActive = false

  var body: some View {
    HStack(spacing: spacing) {
      countBadge()
      if isActive { autoBadge() }
    }
    .onAppear { refresh(at: playbackState.currentTime) }
    .onChange(of: zoomSegments) { _ in refresh(at: playbackState.currentTime) }
    .onReceive(playbackState.$currentTime) { refresh(at: $0) }
  }

  private func refresh(at time: CMTime) {
    let active = ZoomCalculator.activeSegment(at: CMTimeGetSeconds(time), in: zoomSegments)?.isAutoMode == true
    if isActive != active { isActive = active }
  }
}
