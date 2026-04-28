//
//  AppToastManager.swift
//  Snapzy
//
//  Global lightweight toast presenter for non-blocking user feedback.
//

import AppKit
import Combine
import SwiftUI

enum AppToastStyle: Equatable {
  case info
  case success
  case warning
  case error

  var iconName: String {
    switch self {
    case .info: return "info.circle.fill"
    case .success: return "checkmark.circle.fill"
    case .warning: return "exclamationmark.triangle.fill"
    case .error: return "xmark.octagon.fill"
    }
  }

  /// Vibrant gradient tints per severity — provides visual distinction on the neutral background.
  var iconGradientColors: [Color] {
    switch self {
    case .info: return [Color.blue, Color.cyan]
    case .success: return [Color.green, Color.mint]
    case .warning: return [Color.orange, Color.yellow]
    case .error: return [Color.red, Color.pink]
    }
  }

  // MARK: - Appearance-adaptive colors (inverted from system theme)

  /// Neutral background — dark on Light mode, light on Dark mode.
  var backgroundColor: NSColor {
    NSColor(name: nil) { appearance in
      if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
        return NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 0.97)
      } else {
        return NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.97)
      }
    }
  }

  var borderColor: NSColor {
    NSColor(name: nil) { appearance in
      if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
        return NSColor(srgbRed: 0.82, green: 0.82, blue: 0.84, alpha: 0.25)
      } else {
        return NSColor(srgbRed: 0.30, green: 0.30, blue: 0.32, alpha: 0.35)
      }
    }
  }

  var textColor: NSColor {
    NSColor(name: nil) { appearance in
      if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
        return NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
      } else {
        return NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
      }
    }
  }
}

enum AppToastPosition: Equatable {
  case topCenter
  case bottomCenter
}

enum AppToastIconMode: Equatable {
  case symbol
  case spinner
}

enum AppToastVariant: Equatable {
  case regular
  case compact

  var iconFontSize: CGFloat {
    switch self {
    case .regular: return 15
    case .compact: return 12
    }
  }

  var textFontSize: CGFloat {
    switch self {
    case .regular: return 13
    case .compact: return 10
    }
  }

  var horizontalPadding: CGFloat {
    switch self {
    case .regular: return 16
    case .compact: return 10
    }
  }

  var verticalPadding: CGFloat {
    switch self {
    case .regular: return 11
    case .compact: return 6
    }
  }

  var contentSpacing: CGFloat {
    switch self {
    case .regular: return 10
    case .compact: return 6
    }
  }

  var minWidth: CGFloat {
    switch self {
    case .regular: return 80
    case .compact: return 60
    }
  }

  var minHeight: CGFloat {
    switch self {
    case .regular: return 44
    case .compact: return 28
    }
  }

  var cornerRadius: CGFloat {
    switch self {
    case .regular: return 10
    case .compact: return 8
    }
  }

  var lineLimit: Int {
    switch self {
    case .regular: return 3
    case .compact: return 2
    }
  }

  var textWeight: Font.Weight {
    switch self {
    case .regular: return .medium
    case .compact: return .semibold
    }
  }

  var measurementWeight: NSFont.Weight {
    switch self {
    case .regular: return .medium
    case .compact: return .semibold
    }
  }
}

struct AppToastHandle {
  fileprivate let id: UUID
}

private struct AppToastPresentation: Equatable {
  let message: String
  let style: AppToastStyle
  let variant: AppToastVariant
  let iconMode: AppToastIconMode
}

@MainActor
private final class AppToastViewModel: ObservableObject {
  @Published private(set) var presentation: AppToastPresentation

  init(presentation: AppToastPresentation) {
    self.presentation = presentation
  }

  func update(_ presentation: AppToastPresentation, animated: Bool) {
    if animated {
      withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
        self.presentation = presentation
      }
    } else {
      self.presentation = presentation
    }
  }
}

@MainActor
final class AppToastManager {
  static let shared = AppToastManager()

  private var panel: NSPanel?
  private var viewModel: AppToastViewModel?
  private var dismissTask: Task<Void, Never>?
  private var activePresentationID = UUID()
  private var activePosition: AppToastPosition = .bottomCenter

