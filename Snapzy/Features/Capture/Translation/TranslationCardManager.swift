//
//  TranslationCardManager.swift
//  Snapzy
//
//  The Snip to Translate window, shown next to the captured area. A regular titled
//  window with the system traffic lights, backed by the system Liquid Glass material on
//  macOS 26 (same construction as `ColorPickerResultWindow`). One window at a time; no
//  auto-dismiss. Keyboard handling (Esc, ⌘↩, ⌘C, ⌘W) lives on the window itself, so
//  nothing is registered while it is not open and key.
//

import AppKit
import SwiftUI

@MainActor
final class TranslationCardManager: NSObject, NSWindowDelegate {
  static let shared = TranslationCardManager()

  static let cardWidth: CGFloat = 400
  private static let anchorGap: CGFloat = 12
  private static let screenMargin: CGFloat = 12

  /// Height of the titlebar the content runs under (`.fullSizeContentView`).
  static let titlebarHeight: CGFloat = {
    let content = CGRect(x: 0, y: 0, width: 100, height: 100)
    return NSWindow.frameRect(forContentRect: content, styleMask: [.titled, .closable, .miniaturizable]).height
      - content.height
  }()

  /// Height of the SwiftUI canvas behind the window (see `show`); above any card height.
  private static let canvasHeight: CGFloat = 1200

  private var window: TranslationCardWindow?
  private var model: TranslationCardModel?
  /// AppKit global rect the card sits next to (the captured area, or the pointer).
  private var anchorRect: CGRect = .zero
  /// Latest height reported by the view, waiting to be applied (see `updateHeight`).
  private var pendingHeight: CGFloat?
  /// App that was frontmost before the card took focus; it gets focus back on close.
  private var previousApp: NSRunningApplication?

  override private init() {
    super.init()
  }

  var isVisible: Bool {
    window != nil
  }

  /// Shows the card for recognized text captured from `anchorRect` (AppKit global points).
  func present(sourceText: String, anchorRect: CGRect) {
    let resolver = TranslationEngineResolver()
    let route = resolver.resolve()
    let model = TranslationCardModel(
      sourceText: sourceText,
      route: route,
      target: TranslationLanguage.storedTarget(),
      alternativeEndpoint: resolver.firstAvailableEndpoint()
    )
    // Resolve the phase before the view exists: the Apple host starts its translation task on
    // first appearance while the phase is `.translating`, so starting afterwards let an
    // "already in the target language" card still run Apple Translation and show its error.
    model.start()
    show(model: model, anchorRect: anchorRect)
  }

  /// Shows the card explaining why translation can't run on this Mac (no selection happens).
  func presentUnavailable(_ reason: TranslationUnavailableReason) {
    let resolver = TranslationEngineResolver()
    let model = TranslationCardModel(
      sourceText: "",
      route: .unavailable(reason),
      target: TranslationLanguage.storedTarget(),
      alternativeEndpoint: resolver.firstAvailableEndpoint()
    )
    let pointer = NSEvent.mouseLocation
    show(model: model, anchorRect: CGRect(x: pointer.x, y: pointer.y, width: 1, height: 1))
  }

  func dismiss() {
    window?.performClose(nil)
  }

  /// ⌘↩ and the primary button: copy the translation, then close.
  func copyTranslationAndClose() {
    guard let text = model?.translatedText else { return }
    TranslationCardPasteboard.copy(text)
    QuickAccessSound.complete.play()
    dismiss()
  }

  // MARK: - Window

