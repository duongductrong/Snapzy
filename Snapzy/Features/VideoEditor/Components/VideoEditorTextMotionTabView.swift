//
//  VideoEditorTextMotionTabView.swift
//  Snapzy
//
//  Tab 3 (`Motion`) of the Text Studio inspector panel: `In | Out | By Word`
//  motion tiles with live sample-text previews, duration slider, and specular sheen.
//

import AppKit
import SwiftUI

struct VideoEditorTextMotionTabView: View {
  @ObservedObject var state: VideoEditorState
  let overlay: VideoEditorTextOverlay?
  let onCommitTextFocus: () -> Void

  @State private var motionSubTab: VideoEditorTextMotionSubTab = .enter
  @State private var hoveredMotionTile: String?
  @State private var activeBurstTileKey: String?
  @State private var burstResetTask: Task<Void, Never>?
  @State private var sliderBefore: [VideoEditorTextOverlay]?
  @Namespace private var motionTabNamespace

  private let motionTileColumns = [
    GridItem(.flexible(), spacing: 6),
    GridItem(.flexible(), spacing: 6),
    GridItem(.flexible(), spacing: 6),
  ]

  private static let wordMotionStyles: [VideoEditorCaptionSettings.AnimationStyle] = [
    .none,
    .springRise,
    .studioPop,
    .elasticBounce,
    .wordCascade,
    .opticalBlur,
    .maskSlideUp,
    .shutterFlip,
    .whipBlur,
    .neonFlicker,
    .cinematicFade,
    .driftSlide,
  ]

  var body: some View {
    if let overlay {
      motionStudioSection(for: overlay)
        .onDisappear {
          burstResetTask?.cancel()
          commitSliderIfNeeded()
        }
    } else {
      VideoEditorTextInspectorUI.noSelectionPromptCard(state: state)
    }
  }