  private init() {}

  @discardableResult
  func show(
    message: String,
    style: AppToastStyle = .error,
    position: AppToastPosition = .bottomCenter,
    duration: TimeInterval? = 2.5,
    variant: AppToastVariant = .regular,
    iconMode: AppToastIconMode = .symbol
  ) -> AppToastHandle? {
    let handle = AppToastHandle(id: UUID())
    guard present(
      message: message,
      style: style,
      position: position,
      duration: duration,
      variant: variant,
      iconMode: iconMode,
      presentationID: handle.id
    ) else {
      return nil
    }
    return handle
  }

  func update(
    _ handle: AppToastHandle,
    message: String,
    style: AppToastStyle,
    position: AppToastPosition? = nil,
    duration: TimeInterval? = 2.5,
    variant: AppToastVariant? = nil,
    iconMode: AppToastIconMode = .symbol
  ) {
    guard handle.id == activePresentationID else { return }
    let resolvedVariant = variant ?? viewModel?.presentation.variant ?? .regular
    let resolvedPosition = position ?? activePosition
    _ = present(
      message: message,
      style: style,
      position: resolvedPosition,
      duration: duration,
      variant: resolvedVariant,
      iconMode: iconMode,
      presentationID: handle.id
    )
  }

  func dismiss(_ handle: AppToastHandle) {
    guard handle.id == activePresentationID else { return }
    dismissTask?.cancel()
    dismissTask = nil
    dismissIfNeeded(presentationID: handle.id)
  }

  private func present(
    message: String,
    style: AppToastStyle,
    position: AppToastPosition,
    duration: TimeInterval?,
    variant: AppToastVariant,
    iconMode: AppToastIconMode,
    presentationID: UUID
  ) -> Bool {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    guard let frame = frameForToast(message: trimmed, position: position, variant: variant) else { return false }

    dismissTask?.cancel()
    dismissTask = nil
    activePresentationID = presentationID
    activePosition = position

    let presentation = AppToastPresentation(
      message: trimmed,
      style: style,
      variant: variant,
      iconMode: iconMode
    )
    let viewModel = resolveViewModel(for: presentation)
    let isExistingPanelVisible = panel?.isVisible == true

    if let panel {
      if !panel.isVisible {
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
      } else {
        panel.setFrame(frame, display: true, animate: true)
      }
    } else {
      let newPanel = NSPanel(
        contentRect: frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      newPanel.level = .statusBar
      newPanel.isOpaque = false
      newPanel.backgroundColor = .clear
      newPanel.hasShadow = true
      newPanel.hidesOnDeactivate = false
      newPanel.ignoresMouseEvents = true
      newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
      newPanel.contentView = NSHostingView(rootView: AppToastView(viewModel: viewModel))
      newPanel.alphaValue = 0
      newPanel.orderFrontRegardless()
      panel = newPanel
    }

    viewModel.update(presentation, animated: isExistingPanelVisible)

    if let panel {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.16
        panel.animator().alphaValue = 1
      }
    }

    guard let duration else { return true }

    dismissTask = Task { [weak self] in
      let delay = max(0.8, duration)
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      self?.dismissIfNeeded(presentationID: presentationID)
    }
    return true
  }

  private func resolveViewModel(for presentation: AppToastPresentation) -> AppToastViewModel {
    if let viewModel {
      return viewModel
    }

    let newViewModel = AppToastViewModel(presentation: presentation)
    viewModel = newViewModel
    return newViewModel
  }