  private func show(model: TranslationCardModel, anchorRect: CGRect) {
    closeImmediately()
    self.model = model
    self.anchorRect = anchorRect

    let view = makeView(model: model)
    // Measure with a default hosting view: one with `sizingOptions = []` reports no fitting
    // size, which left the window at a placeholder height with the content overflowing up
    // under the traffic lights.
    let initialHeight = max(Self.titlebarHeight + 120, NSHostingView(rootView: view).fittingSize.height)
    let hostingView = NSHostingView(rootView: view)
    // The manager sizes the window itself so the top edge stays put while the
    // content grows (translating → done); letting the hosting view drive the
    // window size as well loops the constraint pass inside a glass container.
    hostingView.sizingOptions = []
    // A fixed-height canvas pinned to the window's top edge; the window clips it. Height changes
    // then only resize the window (and its glass), never re-layout the SwiftUI content mid
    // animation: content taller than its hosting view was laid out off-center for a frame,
    // which made the header jump and the titlebar tear while the window grew.
    let canvasHeight = Self.canvasHeight
    let container = NSView(frame: CGRect(x: 0, y: 0, width: Self.cardWidth, height: initialHeight))
    container.autoresizingMask = [.width, .height]
    hostingView.frame = CGRect(x: 0, y: initialHeight - canvasHeight, width: Self.cardWidth, height: canvasHeight)
    hostingView.autoresizingMask = [.width, .minYMargin]
    container.addSubview(hostingView)

    let newWindow = TranslationCardWindow(
      contentRect: frame(forHeight: initialHeight),
      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    newWindow.title = L10n.Translate.cardTitle
    newWindow.titlebarAppearsTransparent = true
    newWindow.isMovableByWindowBackground = true
    newWindow.isReleasedWhenClosed = false
    newWindow.hidesOnDeactivate = false
    // Floats above the app it translates, so clicking back into that app keeps it visible.
    newWindow.level = .floating
    newWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    newWindow.appearance = ThemeManager.shared.nsAppearance
    newWindow.delegate = self
    newWindow.setFrame(frame(forHeight: initialHeight), display: false)
    // Assign before installing the content: the view reports its height on first layout,
    // and `updateHeight` ignores reports while `window` is still nil.
    window = newWindow

    if #available(macOS 26.0, *) {
      // System Liquid Glass behind the whole window, titlebar included. No corner radius of its
      // own: the window clips the corners and draws the single border and shadow.
      newWindow.isOpaque = false
      newWindow.backgroundColor = .clear
      let glass = NSGlassEffectView()
      glass.cornerRadius = 0
      glass.contentView = container
      newWindow.contentView = glass
    } else {
      newWindow.backgroundColor = .windowBackgroundColor
      newWindow.contentView = container
    }

    newWindow.onCancel = { [weak self] in self?.dismiss() }
    newWindow.onCopyAndClose = { [weak self] in
      guard let self, self.model?.translatedText != nil else { return false }
      self.copyTranslationAndClose()
      return true
    }
    newWindow.onCopy = { [weak model] in
      guard let text = model?.translatedText else { return false }
      TranslationCardPasteboard.copy(text)
      return true
    }

    // Key + active so the traffic lights, ⌘↩ and Esc work; the previous app is
    // re-activated on close.
    let frontmost = NSWorkspace.shared.frontmostApplication
    if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
      previousApp = frontmost
    }
    NSApp.activate(ignoringOtherApps: true)
    newWindow.makeKeyAndOrderFront(nil)
  }

  private func makeView(model: TranslationCardModel) -> TranslationCardView {
    TranslationCardView(
      model: model,
      titlebarHeight: Self.titlebarHeight,
      onCopyAndClose: { [weak self] in self?.copyTranslationAndClose() },
      onOpenSettings: { [weak self] in self?.openSettings() },
      onHeightChange: { [weak self] height in self?.updateHeight(height) }
    )
  }

  private func closeImmediately() {
    guard let window else { return }
    window.delegate = nil
    window.orderOut(nil)
    self.window = nil
    model?.cancel()
    model = nil
    pendingHeight = nil
  }

  /// Height reports arrive from SwiftUI while it is still laying out the hosting view.
  /// Resizing the window inside that pass leaves the content view (glass + hosting view) at
  /// the old size: the content then drifts away from the titlebar or gets clipped. So the
  /// latest report is applied once, on the next turn of the run loop.
  private func updateHeight(_ height: CGFloat) {
    guard window != nil, height > 0 else { return }
    let isScheduled = pendingHeight != nil
    pendingHeight = height
    guard !isScheduled else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, let height = self.pendingHeight else { return }
      self.pendingHeight = nil
      self.applyHeight(height)
    }
  }

  private func applyHeight(_ height: CGFloat) {
    guard let window else { return }
    let current = window.frame
    if abs(current.height - height) > 0.5 {
      // Keep the top edge where the user sees (or dragged) it.
      var newFrame = CGRect(x: current.minX, y: current.maxY - height, width: current.width, height: height)
      if let visible = screen(containing: current)?.visibleFrame, newFrame.minY < visible.minY + Self.screenMargin {
        newFrame.origin.y = visible.minY + Self.screenMargin
      }
      // Glide to the new height on the same curve as the content (read → resolve), so the
      // window grows with the text instead of snapping; instant under Reduce Motion.
      let animates = window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      NSAnimationContext.runAnimationGroup { context in
        context.duration = animates ? TranslationCardMotion.revealDuration : 0
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
        context.allowsImplicitAnimation = animates
        if animates {
          window.animator().setFrame(newFrame, display: true)
        } else {
          window.setFrame(newFrame, display: true)
        }
      } completionHandler: { [weak window] in
        MainActor.assumeIsolated {
          if let window { Self.pinContentView(of: window) }
        }
      }
    }
    Self.pinContentView(of: window)
  }

  /// `.fullSizeContentView`: the content view covers the whole frame. Re-asserted in case a
  /// layout pass still in flight kept the old size.
  private static func pinContentView(of window: NSWindow) {
    if let contentView = window.contentView, contentView.frame.size != window.frame.size {
      contentView.frame = CGRect(origin: .zero, size: window.frame.size)
    }
  }

  // MARK: - NSWindowDelegate

  func windowWillClose(_ notification: Notification) {
    guard let closing = notification.object as? NSWindow, closing === window else { return }
    model?.cancel()
    model = nil
    window = nil
    let previous = previousApp
    previousApp = nil
    // Hand focus back to the app the text came from, unless the user moved on already.
    if NSApp.isActive, let previous, !previous.isTerminated {
      previous.activate()
    }
  }

  /// Right of the anchor if it fits, else left, else below; clamped to the screen.
  private func frame(forHeight height: CGFloat) -> CGRect {
    let size = CGSize(width: Self.cardWidth, height: height)
    let visible = (screen(containing: anchorRect) ?? NSScreen.main)?.visibleFrame
      ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let margin = Self.screenMargin
    let gap = Self.anchorGap

    var origin: CGPoint
    if anchorRect.maxX + gap + size.width <= visible.maxX - margin {
      origin = CGPoint(x: anchorRect.maxX + gap, y: anchorRect.maxY - size.height)
    } else if anchorRect.minX - gap - size.width >= visible.minX + margin {
      origin = CGPoint(x: anchorRect.minX - gap - size.width, y: anchorRect.maxY - size.height)
    } else {
      origin = CGPoint(x: anchorRect.midX - size.width / 2, y: anchorRect.minY - gap - size.height)
    }

    origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - margin - size.width)
    origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - margin - size.height)
    return CGRect(origin: origin, size: size)
  }

  private func screen(containing rect: CGRect) -> NSScreen? {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    return NSScreen.screens.first { $0.frame.contains(center) }
      ?? NSScreen.screens.max { lhs, rhs in
        lhs.frame.intersection(rect).width * lhs.frame.intersection(rect).height
          < rhs.frame.intersection(rect).width * rhs.frame.intersection(rect).height
      }
  }

  private func openSettings() {
    dismiss()
    AppStatusBarController.shared.openPreferencesWindow(tab: .capture)
    PreferencesNavigationState.shared.reveal(
      PreferencesSearchEntry(
        .capture,
        section: L10n.Translate.settingsSection,
        title: L10n.Translate.settingsEngineTitle,
        keywords: []
      ).inPane("ocr")
    )
  }
}

