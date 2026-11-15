//
//  AnnotateAIDockView.swift
//  Snapzy
//
//  Floating AI dock at the bottom center of the Annotate canvas. At rest it is a
//  single glass orb with the multi-hue AI glyph (the same hues as the translation
//  reading rim). Clicking it grows the glass horizontally into a small toolbar:
//
//    [ orb ] | [ Translate ] [ Area ] [ 🌐 Language ⌄ ] [ ⋯ ]
//
//  Each feature is its own section after the orb, separated by a hairline, so
//  future AI tools (e.g. the prompt pen) slot in as another section without
//  changing the dock itself.
//

import AppKit
import SwiftUI

struct AnnotateAIDockView: View {
  @ObservedObject var state: AnnotateState
  @ObservedObject private var shortcuts = AnnotateShortcutManager.shared
  @State private var isExpanded = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  fileprivate static let height: CGFloat = 40
  fileprivate static let inset: CGFloat = 4
  fileprivate static let itemHeight: CGFloat = height - inset * 2

  private var expandAnimation: Animation {
    reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.86)
  }

  /// Annotate mode only, same rule as the Auto Translate actions; stays up while a run finishes.
  private var isAvailable: Bool {
    state.canAutoTranslate || state.isAutoTranslateRunning
  }

  var body: some View {
    Group {
      if isAvailable {
        dock
          .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
      }
    }
    .animation(.easeOut(duration: 0.18), value: isAvailable)
  }

  private var dock: some View {
    HStack(spacing: 0) {
      AnnotateAIDockOrb(
        isExpanded: isExpanded,
        isWorking: state.isAutoTranslateRunning
      ) {
        withAnimation(expandAnimation) { isExpanded.toggle() }
      }

      if isExpanded {
        Group {
          AnnotateAIDockHairline()
          AnnotateAIDockTranslateSection(state: state, shortcuts: shortcuts)
          // Future AI sections (prompt pen, …) go here, each after its own hairline.
        }
        .transition(sectionTransition)
      }
    }
    .padding(Self.inset)
    .frame(height: Self.height)
    .clipShape(Capsule(style: .continuous))
    .liquidGlassSurface(
      shape: Capsule(style: .continuous),
      substrate: LiquidGlassTokens.baseDarkness,
      tint: 0.04,
      highlight: .none,
      withRimLighting: true
    )
    .overlay {
      if state.isAutoTranslateRunning {
        TranslationReadingRim(shape: Capsule(style: .continuous))
          .transition(.opacity)
      }
    }
    .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    .fixedSize()
    .animation(.easeInOut(duration: 0.25), value: state.isAutoTranslateRunning)
    .onChange(of: isAvailable) { available in
      if !available { isExpanded = false }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L10n.AnnotateTranslate.aiTools)
  }

  /// Items fade and settle in from the orb while the glass grows; they leave faster than they come.
  private var sectionTransition: AnyTransition {
    if reduceMotion { return .opacity }
    return .asymmetric(
      insertion: .opacity.combined(with: .scale(scale: 0.86, anchor: .leading))
        .animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.05)),
      removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading))
        .animation(.easeOut(duration: 0.14))
    )
  }
}

// MARK: - Orb

/// The AI glyph in a circle. Static multi-hue at rest; the hues turn slowly and glow while working.
private struct AnnotateAIDockOrb: View {
  let isExpanded: Bool
  let isWorking: Bool
  let action: () -> Void

  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  private static let symbolName: String = {
    NSImage(systemSymbolName: "apple.intelligence", accessibilityDescription: nil) != nil
      ? "apple.intelligence"
      : "sparkles"
  }()

  var body: some View {
    Button(action: action) {
      TimelineView(.animation(minimumInterval: nil, paused: !isWorking || reduceMotion)) { context in
        let angle = gradientAngle(at: context.date)
        let gradient = AngularGradient(
          colors: TranslationCardMotion.rimHues,
          center: .center,
          angle: angle
        )
        ZStack {
          Circle()
            .fill(Color.primary.opacity(isExpanded ? 0.09 : (isHovered ? 0.06 : 0)))

          // Soft bloom of the same hues, strongest while working.
          Circle()
            .fill(gradient)
            .frame(width: 18, height: 18)
            .blur(radius: 9)
            .opacity(glowOpacity)

          Image(systemName: Self.symbolName)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(gradient)
            .scaleEffect(isHovered ? 1.06 : 1)
        }
      }
      .frame(width: AnnotateAIDockView.itemHeight, height: AnnotateAIDockView.itemHeight)
      .contentShape(Circle())
    }
    .buttonStyle(AnnotateAIDockPressStyle())
    .onHover { hovering in
      withAnimation(LiquidGlassTokens.hoverSpring) { isHovered = hovering }
    }
    .help(isExpanded ? L10n.Common.close : L10n.AnnotateTranslate.aiTools)
    .accessibilityLabel(L10n.AnnotateTranslate.aiTools)
    .accessibilityAddTraits(isExpanded ? .isSelected : [])
  }