  private func motionStudioSection(for overlay: VideoEditorTextOverlay) -> some View {
    let s = overlay.style

    return VStack(alignment: .leading, spacing: 10) {
      VideoEditorTextInspectorUI.card {
        HStack(spacing: 6) {
          HStack(spacing: 2) {
            ForEach(VideoEditorTextMotionSubTab.allCases) { sub in
              let isSelected = motionSubTab == sub
              Button {
                withAnimation(LiquidGlassTokens.settleSpring) {
                  motionSubTab = sub
                }
              } label: {
                HStack(spacing: 3.5) {
                  Text(motionSubTabTitle(sub))
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)

                  if motionSubTabHasActiveBadge(sub, style: s) {
                    Circle()
                      .fill(Color.accentColor)
                      .frame(width: 4.5, height: 4.5)
                  }
                }
                .foregroundColor(isSelected ? SidebarColors.labelPrimary : SidebarColors.labelSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background {
                  if isSelected {
                    Radius.controlRect(forHeight: 22)
                      .fill(Color.primary.opacity(0.11))
                      .overlay(
                        Radius.controlRect(forHeight: 22)
                          .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                      )
                      .matchedGeometryEffect(id: "motionSubTabThumb", in: motionTabNamespace)
                  }
                }
                .contentShape(Radius.controlRect(forHeight: 22))
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("video-editor.text-motion-subtab.\(sub.rawValue)")
            }
          }
          .padding(2)
          .background(
            Radius.controlRect(forHeight: 26)
              .fill(Color.primary.opacity(0.05))
              .overlay(
                Radius.controlRect(forHeight: 26)
                  .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
              )
          )

          Button {
            onCommitTextFocus()
            state.previewTextOverlayMotion(id: overlay.id)
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "play.fill")
                .font(.system(size: 8.5, weight: .bold))
              Text(L10n.Common.preview)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
              Radius.controlRect(forHeight: 26)
                .fill(Color.accentColor.opacity(0.12))
                .overlay(
                  Radius.controlRect(forHeight: 26)
                    .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 0.65)
                )
            )
            .contentShape(Radius.controlRect(forHeight: 26))
          }
          .buttonStyle(.plain)
          .help(L10n.VideoEditor.captionsPreviewMotion)
          .accessibilityLabel(L10n.VideoEditor.captionsPreviewMotion)
          .accessibilityIdentifier("video-editor.preview-text-motion")
        }

        switch motionSubTab {
        case .enter:
          motionTilesGrid(
            styles: VideoEditorCaptionSettings.AnimationStyle.allCases,
            selected: s.animationIn,
            mode: .enter,
            overlayStyle: s,
            namespacePrefix: "in"
          ) { chosen in
            mutateStyle(id: overlay.id) { $0.animationIn = chosen }
            triggerTilePreviewBurst(tileKey: "in.\(chosen.rawValue)", animation: chosen)
          }

        case .exit:
          motionTilesGrid(
            styles: VideoEditorCaptionSettings.AnimationStyle.allCases,
            selected: s.animationOut,
            mode: .exit,
            overlayStyle: s,
            namespacePrefix: "out"
          ) { chosen in
            mutateStyle(id: overlay.id) { $0.animationOut = chosen }
            triggerTilePreviewBurst(tileKey: "out.\(chosen.rawValue)", animation: chosen)
          }

        case .word:
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              VideoEditorTextInspectorUI.rowLabel(L10n.VideoEditor.captionsWordMode)
              Spacer()
              VideoEditorTextInspectorUI.labeledColorWell(
                title: L10n.VideoEditor.textColorAccentShort,
                selection: rgbaBinding(for: overlay.id, \.accentColor)
              )
            }

            HStack(spacing: 3) {
              wordModePill(.fullLine, title: L10n.VideoEditor.captionsWordFullLine, overlay: overlay)
              wordModePill(.activeHighlight, title: L10n.VideoEditor.captionsWordActiveHighlight, overlay: overlay)
              wordModePill(
                .progressiveReveal,
                title: L10n.VideoEditor.captionsWordProgressiveReveal,
                overlay: overlay
              )
            }
            .padding(2)
            .background(Color.primary.opacity(0.05), in: Radius.controlRect(forHeight: 26))

            VideoEditorTextInspectorUI.rowLabel(L10n.VideoEditor.textWordAnimationLabel)

            motionTilesGrid(
              styles: Self.wordMotionStyles,
              selected: s.wordMode == .fullLine ? .none : s.wordAnimation,
              mode: .word,
              overlayStyle: s,
              namespacePrefix: "word"
            ) { chosen in
              mutateStyle(id: overlay.id) { style in
                style.wordAnimation = chosen
                if chosen != .none, style.wordMode == .fullLine {
                  style.wordMode = .activeHighlight
                }
              }
              triggerTilePreviewBurst(tileKey: "word.\(chosen.rawValue)", animation: chosen)
            }
          }
        }
      }

      VideoEditorTextInspectorUI.card {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            VideoEditorTextInspectorUI.rowLabel(L10n.VideoEditor.captionsMotionSpeed)
            Spacer()
            Text(String(format: "%.2fs", s.animationDuration))
              .font(.system(size: 10, weight: .semibold).monospacedDigit())
              .foregroundColor(SidebarColors.labelSecondary)
          }
          Slider(
            value: continuousStyleBinding(for: overlay.id, \.animationDuration),
            in: VideoEditorCaptionSettings.animationDurationRange,
            step: 0.02
          ) { editing in
            handleSliderEditing(editing)
          }
          .controlSize(.small)
        }

        Divider().opacity(0.5)

        Toggle(L10n.VideoEditor.captionsShimmerSweep, isOn: styleBinding(for: overlay.id, \.shimmerSweep))
          .font(.system(size: 10.5, weight: .medium))
          .lineLimit(1)
          .toggleStyle(.switch)
          .controlSize(.small)

        if state.textOverlays.count > 1 {
          Divider().opacity(0.5)

          Button {
            onCommitTextFocus()
            _ = state.applySelectedTextMotionToAll()
          } label: {
            HStack(spacing: 5) {
              Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 10, weight: .semibold))
              Text(L10n.VideoEditor.textApplyMotionToAll)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            }
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(Color.accentColor.opacity(0.10), in: Radius.rect(Radius.ornament))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("video-editor.apply-motion-to-all-text")
        }
      }
    }
  }

  private func triggerTilePreviewBurst(
    tileKey: String,
    animation: VideoEditorCaptionSettings.AnimationStyle
  ) {
    burstResetTask?.cancel()
    if animation != .none {
      activeBurstTileKey = tileKey
      burstResetTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 2_300_000_000)
        if !Task.isCancelled, activeBurstTileKey == tileKey {
          activeBurstTileKey = nil
        }
      }
    } else {
      activeBurstTileKey = nil
    }
  }

  private func motionSubTabTitle(_ sub: VideoEditorTextMotionSubTab) -> String {
    switch sub {
    case .enter:
      L10n.VideoEditor.captionsAnimationIn
    case .exit:
      L10n.VideoEditor.captionsAnimationOut
    case .word:
      L10n.VideoEditor.textMotionTabWord
    }
  }

  private func motionSubTabHasActiveBadge(
    _ sub: VideoEditorTextMotionSubTab,
    style: VideoEditorCaptionSettings
  ) -> Bool {
    switch sub {
    case .enter:
      style.animationIn != .none
    case .exit:
      style.animationOut != .none
    case .word:
      style.wordMode != .fullLine
    }
  }

  private func motionTilesGrid(
    styles: [VideoEditorCaptionSettings.AnimationStyle],
    selected: VideoEditorCaptionSettings.AnimationStyle,
    mode: VideoEditorTextMotionSubTab,
    overlayStyle: VideoEditorCaptionSettings,
    namespacePrefix: String,
    onSelect: @escaping (VideoEditorCaptionSettings.AnimationStyle) -> Void
  ) -> some View {
    LazyVGrid(columns: motionTileColumns, spacing: 6) {
      ForEach(styles, id: \.self) { anim in
        let isSelected = selected == anim
        let tileKey = "\(namespacePrefix).\(anim.rawValue)"
        let isHovered = hoveredMotionTile == tileKey
        let isAnimating = anim != .none && (isHovered || activeBurstTileKey == tileKey)

        Button {
          onCommitTextFocus()
          onSelect(anim)
        } label: {
          VStack(spacing: 4) {
            MotionTileSampleStage(
              animation: anim,
              mode: mode,
              style: overlayStyle,
              isSelected: isSelected,
              isAnimating: isAnimating
            )
            .frame(height: 36)

            Text(VideoEditorTextInspectorUI.animationDisplayName(anim))
              .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium))
              .foregroundColor(isSelected ? SidebarColors.labelPrimary : SidebarColors.labelSecondary)
              .lineLimit(1)
              .minimumScaleFactor(0.80)
          }
          .padding(4)
          .frame(maxWidth: .infinity)
          .background(
            Radius.rect(Radius.tile)
              .fill(
                isSelected
                  ? Color.accentColor.opacity(0.13)
                  : (isHovered ? Color.primary.opacity(0.055) : Color.primary.opacity(0.025))
              )
              .overlay(
                Radius.rect(Radius.tile)
                  .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.88) : Color.primary.opacity(isHovered ? 0.16 : 0.08),
                    lineWidth: isSelected ? 1.25 : 0.6
                  )
              )
          )
          .contentShape(Radius.rect(Radius.tile))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
          hoveredMotionTile = hovering ? tileKey : (hoveredMotionTile == tileKey ? nil : hoveredMotionTile)
        }
        .accessibilityLabel(VideoEditorTextInspectorUI.animationDisplayName(anim))
        .accessibilityIdentifier("video-editor.motion-tile.\(tileKey)")
      }
    }
  }

  private func wordModePill(
    _ value: VideoEditorCaptionSettings.WordMode,
    title: String,
    overlay: VideoEditorTextOverlay
  ) -> some View {
    let selected = overlay.style.wordMode == value
    return Button {
      mutateStyle(id: overlay.id) { $0.wordMode = value }
    } label: {
      Text(title)
        .font(.system(size: 10, weight: selected ? .semibold : .medium))
        .foregroundColor(selected ? .white : SidebarColors.labelSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .background(Radius.controlRect(forHeight: 22).fill(selected ? Color.accentColor : .clear))
        .contentShape(Radius.controlRect(forHeight: 22))
    }
    .buttonStyle(.plain)
  }

  private func mutateStyle(id: UUID, recordUndo: Bool = true, _ body: (inout VideoEditorCaptionSettings) -> Void) {
    state.updateTextOverlay(id: id, recordUndo: recordUndo) { item in
      body(&item.style)
      item.syncLegacyMirrorFromStyle()
    }
  }

  private func styleBinding<Value>(
    for id: UUID,
    _ keyPath: WritableKeyPath<VideoEditorCaptionSettings, Value>
  ) -> Binding<Value> {
    Binding(
      get: {
        state.textOverlays.first(where: { $0.id == id })?.style[keyPath: keyPath]
          ?? VideoEditorCaptionSettings.default[keyPath: keyPath]
      },
      set: { newValue in
        mutateStyle(id: id) { $0[keyPath: keyPath] = newValue }
      }
    )
  }

  private func continuousStyleBinding<Value>(
    for id: UUID,
    _ keyPath: WritableKeyPath<VideoEditorCaptionSettings, Value>
  ) -> Binding<Value> {
    Binding(
      get: {
        state.textOverlays.first(where: { $0.id == id })?.style[keyPath: keyPath]
          ?? VideoEditorCaptionSettings.default[keyPath: keyPath]
      },
      set: { newValue in
        if sliderBefore == nil {
          sliderBefore = state.textOverlays
        }
        mutateStyle(id: id, recordUndo: false) { $0[keyPath: keyPath] = newValue }
      }
    )
  }

  private func rgbaBinding(
    for id: UUID,
    _ keyPath: WritableKeyPath<VideoEditorCaptionSettings, VideoEditorRGBAColor>
  ) -> Binding<Color> {
    Binding(
      get: {
        let c = state.textOverlays.first(where: { $0.id == id })?.style[keyPath: keyPath]
          ?? VideoEditorCaptionSettings.default[keyPath: keyPath]
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
      },
      set: { color in
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return }
        mutateStyle(id: id) {
          $0[keyPath: keyPath] = VideoEditorRGBAColor(
            red: ns.redComponent,
            green: ns.greenComponent,
            blue: ns.blueComponent,
            alpha: 1
          )
        }
      }
    )
  }

  private func handleSliderEditing(_ editing: Bool) {
    if editing {
      if sliderBefore == nil {
        sliderBefore = state.textOverlays
      }
    } else {
      commitSliderIfNeeded()
    }
  }

  private func commitSliderIfNeeded() {
    if let before = sliderBefore {
      sliderBefore = nil
      state.commitTextOverlayEdit(previous: before)
    }
  }
}