enum TranslationCardPasteboard {
  @MainActor
  static func copy(_ text: String) {
    ClipboardHelper.copyText(text)
  }
}

/// The translation window. Its shortcuts only exist while it is the key window:
/// Esc / ⌘W close, ⌘↩ copies the translation and closes, ⌘C copies it unless text is selected.
final class TranslationCardWindow: NSWindow {
  var onCancel: (() -> Void)?
  /// Return false when there is nothing to copy yet (the key event then passes on).
  var onCopyAndClose: (() -> Bool)?
  var onCopy: (() -> Bool)?

  override func cancelOperation(_ sender: Any?) {
    onCancel?()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
    guard flags == .command else { return super.performKeyEquivalent(with: event) }

    switch event.keyCode {
    case 36, 76: // Return, keypad Enter
      if onCopyAndClose?() == true { return true }
    default:
      switch event.charactersIgnoringModifiers?.lowercased() {
      case "c":
        if !hasTextSelection, onCopy?() == true { return true }
      case "w":
        onCancel?()
        return true
      default:
        break
      }
    }
    return super.performKeyEquivalent(with: event)
  }

  /// ⌘C with selected text keeps the normal "copy selection" behavior.
  private var hasTextSelection: Bool {
    guard let textView = firstResponder as? NSTextView else { return false }
    return textView.selectedRanges.contains { $0.rangeValue.length > 0 }
  }
}
