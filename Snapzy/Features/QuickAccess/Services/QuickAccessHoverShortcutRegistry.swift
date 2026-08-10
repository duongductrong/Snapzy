//
//  QuickAccessHoverShortcutRegistry.swift
//  Snapzy
//
//  Registers Quick Access card action shortcuts as Carbon hotkeys, scoped to the
//  window where the pointer is over a card.
//
//  The Quick Access panel is a non-activating panel (`canBecomeKey == false`), so
//  keyboard events never route to it — the frontmost app owns the keyboard while
//  the user hovers a card. Carbon hotkeys are the only delivery path that both
//  works without Accessibility permission and *consumes* the keystroke, so ⌘C on a
//  hovered card does not also copy in the app underneath.
//
//  Because these bindings shadow the frontmost app while registered, every path
//  that ends a hover must tear them down. `QuickAccessManager` owns the hover
//  state and is the single caller of `setHoverActive`.
//

import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class QuickAccessHoverShortcutRegistry {
  /// Called on the main actor when a registered binding fires.
  var onTrigger: ((QuickAccessActionKind) -> Void)?

  private let store: QuickAccessActionShortcutStore
  private var hotKeyRefs: [QuickAccessActionKind: EventHotKeyRef] = [:]
  private var eventHandler: EventHandlerRef?
  private var isHoverActive = false
  private var isRegistered = false
  private var pendingDisarm: DispatchWorkItem?
  private var storeObservers: Set<AnyCancellable> = []

  /// "ZQHS" — Quick Access hover shortcuts. Distinct from `KeyboardShortcutManager`
  /// (`ZSFx`) and the panel-scoped edit hotkey (`QuickAccessManager.editHotKeyID`).
  private static let hotKeySignature = OSType(0x5A51_4853)

  /// Delay before bindings are physically unregistered after hover ends.
  ///
  /// Registering/unregistering Carbon hotkeys is a synchronous WindowServer IPC
  /// on the main thread, and moving the pointer between cards produces an
  /// exit+enter pair within milliseconds. Coalescing turns each card crossing
  /// into a no-op instead of a full unregister+register round-trip; the cost is
  /// that bindings stay live for this tail after the pointer leaves the last
  /// card (triggers are still gated by `isHoverActive`, so nothing fires).
  private static let disarmDelay: TimeInterval = 0.25

  init(store: QuickAccessActionShortcutStore = .shared) {
    self.store = store
    observeStore()
  }

  deinit {
    // Carbon teardown must run on the main actor; `QuickAccessManager` holds this
    // for the app lifetime, so rely on explicit `setHoverActive(false)` instead.
  }

  // MARK: - Hover lifecycle

  func setHoverActive(_ active: Bool) {
    guard active != isHoverActive else { return }
    isHoverActive = active
    if active {
      arm()
    } else {
      scheduleDisarm()
    }
  }

  /// Registers bindings unless they are still registered from the current hover
  /// session — the common case when the pointer moves directly between cards.
  private func arm() {
    if let pendingDisarm {
      pendingDisarm.cancel()
      self.pendingDisarm = nil
    }
    guard !isRegistered else { return }
    registerAll()
  }

  private func scheduleDisarm() {
    pendingDisarm?.cancel()
    let work = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.isHoverActive else { return }
        self.pendingDisarm = nil
        self.unregisterAll()
      }
    }
    pendingDisarm = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.disarmDelay, execute: work)
  }

  /// Re-applies the current bindings without changing hover state. Used when the
  /// user edits a shortcut while a card happens to be hovered.
  func refreshRegistration() {
    guard isHoverActive else { return }
    unregisterAll()
    registerAll()
  }

  // MARK: - Registration

  private func registerAll() {
    installEventHandlerIfNeeded()

    for binding in store.activeBindings {
      guard let id = Self.hotKeyID(for: binding.action) else { continue }
      var ref: EventHotKeyRef?
      let status = RegisterEventHotKey(
        binding.shortcut.keyCode,
        binding.shortcut.modifiers,
        id,
        GetApplicationEventTarget(),
        0,
        &ref
      )
      guard status == noErr, let ref else {
        DiagnosticLogger.shared.log(
          .warning,
          .action,
          "Quick access card shortcut registration failed",
          context: ["action": binding.action.rawValue, "status": "\(status)"]
        )
        continue
      }
      hotKeyRefs[binding.action] = ref
    }
    isRegistered = true
  }

  private func unregisterAll() {
    for ref in hotKeyRefs.values {
      UnregisterEventHotKey(ref)
    }
    hotKeyRefs.removeAll()
    isRegistered = false
  }

  private func installEventHandlerIfNeeded() {
    guard eventHandler == nil else { return }

    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: OSType(kEventHotKeyPressed)
    )
    let callback: EventHandlerUPP = { _, event, userData in
      guard let userData, let event else { return OSStatus(eventNotHandledErr) }

      var hotKeyID = EventHotKeyID()
      GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
      )
      guard hotKeyID.signature == QuickAccessHoverShortcutRegistry.hotKeySignature else {
        return OSStatus(eventNotHandledErr)
      }
      guard let action = QuickAccessHoverShortcutRegistry.action(for: hotKeyID.id) else {
        return OSStatus(eventNotHandledErr)
      }

      let registry = Unmanaged<QuickAccessHoverShortcutRegistry>
        .fromOpaque(userData)
        .takeUnretainedValue()
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          registry.handleTrigger(action)
        }
      }
      return noErr
    }

    InstallEventHandler(
      GetApplicationEventTarget(),
      callback,
      1,
      &spec,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )
  }

  private func handleTrigger(_ action: QuickAccessActionKind) {
    // A hotkey press can land after the pointer left the card, since Carbon
    // delivery is async relative to the unregister call.
    guard isHoverActive else { return }
    onTrigger?(action)
  }

  // MARK: - Store observation

  private func observeStore() {
    // `@Published` emits in `willSet`, so the store still reports the previous
    // values inside the sink. Hop a runloop turn before reading `activeBindings`.
    store.$shortcuts
      .dropFirst()
      .sink { [weak self] _ in self?.scheduleRefresh() }
      .store(in: &storeObservers)

    store.$disabledActions
      .dropFirst()
      .sink { [weak self] _ in self?.scheduleRefresh() }
      .store(in: &storeObservers)

    store.$isEnabled
      .dropFirst()
      .sink { [weak self] _ in self?.scheduleRefresh() }
      .store(in: &storeObservers)
  }

  private func scheduleRefresh() {
    guard isHoverActive else { return }
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        self?.refreshRegistration()
      }
    }
  }

  // MARK: - Hotkey identity

  /// Stable per-action ID derived from the declaration order, so a hotkey press
  /// maps back to its action without carrying extra state.
  private static func hotKeyID(for action: QuickAccessActionKind) -> EventHotKeyID? {
    guard let index = QuickAccessActionKind.defaultOrder.firstIndex(of: action) else { return nil }
    return EventHotKeyID(signature: hotKeySignature, id: UInt32(index + 1))
  }

  private static func action(for rawID: UInt32) -> QuickAccessActionKind? {
    let index = Int(rawID) - 1
    guard QuickAccessActionKind.defaultOrder.indices.contains(index) else { return nil }
    return QuickAccessActionKind.defaultOrder[index]
  }
}