  private var glowOpacity: Double {
    if isWorking { return colorScheme == .dark ? 0.55 : 0.4 }
    return isHovered ? 0.22 : 0.1
  }

  private func gradientAngle(at date: Date) -> Angle {
    // Resting angle puts blue/violet at the top-left, warm tones bottom-right.
    let rest = Angle.degrees(-135)
    guard isWorking, !reduceMotion else { return rest }
    let duration = TranslationCardMotion.rimTurnDuration * 0.6
    let turn = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
    return rest + .degrees(turn * 360)
  }
}

// MARK: - Translate section

private struct AnnotateAIDockTranslateSection: View {
  @ObservedObject var state: AnnotateState
  @ObservedObject var shortcuts: AnnotateShortcutManager

  private var canRun: Bool { state.canAutoTranslate && !state.isAutoTranslateRunning }

  var body: some View {
    HStack(spacing: 2) {
      AnnotateAIDockItem(
        icon: "translate",
        title: L10n.AnnotateTranslate.dockTranslate,
        isActive: state.isAutoTranslateRunning && state.autoTranslateRegion == nil,
        help: help(L10n.AnnotateTranslate.translateWholeImage, .autoTranslate)
      ) {
        state.autoTranslate()
      }
      .disabled(!canRun)

      AnnotateAIDockItem(
        icon: "text.viewfinder",
        title: L10n.AnnotateTranslate.dockArea,
        isActive: state.isTranslateAreaSelecting
          || (state.isAutoTranslateRunning && state.autoTranslateRegion != nil),
        help: help(
          state.isTranslateAreaSelecting ? L10n.AnnotateTranslate.cancelAreaSelection : L10n.AnnotateTranslate.translateArea,
          .translateArea
        )
      ) {
        state.toggleTranslateAreaSelection()
      }
      .disabled(!canRun)

      AnnotateAIDockMenuButton(help: L10n.Translate.targetLanguageLabel, makeMenu: languageMenu) { isOpen in
        HStack(spacing: 5) {
          Image(systemName: "globe")
            .font(.system(size: 12, weight: .medium))
          Text(state.autoTranslateTarget.displayName)
            .lineLimit(1)
          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .bold))
            .opacity(0.6)
        }
        .padding(.horizontal, 10)
      }
      .disabled(state.isAutoTranslateRunning)

      AnnotateAIDockMenuButton(help: L10n.AnnotateTranslate.options, makeMenu: optionsMenu) { _ in
        Image(systemName: "ellipsis")
          .font(.system(size: 13, weight: .semibold))
          .frame(width: AnnotateAIDockView.itemHeight)
      }
    }
  }

  private func help(_ title: String, _ kind: AnnotateActionShortcutKind) -> String {
    guard shortcuts.isActionShortcutEnabled(for: kind),
          let config = shortcuts.shortcut(for: kind) else { return title }
    return "\(title) (\(config.displayString))"
  }

  private func languageMenu() -> NSMenu {
    let menu = NSMenu()
    let current = state.autoTranslateTarget
    for language in TranslationLanguage.all.sorted(by: { $0.displayName < $1.displayName }) {
      let item = ClosureMenuItem(title: language.displayName, keyEquivalent: "") { [weak state] in
        state?.setAutoTranslateTarget(language)
      }
      item.state = language == current ? .on : .off
      menu.addItem(item)
    }
    return menu
  }

  private func optionsMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false

    if state.isAutoTranslateRunning {
      let cancel = ClosureMenuItem(title: L10n.Common.cancel, keyEquivalent: "") { [weak state] in
        state?.cancelAutoTranslate()
      }
      cancel.image = symbol("stop.circle")
      menu.addItem(cancel)
      menu.addItem(.separator())
    }

    let engine = NSMenuItem(title: engineDescription, action: nil, keyEquivalent: "")
    engine.image = symbol(isRemoteEngine ? "network" : "lock.laptopcomputer")
    engine.isEnabled = false
    menu.addItem(engine)

    let settings = ClosureMenuItem(title: L10n.Translate.openSettings, keyEquivalent: "") {
      AnnotateState.openTranslationSettings()
    }
    settings.image = symbol("gearshape")
    menu.addItem(settings)

    menu.addItem(.separator())

    let export = ClosureMenuItem(title: L10n.AnnotateTranslate.includeInExport, keyEquivalent: "") { [weak state] in
      guard let state else { return }
      state.setIncludesTranslationsInExport(!state.includesTranslationsInExport)
    }
    export.image = symbol("square.and.arrow.up")
    export.state = state.includesTranslationsInExport ? .on : .off
    menu.addItem(export)

    let remove = ClosureMenuItem(title: L10n.AnnotateTranslate.removeTranslations, keyEquivalent: "") { [weak state] in
      state?.removeAllTranslations()
    }
    remove.image = symbol("trash")
    remove.isEnabled = state.translationAnnotationCount > 0 && !state.isAutoTranslateRunning
    menu.addItem(remove)
    return menu
  }

  private func symbol(_ name: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)
  }

  private var isRemoteEngine: Bool {
    if case .remote = TranslationEngineResolver().resolve() { return true }
    return false
  }

  private var engineDescription: String {
    switch TranslationEngineResolver().resolve() {
    case .apple:
      return L10n.AnnotateTranslate.engineApple
    case .remote(let model):
      return L10n.AnnotateTranslate.engineRemote(model.name)
    case .unavailable:
      return L10n.Translate.requiresMacOS15Title
    }
  }
}