  private func dismissIfNeeded(presentationID: UUID) {
    guard presentationID == activePresentationID else { return }
    guard let panel else { return }

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.16
      panel.animator().alphaValue = 0
    }, completionHandler: {
      panel.orderOut(nil)
    })
  }

  private func frameForToast(
    message: String,
    position: AppToastPosition,
    variant: AppToastVariant
  ) -> CGRect? {
    guard let screen = targetScreen() else { return nil }
    let visibleFrame = screen.visibleFrame
    let maxWidth = min(560, visibleFrame.width - 32)
    let size = measuredToastSize(for: message, maxWidth: maxWidth, variant: variant)

    let x = visibleFrame.midX - size.width / 2
    let y: CGFloat
    switch position {
    case .topCenter:
      y = visibleFrame.maxY - size.height - 36
    case .bottomCenter:
      y = visibleFrame.minY + 36
    }

    return CGRect(x: x, y: y, width: size.width, height: size.height)
  }

  private func measuredToastSize(
    for message: String,
    maxWidth: CGFloat,
    variant: AppToastVariant
  ) -> CGSize {
    let font = NSFont.systemFont(ofSize: variant.textFontSize, weight: variant.measurementWeight)
    let iconFrameWidth = variant.iconFontSize + 8
    let horizontalChrome = (variant.horizontalPadding * 2) + iconFrameWidth + variant.contentSpacing
    let maxTextWidth = max(120, maxWidth - horizontalChrome)
    let attributed = NSAttributedString(string: message, attributes: [.font: font])
    let textBounds = attributed.boundingRect(
      with: NSSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let width = min(maxWidth, max(variant.minWidth, ceil(textBounds.width + 2) + horizontalChrome))
    let height = max(variant.minHeight, ceil(textBounds.height) + (variant.verticalPadding * 2))
    return CGSize(width: width, height: height)
  }

  private func targetScreen() -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    if let hovered = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
      return hovered
    }
    return NSScreen.main ?? NSScreen.screens.first
  }
}

private struct AppToastView: View {
  @ObservedObject var viewModel: AppToastViewModel
  @State private var appeared = false

  var body: some View {
    let presentation = viewModel.presentation

    HStack(alignment: .center, spacing: variant.contentSpacing) {
      AppToastIconView(presentation: presentation)

      Text(presentation.message)
        .font(.system(size: presentation.variant.textFontSize, weight: presentation.variant.textWeight))
        .foregroundColor(Color(nsColor: presentation.style.textColor))
        .lineLimit(presentation.variant.lineLimit)
        .multilineTextAlignment(.leading)
    }
    .padding(.horizontal, presentation.variant.horizontalPadding)
    .padding(.vertical, presentation.variant.verticalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RoundedRectangle(cornerRadius: presentation.variant.cornerRadius, style: .continuous)
        .fill(Color(nsColor: presentation.style.backgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: presentation.variant.cornerRadius, style: .continuous)
        .stroke(Color(nsColor: presentation.style.borderColor), lineWidth: 0.5)
    )
    .scaleEffect(appeared ? 1.0 : 0.96)
    .onAppear {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
        appeared = true
      }
    }
  }

  private var variant: AppToastVariant {
    viewModel.presentation.variant
  }
}

private struct AppToastIconView: View {
  let presentation: AppToastPresentation

  var body: some View {
    ZStack {
      switch presentation.iconMode {
      case .symbol:
        Image(systemName: presentation.style.iconName)
          .font(.system(size: presentation.variant.iconFontSize, weight: .semibold))
          .foregroundStyle(
            LinearGradient(
              colors: presentation.style.iconGradientColors,
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .transition(.scale(scale: 0.82).combined(with: .opacity))
      case .spinner:
        AppToastSpinnerView(
          colors: presentation.style.iconGradientColors,
          size: presentation.variant.iconFontSize + 4
        )
        .transition(.scale(scale: 0.82).combined(with: .opacity))
      }
    }
    .frame(width: presentation.variant.iconFontSize + 8, height: presentation.variant.iconFontSize + 8)
  }
}

private struct AppToastSpinnerView: View {
  let colors: [Color]
  let size: CGFloat

  @State private var isSpinning = false

  var body: some View {
    Circle()
      .trim(from: 0.18, to: 1)
      .stroke(
        AngularGradient(
          gradient: Gradient(colors: colors.map { $0.opacity(0.15) } + [colors.last ?? .cyan]),
          center: .center
        ),
        style: StrokeStyle(lineWidth: max(2, size * 0.15), lineCap: .round)
      )
      .frame(width: size, height: size)
      .rotationEffect(.degrees(isSpinning ? 360 : 0))
      .onAppear {
        guard !isSpinning else { return }
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
          isSpinning = true
        }
      }
  }
}
