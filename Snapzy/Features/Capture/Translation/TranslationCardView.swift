//
//  TranslationCardView.swift
//  Snapzy
//
//  SwiftUI content of the Snip to Translate window. The window supplies the glass
//  material, corners, border and traffic lights; this view runs under the transparent
//  titlebar and uses the app's Liquid Glass controls (docs/LIQUID_GLASS.md): capsule
//  glass actions and a capsule language menu.
//

import SwiftUI
import Translation

struct TranslationCardView: View {
  @ObservedObject var model: TranslationCardModel
  /// Height of the transparent titlebar the content runs under.
  let titlebarHeight: CGFloat
  let onCopyAndClose: () -> Void
  let onOpenSettings: () -> Void
  let onHeightChange: (CGFloat) -> Void

  @State private var showsOriginal = false
  @State private var copiedOriginal = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Side margin, matching the system's small utility windows.
  private static let margin: CGFloat = 16
  private static let maxTextHeight: CGFloat = 300
  /// Inset wells (text, status) — tile radius sits inside the window corner at this margin.
  private static let wellShape = Radius.rect(Radius.tile)
  /// Source (while reading) and translation share the type, so the swap does not reflow.
  private static let textFont = Font.system(size: 14)
  private static let textLineSpacing: CGFloat = 2

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Without a detected source or a target menu the row would only repeat the window title.
      if sourceName != nil || showsTargetMenu {
        header
      }
      content
    }
    .padding(.horizontal, Self.margin)
    .padding(.top, titlebarHeight + 2)
    .padding(.bottom, Self.margin)
    .frame(width: TranslationCardManager.cardWidth, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
    .background(
      GeometryReader { proxy in
        Color.clear
          .onAppear { onHeightChange(proxy.size.height) }
          .onChange(of: proxy.size.height) { onHeightChange($0) }
      }
    )
    .modifier(AppleTranslationHostModifier(model: model))
    .frame(maxHeight: .infinity, alignment: .top)
    .ignoresSafeArea()
  }

  // MARK: - Header

  /// Source → target, the target being the language menu. The window title says "Translation".
  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      Text(sourceName ?? L10n.Translate.cardTitle)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(LiquidGlassTokens.inkBody)
        .lineLimit(1)

      if showsTargetMenu {
        Image(systemName: "arrow.right")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(LiquidGlassTokens.inkMuted)
        TranslationLanguageMenu(selection: model.target, onSelect: model.selectTarget)
      }

      Spacer(minLength: 0)

      if model.phase == .translating {
        Text(L10n.Translate.translating)
          .font(.system(size: 11))
          .foregroundStyle(LiquidGlassTokens.inkMuted)
          .lineLimit(1)
          .transition(.opacity)
          .accessibilityHidden(true)
      }
    }
    .animation(.easeOut(duration: 0.2), value: model.phase == .translating)
  }

  private var sourceName: String? {
    model.detectedSourceIdentifier.flatMap(Self.languageName)
  }

  private var showsTargetMenu: Bool {
    switch model.phase {
    case .needsTarget, .unavailable:
      return false
    default:
      return model.target != nil
    }
  }

  // MARK: - Content

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .needsTarget:
      chooseTarget
    case .translating, .done:
      // One branch for both, so the well keeps its identity and changes content in place
      // (read → resolve) instead of being swapped for another view.
      translationBody
    case .failed(let failure):
      failureView(failure)
    case .unavailable(let reason):
      unavailableView(reason)
    }
  }

  private var chooseTarget: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.Translate.chooseLanguagePrompt)
        .font(.system(size: 12))
        .foregroundStyle(LiquidGlassTokens.inkBody)
        .fixedSize(horizontal: false, vertical: true)
      ChooseTargetLanguageRow(onTranslate: model.selectTarget)
      originalSection
    }
  }

  private var translationBody: some View {
    let translation = model.translatedText
    let lateEntrance = TranslationCardMotion.lateEntrance(reduceMotion: reduceMotion)
    return VStack(alignment: .leading, spacing: 12) {
      textWell(translation: translation)

      if translation != nil, model.isAlreadyInTarget, let target = model.target {
        note(L10n.Translate.alreadyInTarget(target.displayName), systemImage: "checkmark.circle")
          .transition(lateEntrance)
      }
      // While translating, the source is already on screen in the well.
      if let translation {
        originalSection
          .transition(lateEntrance)
        footer(translation: translation)
          .transition(lateEntrance)
      }
    }
    // No `.animation` here on purpose: the transitions carry their own, and the layout must not
    // interpolate (the well would draw new text outside its old bounds mid-way).
  }

  /// The text well: the source being read while translating, then the translation.
  private func textWell(translation: String?) -> some View {
    ZStack(alignment: .topLeading) {
      if let translation {
        ScrollView {
          TranslationResolvingText(
            text: translation,
            font: Self.textFont,
            lineSpacing: Self.textLineSpacing,
            layoutDirection: model.target.map(Self.layoutDirection) ?? .leftToRight
          )
          .padding(12)
        }
        .frame(maxHeight: Self.maxTextHeight)
        .fixedSize(horizontal: false, vertical: true)
      } else {
        TranslationReadingText(text: model.sourceText, font: Self.textFont, lineSpacing: Self.textLineSpacing)
          .padding(12)
          .transition(TranslationCardMotion.sourceExit(reduceMotion: reduceMotion))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .clipShape(Self.wellShape)
    .background(Self.wellShape.fill(LiquidGlassTokens.veilFill.opacity(0.05)))
    .overlay(Self.wellShape.strokeBorder(LiquidGlassTokens.veilFill.opacity(0.06), lineWidth: 0.5))
    .overlay {
      if translation == nil {
        TranslationReadingRim(shape: Self.wellShape)
          .transition(.opacity.animation(.easeOut(duration: 0.2)))
      }
    }
  }

  @ViewBuilder
  private var originalSection: some View {
    if !model.sourceText.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Button {
          withAnimation(LiquidGlassTokens.settleSpring) { showsOriginal.toggle() }
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "chevron.right")
              .font(.system(size: 8.5, weight: .bold))
              .rotationEffect(.degrees(showsOriginal ? 90 : 0))
            Text(L10n.Translate.originalText)
              .font(.system(size: 11.5, weight: .medium))
            Spacer(minLength: 0)
          }
          .foregroundStyle(LiquidGlassTokens.inkMuted)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if showsOriginal {
          ScrollView {
            Text(model.sourceText)
              .font(.system(size: 12))
              .lineSpacing(1.5)
              .foregroundStyle(LiquidGlassTokens.inkBody)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(10)
          }
          .frame(maxHeight: 150)
          .fixedSize(horizontal: false, vertical: true)
          .background(Self.wellShape.fill(LiquidGlassTokens.veilFill.opacity(0.035)))
          .transition(.scale(scale: 0.98, anchor: .top))
        }
      }
    }
  }

  private func footer(translation: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      engineNote
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        Button {
          TranslationCardPasteboard.copy(model.sourceText)
          flash($copiedOriginal)
        } label: {
          // Both labels are laid out and only one is shown, so the button keeps its width
          // when it flips to "Copied" and nothing next to it shifts.
          ZStack {
            Label(L10n.Translate.copyOriginal, systemImage: "doc.on.doc")
              .opacity(copiedOriginal ? 0 : 1)
            Label(L10n.Translate.copied, systemImage: "checkmark")
              .opacity(copiedOriginal ? 1 : 0)
          }
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))

        LiquidGlassActionButton(
          title: L10n.Translate.copyTranslation,
          trailingKey: "⌘↩",
          emphasis: .primary,
          action: onCopyAndClose
        )
        .help(L10n.Translate.copyTranslation + " (⌘↩)")
      }
      .liquidGlassGroup(spacing: 8)
    }
  }

  @ViewBuilder
  private var engineNote: some View {
    switch model.route {
    case .apple:
      note(L10n.Translate.engineAppleFooter, systemImage: "lock")
    case .remote(let endpoint):
      note(L10n.Translate.engineRemoteFooter(endpoint.name), systemImage: "network")
    case .unavailable:
      EmptyView()
    }
  }

  private func failureView(_ failure: TranslationFailure) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 13))
          .foregroundStyle(.orange)
        Text(Self.message(for: failure))
          .font(.system(size: 12.5))
          .foregroundStyle(LiquidGlassTokens.inkPrimary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .padding(12)
      .background(Self.wellShape.fill(LiquidGlassTokens.veilFill.opacity(0.05)))

      if model.offersEndpointFallback, let endpoint = model.alternativeEndpoint {
        VStack(alignment: .leading, spacing: 6) {
          Button {
            model.translateWithAlternativeEndpoint()
          } label: {
            Label(L10n.Translate.useEndpoint(endpoint.name), systemImage: "network")
              .lineLimit(1)
          }
          .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))
          note(L10n.Translate.useEndpointCaption, systemImage: "info.circle")
        }
      }

      // The source stays reachable, above the actions so they close the window like every state.
      originalSection

      HStack(spacing: 8) {
        Button(L10n.Translate.openSettings, action: onOpenSettings)
          .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))
        Spacer(minLength: 0)
        Button(L10n.Translate.retry) { model.start() }
          .buttonStyle(.liquidGlass(emphasis: .primary, capsule: true))
      }
      .liquidGlassGroup(spacing: 8)
    }
  }

  private func unavailableView(_ reason: TranslationUnavailableReason) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      switch reason {
      case .requiresMacOS15:
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "info.circle.fill")
            .font(.system(size: 13))
            .foregroundStyle(Color.accentColor)
          VStack(alignment: .leading, spacing: 4) {
            Text(L10n.Translate.requiresMacOS15Title)
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(LiquidGlassTokens.inkPrimary)
            Text(model.alternativeEndpoint == nil
              ? L10n.Translate.requiresMacOS15MessageNoEndpoint
              : L10n.Translate.requiresMacOS15MessageWithEndpoint)
              .font(.system(size: 12))
              .foregroundStyle(LiquidGlassTokens.inkBody)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
        }
        .padding(12)
        .background(Self.wellShape.fill(LiquidGlassTokens.veilFill.opacity(0.05)))
      }
      HStack {
        Spacer(minLength: 0)
        Button(L10n.Translate.openSettings, action: onOpenSettings)
          .buttonStyle(.liquidGlass(emphasis: .primary, capsule: true))
      }
    }
  }

  private func note(_ text: String, systemImage: String) -> some View {
    Label {
      Text(text)
        .fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: systemImage)
        .font(.system(size: 9.5, weight: .semibold))
    }
    .font(.system(size: 10.5))
    .foregroundStyle(LiquidGlassTokens.inkMuted)
  }

  private func flash(_ flag: Binding<Bool>) {
    flag.wrappedValue = true
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_400_000_000)
      flag.wrappedValue = false
    }
  }

  // MARK: - Helpers

  static func message(for failure: TranslationFailure) -> String {
    switch failure {
    case .unsupportedLanguagePair:
      return L10n.Translate.errorUnsupportedPair
    case .unableToIdentifyLanguage:
      return L10n.Translate.errorUnidentifiedLanguage
    case .cancelled:
      return L10n.Translate.errorCancelled
    case .other(let description):
      return L10n.Translate.errorGeneric(description)
    }
  }

  /// Rough line count at the card's text width, for the line-by-line reveal's length.
  static func estimatedLineCount(_ text: String) -> Int {
    let charactersPerLine = 46
    return text.split(separator: "\n", omittingEmptySubsequences: false)
      .reduce(0) { $0 + max(1, Int((Double($1.count) / Double(charactersPerLine)).rounded(.up))) }
  }

  static func languageName(_ identifier: String) -> String? {
    let displayLocale = Locale(identifier: AppLanguageManager.shared.activeEffectiveLanguageIdentifier)
    return displayLocale.localizedString(forIdentifier: identifier)
  }

  static func layoutDirection(for language: TranslationLanguage) -> LayoutDirection {
    Locale.Language(identifier: language.identifier).characterDirection == .rightToLeft
      ? .rightToLeft
      : .leftToRight
  }

  /// Pre-selected entry in the first-use picker (the user still confirms it):
  /// the app's display language when supported, else English.
  static var suggestedTarget: TranslationLanguage {
    let appLanguage = Locale.Language(identifier: AppLanguageManager.shared.activeEffectiveLanguageIdentifier)
    return TranslationLanguage.all.first { $0.localeLanguage.languageCode == appLanguage.languageCode
      && ($0.localeLanguage.script == nil || $0.localeLanguage.script == appLanguage.script) }
      ?? TranslationLanguage(identifier: "en")
  }
}