// MARK: - Building blocks

/// Icon + label segment with a hover glass capsule; accent-tinted while its action is active.
private struct AnnotateAIDockItem: View {
  let icon: String
  let title: String
  var isActive: Bool = false
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 12, weight: .medium))
        Text(title)
          .lineLimit(1)
      }
      .padding(.horizontal, 11)
    }
    .buttonStyle(AnnotateAIDockItemStyle(isActive: isActive))
    .help(help)
  }
}

/// A dock segment that pops a native menu just above itself (the dock sits at the bottom).
private struct AnnotateAIDockMenuButton<Label: View>: View {
  let help: String
  let makeMenu: () -> NSMenu
  @ViewBuilder let label: (Bool) -> Label

  @State private var anchor = MenuAnchor()
  @State private var isOpen = false

  var body: some View {
    Button {
      present()
    } label: {
      label(isOpen)
    }
    .buttonStyle(AnnotateAIDockItemStyle(isActive: isOpen))
    .background(MenuAnchorView(anchor: anchor))
    .help(help)
  }

  private func present() {
    guard let view = anchor.view else { return }
    let menu = makeMenu()
    isOpen = true
    let top = view.isFlipped ? -6 : view.bounds.height + 6
    // Position the menu's bottom edge just above the segment.
    let origin = NSPoint(x: 0, y: top)
    menu.popUp(positioning: nil, at: origin, in: view)
    isOpen = false
  }
}

private struct AnnotateAIDockItemStyle: ButtonStyle {
  var isActive: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    AnnotateAIDockItemBody(configuration: configuration, isActive: isActive)
  }
}

private struct AnnotateAIDockItemBody: View {
  let configuration: ButtonStyleConfiguration
  let isActive: Bool

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovered = false

  var body: some View {
    configuration.label
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(foreground)
      .frame(minWidth: AnnotateAIDockView.itemHeight)
      .frame(height: AnnotateAIDockView.itemHeight)
      .background {
        Capsule(style: .continuous)
          .fill(fill)
      }
      .contentShape(Capsule(style: .continuous))
      .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
      .onHover { hovering in
        withAnimation(LiquidGlassTokens.hoverSpring) { isHovered = hovering && isEnabled }
      }
      .onChange(of: isEnabled) { enabled in
        if !enabled { isHovered = false }
      }
      .animation(LiquidGlassTokens.pressSpring, value: configuration.isPressed)
      .animation(LiquidGlassTokens.settleSpring, value: isActive)
  }

  private var fill: Color {
    if isActive { return Color.accentColor.opacity(0.22) }
    if configuration.isPressed && isEnabled { return Color.primary.opacity(0.12) }
    return Color.primary.opacity(isHovered ? 0.08 : 0)
  }

  private var foreground: Color {
    guard isEnabled else { return LiquidGlassTokens.inkFaint }
    if isActive { return .accentColor }
    return isHovered ? LiquidGlassTokens.inkPrimary : LiquidGlassTokens.inkBody
  }
}

private struct AnnotateAIDockPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
      .animation(LiquidGlassTokens.pressSpring, value: configuration.isPressed)
  }
}

private struct AnnotateAIDockHairline: View {
  var body: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.12))
      .frame(width: 1, height: 18)
      .padding(.horizontal, 5)
  }
}