// MARK: - Live Sample-Text Motion Tile Preview Stage

private struct MotionTileSampleStage: View {
  let animation: VideoEditorCaptionSettings.AnimationStyle
  let mode: VideoEditorTextMotionSubTab
  let style: VideoEditorCaptionSettings
  let isSelected: Bool
  let isAnimating: Bool

  private var heroInkColor: Color {
    let c = style.useGradientText ? style.textGradientEndColor : style.textColor
    let lum = 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
    if lum < 0.14 {
      return Color(red: 0.42, green: 0.86, blue: 1.0)
    }
    return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
  }

  private var leadInkColor: Color {
    let c = style.textColor
    let lum = 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
    if lum < 0.14 {
      return Color.white.opacity(0.84)
    }
    return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 0.84)
  }

  private var accentInkColor: Color {
    let c = style.accentColor
    let lum = 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
    if lum < 0.14 {
      return Color(red: 0.29, green: 0.76, blue: 1.0)
    }
    return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
  }

  var body: some View {
    ZStack {
      Radius.rect(Radius.ornament)
        .fill(VideoEditorTextInspectorUI.stageMatteColor)
        .overlay(
          Radius.rect(Radius.ornament)
            .strokeBorder(
              isSelected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06),
              lineWidth: 0.5
            )
        )

      if animation == .none {
        staticSampleContent(dimmed: true)
      } else {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimating)) { context in
          animatedSampleContent(at: context.date)
        }
      }
    }
    .clipped()
  }

  @ViewBuilder
  private func staticSampleContent(dimmed: Bool) -> some View {
    if style.dualLineHero {
      VStack(spacing: -1) {
        Text(cased("lead", forceStandard: true))
          .font(.system(size: 7.5, weight: .medium))
          .foregroundColor(leadInkColor.opacity(dimmed ? 0.58 : 0.82))
          .lineLimit(1)
        Text(cased("HERO"))
          .font(.system(size: 11, weight: .heavy))
          .italic(style.resolvedItalic)
          .foregroundColor(dimmed ? Color.white.opacity(0.62) : heroInkColor)
          .lineLimit(1)
      }
    } else if mode == .word {
      HStack(spacing: 3) {
        Text(cased("Key"))
          .foregroundColor(.white.opacity(dimmed ? 0.55 : 0.78))
        Text(cased("Focus"))
          .foregroundColor(dimmed ? .white.opacity(0.62) : accentInkColor)
      }
      .font(.system(size: 9.5, weight: .bold))
      .italic(style.resolvedItalic)
      .lineLimit(1)
    } else {
      Text(cased("Sample"))
        .font(.system(size: 10.5, weight: .bold))
        .italic(style.resolvedItalic)
        .foregroundColor(dimmed ? Color.white.opacity(0.62) : heroInkColor)
        .lineLimit(1)
    }
  }

  @ViewBuilder
  private func animatedSampleContent(at date: Date) -> some View {
    if !isAnimating {
      staticSampleContent(dimmed: false)
    } else {
      let cyclePeriod = 1.16
      let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cyclePeriod)
      let motion = evaluatedMotionState(forCyclePhase: phase)

      let stageH: CGFloat = 36
      let dx = max(-26, min(26, motion.offsetXFraction * stageH * 1.65))
      let dy = max(-16, min(16, motion.offsetYFraction * stageH * 1.65))
      let blurPt = min(4.5, motion.blurRadiusFraction * stageH * 1.8)
      let trackingPt = motion.trackingDeltaEm * 10.5

      sampleTokensView(motion: motion)
        .tracking(trackingPt)
        .mask(alignment: .leading) {
          GeometryReader { geo in
            Rectangle()
              .frame(
                width: max(0, geo.size.width * motion.wipeProgress),
                height: max(0, geo.size.height * motion.verticalRevealProgress)
              )
              .frame(maxHeight: .infinity, alignment: .bottom)
          }
        }
        .scaleEffect(x: motion.scale * motion.scaleX, y: motion.scale * motion.scaleY)
        .offset(x: dx, y: dy)
        .blur(radius: blurPt)
        .opacity(Double(motion.opacity))
        .padding(.horizontal, 4)
    }
  }

  @ViewBuilder
  private func sampleTokensView(motion: VideoEditorCaptionMotionState) -> some View {
    if mode == .word {
      let activeIdx = motion.activeWordIndex ?? 0
      let wScale = motion.activeWordScale
      let wOffsetY = -motion.activeWordOffsetYEm * 9.0
      let wOpacity = Double(motion.activeWordOpacity)

      if style.dualLineHero {
        VStack(spacing: -1) {
          Text(cased("lead", forceStandard: true))
            .font(.system(size: 7.5, weight: .semibold))
            .foregroundColor(activeIdx == 0 ? accentInkColor : leadInkColor.opacity(0.55))
            .scaleEffect(activeIdx == 0 ? wScale : 1.0)
            .offset(y: activeIdx == 0 ? wOffsetY : 0)
            .opacity(activeIdx == 0 ? wOpacity : 0.65)
            .lineLimit(1)

          Text(cased("HERO"))
            .font(.system(size: 11, weight: .heavy))
            .italic(style.resolvedItalic)
            .foregroundColor(activeIdx == 1 ? accentInkColor : heroInkColor.opacity(0.65))
            .scaleEffect(activeIdx == 1 ? wScale : 1.0)
            .offset(y: activeIdx == 1 ? wOffsetY : 0)
            .opacity(activeIdx == 1 ? wOpacity : 0.65)
            .lineLimit(1)
        }
      } else {
        HStack(spacing: 3) {
          Text(cased("Key"))
            .foregroundColor(activeIdx == 0 ? accentInkColor : .white.opacity(0.62))
            .scaleEffect(activeIdx == 0 ? wScale : 1.0)
            .offset(y: activeIdx == 0 ? wOffsetY : 0)
            .opacity(activeIdx == 0 ? wOpacity : 0.65)

          Text(cased("Focus"))
            .foregroundColor(activeIdx == 1 ? accentInkColor : .white.opacity(0.62))
            .scaleEffect(activeIdx == 1 ? wScale : 1.0)
            .offset(y: activeIdx == 1 ? wOffsetY : 0)
            .opacity(activeIdx == 1 ? wOpacity : 0.65)
        }
        .font(.system(size: 9.5, weight: .bold))
        .italic(style.resolvedItalic)
        .lineLimit(1)
      }
    } else if let subKind = motion.subwordKind, let subProg = motion.subwordProgress {
      subwordAnimatedView(kind: subKind, progress: subProg)
    } else if style.dualLineHero {
      VStack(spacing: -1) {
        Text(cased("lead", forceStandard: true))
          .font(.system(size: 7.5, weight: .medium))
          .foregroundColor(leadInkColor)
          .lineLimit(1)
        Text(cased("HERO"))
          .font(.system(size: 11, weight: .heavy))
          .italic(style.resolvedItalic)
          .foregroundColor(heroInkColor)
          .lineLimit(1)
      }
    } else {
      Text(cased("Sample"))
        .font(.system(size: 10.5, weight: .bold))
        .italic(style.resolvedItalic)
        .foregroundColor(heroInkColor)
        .lineLimit(1)
    }
  }

  @ViewBuilder
  private func subwordAnimatedView(
    kind: VideoEditorCaptionMotionState.SubwordAnimationKind,
    progress: CGFloat
  ) -> some View {
    let p1 = min(max(progress / 0.58, 0), 1)
    let p2 = min(max((progress - 0.30) / 0.62, 0), 1)

    switch kind {
    case .typewriter:
      if style.dualLineHero {
        let full1 = cased("lead", forceStandard: true)
        let full2 = cased("HERO")
        let total = full1.count + full2.count
        let shown = max(1, Int((CGFloat(total) * progress).rounded(.up)))
        let count1 = min(full1.count, shown)
        let count2 = max(0, shown - full1.count)
        VStack(spacing: -1) {
          Text(String(full1.prefix(count1)) + (count2 == 0 && progress < 0.98 ? "|" : ""))
            .font(.system(size: 7.5, weight: .medium))
            .foregroundColor(leadInkColor)
            .lineLimit(1)
          Text(count2 > 0 ? (String(full2.prefix(count2)) + (progress < 0.98 ? "|" : "")) : " ")
            .font(.system(size: 11, weight: .heavy))
            .italic(style.resolvedItalic)
            .foregroundColor(heroInkColor)
            .lineLimit(1)
        }
      } else {
        let full = cased("Sample")
        let shown = max(1, Int((CGFloat(full.count) * progress).rounded(.up)))
        Text(String(full.prefix(shown)) + (progress < 0.98 ? "|" : ""))
          .font(.system(size: 10.5, weight: .bold))
          .italic(style.resolvedItalic)
          .foregroundColor(heroInkColor)
          .lineLimit(1)
      }

    case .wordCascade, .wordFocus:
      let isBlur = (kind == .wordFocus)
      if style.dualLineHero {
        VStack(spacing: -1) {
          Text(cased("lead", forceStandard: true))
            .font(.system(size: 7.5, weight: .medium))
            .foregroundColor(leadInkColor)
            .offset(y: isBlur ? 0 : (1.0 - p1) * 6)
            .blur(radius: isBlur ? (1.0 - p1) * 3.2 : 0)
            .opacity(Double(p1))
            .lineLimit(1)

          Text(cased("HERO"))
            .font(.system(size: 11, weight: .heavy))
            .italic(style.resolvedItalic)
            .foregroundColor(heroInkColor)
            .offset(y: isBlur ? 0 : (1.0 - p2) * 7)
            .blur(radius: isBlur ? (1.0 - p2) * 3.6 : 0)
            .opacity(Double(p2))
            .lineLimit(1)
        }
      } else {
        HStack(spacing: 3) {
          Text(cased("Key"))
            .offset(y: isBlur ? 0 : (1.0 - p1) * 6)
            .blur(radius: isBlur ? (1.0 - p1) * 3.2 : 0)
            .opacity(Double(p1))

          Text(cased("Focus"))
            .offset(y: isBlur ? 0 : (1.0 - p2) * 6)
            .blur(radius: isBlur ? (1.0 - p2) * 3.2 : 0)
            .opacity(Double(p2))
        }
        .font(.system(size: 9.5, weight: .bold))
        .italic(style.resolvedItalic)
        .foregroundColor(heroInkColor)
        .lineLimit(1)
      }
    }
  }

  private func evaluatedMotionState(forCyclePhase phase: Double) -> VideoEditorCaptionMotionState {
    var probe = style
    probe.shimmerSweep = false
    let sampleText = style.dualLineHero ? "lead HERO" : "Key Focus"
    let seg = CaptionSegment(sourceRange: 0.0 ... 1.0, text: sampleText)

    switch mode {
    case .enter:
      probe.animationIn = animation
      probe.animationOut = .none
      probe.wordMode = .fullLine
      probe.animationDuration = 0.44
      if phase > 1.04 {
        var gap = VideoEditorCaptionMotionState.identity
        gap.opacity = 0
        return gap
      }
      return VideoEditorCaptionMotion.evaluate(
        atSource: min(0.98, phase),
        in: seg,
        settings: probe
      )

    case .exit:
      probe.animationIn = .none
      probe.animationOut = animation
      probe.wordMode = .fullLine
      probe.animationDuration = 0.44
      if phase < 0.24 {
        return .identity
      } else if phase <= 0.72 {
        let exitFrac = (phase - 0.24) / 0.48
        let mappedT = 0.56 + exitFrac * 0.439
        return VideoEditorCaptionMotion.evaluate(
          atSource: min(0.999, mappedT),
          in: seg,
          settings: probe
        )
      } else {
        var hidden = VideoEditorCaptionMotionState.identity
        hidden.opacity = 0
        return hidden
      }

    case .word:
      probe.animationIn = .none
      probe.animationOut = .none
      probe.wordMode = .activeHighlight
      probe.wordAnimation = animation
      let mappedWordT = min(0.99, phase / 1.16)
      return VideoEditorCaptionMotion.evaluate(
        atSource: mappedWordT,
        in: seg,
        settings: probe
      )
    }
  }

  private func cased(_ raw: String, forceStandard: Bool = false) -> String {
    guard !forceStandard else { return raw }
    return switch style.textCase {
    case .standard: raw
    case .uppercase: raw.uppercased()
    case .lowercase: raw.lowercased()
    }
  }
}