// MARK: - Language menu

/// Capsule glass select (LIQUID_GLASS.md §4b: menus that show text are pills).
private struct TranslationLanguageMenu: View {
  let selection: TranslationLanguage?
  let onSelect: (TranslationLanguage) -> Void
  @ObservedObject private var menuBar = MenuBarCustomizationStore.shared

  var body: some View {
    Menu {
      ForEach(TranslationLanguage.all) { language in
        Button {
          onSelect(language)
        } label: {
          if language == selection {
            Label(language.displayName, systemImage: "checkmark")
              .menuBarRowIcon(showsIcon: menuBar.drawsItemIcons)
          } else {
            Text(language.displayName)
          }
        }
      }
    } label: {
      HStack(spacing: 5) {
        Text(selection?.displayName ?? L10n.Translate.targetLanguageLabel)
          .font(.system(size: 11.5, weight: .medium))
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .semibold))
      }
      .foregroundStyle(LiquidGlassTokens.inkPrimary)
      .padding(.horizontal, 11)
      .frame(height: ControlMetrics.propertyChip)
      .liquidGlassControl(
        isActive: false,
        in: Capsule(style: .continuous),
        showsRestingSurface: true,
        activeGlassTint: nil
      )
    }
    // `.borderlessButton` rebuilds the label itself (chevron moved in front of the name, the
    // glass capsule dropped); the button style keeps the label exactly as drawn.
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(L10n.Translate.targetLanguageLabel)
  }
}

/// First-use row: choose the target language, then translate.
private struct ChooseTargetLanguageRow: View {
  let onTranslate: (TranslationLanguage) -> Void

  @State private var selection = TranslationCardView.suggestedTarget

  var body: some View {
    HStack(spacing: 8) {
      Text(L10n.Translate.targetLanguageLabel)
        .font(.system(size: 12))
        .foregroundStyle(LiquidGlassTokens.inkBody)
      TranslationLanguageMenu(selection: selection) { selection = $0 }
      Spacer(minLength: 0)
      Button(L10n.Translate.translateButton) {
        onTranslate(selection)
      }
      .buttonStyle(.liquidGlass(emphasis: .primary, capsule: true))
      .keyboardShortcut(.defaultAction)
    }
  }
}

// MARK: - Apple Translation host

/// Attaches `.translationTask` on macOS 15+; no-op on older systems.
private struct AppleTranslationHostModifier: ViewModifier {
  @ObservedObject var model: TranslationCardModel

  func body(content: Content) -> some View {
    if #available(macOS 15.0, *) {
      content.modifier(AppleTranslationTaskModifier(model: model))
    } else {
      content
    }
  }
}

@available(macOS 15.0, *)
private struct AppleTranslationTaskModifier: ViewModifier {
  @ObservedObject var model: TranslationCardModel
  @State private var configuration: TranslationSession.Configuration?

  func body(content: Content) -> some View {
    content
      .translationTask(configuration) { @MainActor session in
        await model.runApple(session: session)
      }
      .onAppear(perform: sync)
      .onChange(of: model.appleRequestToken) { _ in sync() }
  }

  /// A new token means "translate now": build the configuration, or
  /// invalidate the existing one so the task runs again.
  private func sync() {
    guard model.isAppleRoute, model.phase == .translating, let target = model.target else { return }
    let next = TranslationSession.Configuration(source: model.appleSourceLanguage, target: target.localeLanguage)
    if configuration?.source == next.source, configuration?.target == next.target {
      configuration?.invalidate()
    } else {
      configuration = next
    }
  }
}
