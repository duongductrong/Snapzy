//
//  QuickAccessCardView.swift
//  Snapzy
//
//  Single quick access card with swipe-to-dismiss and drag-to-external-app
//  Direction-based gesture handling: swipe toward edge = dismiss, drag away = external app
//

import AppKit
import SwiftUI

/// Displays a single item preview with hover-activated actions and swipe gestures
struct QuickAccessCardView: View {
  let item: QuickAccessItem
  let manager: QuickAccessManager
  var onHover: ((Bool) -> Void)? = nil

  @ObservedObject private var preferencesManager = PreferencesManager.shared
  @ObservedObject private var actionConfiguration = QuickAccessActionConfigurationStore.shared
  @ObservedObject private var trackpadSwipeModeStore = QuickAccessTrackpadSwipeModeStore.shared
  @ObservedObject private var swipeActionStore = QuickAccessSwipeActionStore.shared
  @ObservedObject private var cloudManager = CloudManager.shared
  @State private var isHovering = false
  @State private var isDragging = false
  @State private var isSwiping = false
  @State private var isDismissing = false
  @State private var swipeOffset: CGFloat = 0
  @State private var isCloudUploading = false
  @State private var cloudUploadProgress: Double = 0
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  private let cornerRadius: CGFloat = 16

  /// Scaled card dimensions based on overlay scale setting
  private var scaledWidth: CGFloat { QuickAccessLayout.scaledCardWidth(CGFloat(manager.overlayScale)) }
  private var scaledHeight: CGFloat { QuickAccessLayout.scaledCardHeight(CGFloat(manager.overlayScale)) }

  /// Dismiss direction based on panel position
  /// Right side panel: swipe right to dismiss (+1)
  /// Left side panel: swipe left to dismiss (-1)
  private var dismissDirection: CGFloat {
    manager.position.isLeftSide ? -1 : 1
  }

  var body: some View {
    ZStack(alignment: .center) {
      thumbnailLayer

      // Pin indicator (pinned items when pin action is NOT assigned to a slot)
      if item.isPinned, !isPinActionOnCard {
        pinIndicator
      }

      // Duration badge (videos only, bottom-right)
      if let duration = item.formattedDuration {
        durationBadge(duration)
      }

      // Processing progress overlay
      if item.processingState != .idle {
        QuickAccessProgressView(state: item.processingState)
          .transition(.opacity)
      }

      // Cloud upload progress overlay
      if isCloudUploading {
        QuickAccessProgressView(state: .processing(progress: cloudUploadProgress))
          .transition(.opacity)
      }

      // Hover overlay with staggered buttons (hidden while swiping so it does not
      // visually fight the swipe gesture).
      if isHovering && !isSwiping && canPerformCardActions && hasVisibleOverlayActions {
        hoverOverlay
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
      }

      // Corner buttons (only visible on hover, hidden during cloud upload and swipe).
      if isHovering && !isSwiping && canPerformCardActions && !cornerOverlayActions.isEmpty {
        cornerButtons
      }
    }
    .frame(width: scaledWidth, height: scaledHeight)
    .clipShape(cardShape)
    .contentShape(cardShape)
    .background(
      cardShape
        .fill(Color.black.opacity(0.1))
    )
    .overlay(
      cardShape
        .stroke(Color.white.opacity(0.2), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
    .opacity(cardOpacity)
    .offset(x: reduceMotion ? 0 : swipeOffset)
    .rotationEffect(.degrees(reduceMotion ? 0 : Double(swipeOffset) * 0.03))
    .onHover { hovering in
      withAnimation(QuickAccessAnimations.hoverOverlay) {
        isHovering = hovering
      }
      onHover?(hovering)

      // Pause/resume countdown on hover if enabled
      if manager.pauseCountdownOnHover {
        if hovering {
          manager.pauseCountdown(for: item.id)
        } else {
          manager.resumeCountdown(for: item.id)
        }
      }
    }
    .onTapGesture(count: 2) {
      handleDoubleClick()
    }
    .background(
      QuickAccessContextMenuPresenter(entries: quickAccessContextMenuEntries)
        .frame(width: scaledWidth, height: scaledHeight)
    )
    .overlay(dragInteractionBridge.frame(width: scaledWidth, height: scaledHeight))
    .onDisappear {
      isDragging = false
    }
    .animation(QuickAccessAnimations.hoverOverlay, value: isHovering)
  }

  // MARK: - Computed Properties

  private var cardOpacity: Double {
    if isDragging { return 0.6 }
    if isDismissing { return 0 }
    if reduceMotion { return 1.0 }
    return 1.0 - Double(abs(swipeOffset)) / 200.0
  }

  private var captureType: CaptureType {
    item.isVideo ? .recording : .screenshot
  }

  private var isTempFile: Bool {
    TempCaptureManager.shared.isTempFile(item.url)
  }

  private var saveOrOpenActionTitle: String {
    isTempFile ? L10n.Common.save : L10n.Common.open
  }

  private var editActionTitle: String {
    item.isVideo ? L10n.QuickAccess.editVideo : L10n.AnnotateUI.modeAnnotate
  }

  private var deleteActionTitle: String {
    isTempFile ? L10n.Common.deleteAction : L10n.Common.moveToTrash
  }

  private var alreadyUploadedToCloud: Bool {
    item.cloudURL != nil && !item.isCloudStale
  }

  private var cloudActionTitle: String {
    if alreadyUploadedToCloud {
      return L10n.AnnotateUI.uploadedToCloud
    }
    return item.isCloudStale ? L10n.AnnotateUI.reuploadToCloud : L10n.AnnotateUI.uploadToCloud
  }

  private var cloudActionIcon: String {
    alreadyUploadedToCloud ? "checkmark.icloud" : "icloud.and.arrow.up"
  }

  private var canPerformCardActions: Bool {
    item.processingState == .idle && !isCloudUploading
  }

  private var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }

  private var orderedEnabledActions: [QuickAccessActionKind] {
    actionConfiguration.orderedActions(includeDisabled: false)
  }

  private var primaryOverlayActions: [QuickAccessActionKind] {
    QuickAccessActionSlot.centerSlots.compactMap(overlayAction)
  }

  private var cornerOverlayActions: [QuickAccessActionKind] {
    QuickAccessActionSlot.cornerSlots.compactMap(overlayAction)
  }

  private var hasVisibleOverlayActions: Bool {
    !primaryOverlayActions.isEmpty || !cornerOverlayActions.isEmpty
  }

  private func overlayAction(in slot: QuickAccessActionSlot) -> QuickAccessActionKind? {
    guard let action = actionConfiguration.action(in: slot),
          actionConfiguration.isEnabled(action),
          isActionAvailable(action, on: .overlay) else {
      return nil
    }
    return action
  }

  // MARK: - Gestures

  private var dragInteractionBridge: some View {
    QuickAccessDraggableView(
      fileURL: item.url,
      thumbnail: item.thumbnail,
      dismissDirection: dismissDirection,
      dragDropEnabled: manager.dragDropEnabled,
      twoFingerSwipeToDismissEnabled: manager.twoFingerSwipeToDismissEnabled,
      swipeMode: trackpadSwipeModeStore.mode,
      onDragStarted: {
        isDragging = true
      },
      onDragEnded: { success in
        isDragging = false
        if success {
          // Only remove card from UI — don't delete the file.
          // Temp files stay available for the receiving app.
          manager.dismissCard(id: item.id)
        }
      },
      onSwipeChanged: { translation in
        guard !reduceMotion else { return }
        var finalTranslation = translation
        if finalTranslation > 0 && swipeActionStore.action(for: .right) == nil {
          finalTranslation = 0
        } else if finalTranslation < 0 && swipeActionStore.action(for: .left) == nil {
          finalTranslation = 0
        }

        guard finalTranslation != 0 else {
          swipeOffset = 0
          isSwiping = false
          return
        }

        swipeOffset = finalTranslation
        isSwiping = true
      },
      onSwipeEnded: { translation, velocity in
        isSwiping = false
        var finalTranslation = translation
        var finalVelocity = velocity
        if finalTranslation > 0 && swipeActionStore.action(for: .right) == nil {
          finalTranslation = 0
          finalVelocity = 0
        } else if finalTranslation < 0 && swipeActionStore.action(for: .left) == nil {
          finalTranslation = 0
          finalVelocity = 0
        }

        handleSwipeEnded(translation: finalTranslation, velocity: finalVelocity)
      },
      swipeSensitivity: CGFloat(manager.swipeSensitivity)
    )
  }

  private func handleSwipeEnded(translation: CGFloat, velocity: CGFloat) {
    let distanceThreshold = QuickAccessCardDragPolicy.dismissDistanceThreshold
    let velocityThreshold = QuickAccessCardDragPolicy.dismissVelocityThreshold

    guard abs(translation) > distanceThreshold || abs(velocity) > velocityThreshold else {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        swipeOffset = 0
      }
      return
    }

    let direction: QuickAccessSwipeDirection = translation > 0 ? .right : .left
    guard let configuredAction = swipeActionStore.action(for: direction) else {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        swipeOffset = 0
      }
      return
    }

    swipeOffset = 0

    if configuredAction == .dismiss {
      isDismissing = true
      QuickAccessSound.dismiss.play(reduceMotion: reduceMotion)
      manager.removeScreenshot(id: item.id)
    } else {
      performAction(configuredAction)
    }
  }

  // MARK: - Actions

  private func actionTitle(for action: QuickAccessActionKind) -> String {
    switch action {
    case .copy:
      return L10n.Common.copy
    case .saveOrOpen:
      return saveOrOpenActionTitle
    case .dismiss:
      return L10n.Common.close
    case .delete:
      return deleteActionTitle
    case .edit:
      return editActionTitle
    case .uploadToCloud:
      return cloudActionTitle
    case .pinToScreen:
      return item.isPinned ? L10n.PreferencesQuickAccess.unpinAction : L10n.PreferencesQuickAccess.pinToScreenAction
    }
  }

  private func actionIcon(for action: QuickAccessActionKind) -> String {
    switch action {
    case .saveOrOpen:
      return isTempFile ? "square.and.arrow.down" : "folder"
    case .uploadToCloud:
      return cloudActionIcon
    case .pinToScreen:
      return item.isPinned ? "pin.fill" : "pin"
    default:
      return action.systemImage
    }
  }

  private func isActionAvailable(
    _ action: QuickAccessActionKind,
    on _: QuickAccessActionSurface
  ) -> Bool {
    switch action {
    case .copy, .dismiss, .edit:
      return true
    case .pinToScreen:
      return true
    case .saveOrOpen:
      return true
    case .uploadToCloud:
      return shouldShowCloudButton
    case .delete:
      return true
    }
  }

  private func isActionEnabled(_ action: QuickAccessActionKind) -> Bool {
    switch action {
    case .pinToScreen:
      return !item.isVideo
    case .uploadToCloud:
      return shouldShowCloudButton && !alreadyUploadedToCloud && !isCloudUploading
    case .copy, .saveOrOpen, .dismiss, .delete, .edit:
      return true
    }
  }

  private func performAction(_ action: QuickAccessActionKind) {
    guard isActionEnabled(action) else { return }

    switch action {
    case .copy:
      copyItem()
    case .saveOrOpen:
      saveOrOpenItem()
    case .dismiss:
      dismissItem()
    case .delete:
      deleteItem()
    case .edit:
      handleDoubleClick()
    case .uploadToCloud:
      uploadToCloud()
    case .pinToScreen:
      guard !item.isVideo else { return }
      manager.togglePin(id: item.id)
    }
  }

  private func handleDoubleClick() {
    if item.isVideo {
      openVideoEditor()
    } else {
      openAnnotation()
    }
  }

  private func openAnnotation() {
    Task { @MainActor in
      await Task.yield()
      AnnotateManager.shared.openAnnotation(for: item)
    }
  }

  private func openVideoEditor() {
    Task { @MainActor in
      VideoEditorManager.shared.openEditor(for: item)
    }
  }

  private func copyItem() {
    QuickAccessSound.copy.play(reduceMotion: reduceMotion)
    manager.copyToClipboard(id: item.id)
  }

  private func saveOrOpenItem() {
    QuickAccessSound.save.play(reduceMotion: reduceMotion)
    if isTempFile {
      manager.saveItem(id: item.id)
    } else {
      manager.openInFinder(id: item.id)
    }
  }

  private func dismissItem() {
    isDismissing = true
    QuickAccessSound.dismiss.play(reduceMotion: reduceMotion)
    manager.removeScreenshot(id: item.id)
  }

  private func deleteItem() {
    isDismissing = true
    manager.deleteItem(id: item.id)
  }

  // MARK: - Subviews

  private var thumbnailLayer: some View {
    // Clipped scaled-to-fill images can still expose their hidden area to hit
    // testing, so the thumbnail stays decorative and the card owns interaction.
    Image(nsImage: item.thumbnail)
      .resizable()
      .aspectRatio(contentMode: .fill)
      .frame(width: scaledWidth, height: scaledHeight)
      .clipped()
      .blur(radius: isHovering ? 2 : 0)
      .contentShape(Rectangle())
      .allowsHitTesting(false)
  }

  private func durationBadge(_ duration: String) -> some View {
    VStack {
      Spacer()
      HStack {
        Spacer()
        Text(duration)
          .font(.system(size: 10, weight: .semibold, design: .monospaced))
          .foregroundColor(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.black.opacity(0.7))
          )
          .padding(6)
      }
    }
  }

  private var isPinActionOnCard: Bool {
    actionConfiguration.assignedSlot(for: .pinToScreen) != nil
      && actionConfiguration.isEnabled(.pinToScreen)
  }

  private var pinIndicator: some View {
    Image(systemName: "pin.fill")
      .font(.system(size: 10, weight: .bold))
      .foregroundColor(.white)
      .frame(width: 20, height: 20)
      .background(Circle().fill(Color.black.opacity(0.6)))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(6)
      .contentShape(Circle())
      .onTapGesture {
        manager.togglePin(id: item.id)
      }
      .help(item.isPinned ? L10n.PreferencesQuickAccess.unpinAction : L10n.PreferencesQuickAccess.pinToScreenAction)
  }

  private var hoverOverlay: some View {
    ZStack {
      // Dimming overlay
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.black.opacity(0.4))

      // Action buttons with stagger effect
      VStack(spacing: 8) {
        ForEach(Array(QuickAccessActionSlot.centerSlots.enumerated()), id: \.element) { index, slot in
          if let action = overlayAction(in: slot) {
            staggeredButton(action: action, delay: index)
          } else {
            Color.clear.frame(height: 28)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func staggeredButton(action: QuickAccessActionKind, delay: Int) -> some View {
    QuickAccessTextButton(label: actionTitle(for: action)) {
      performAction(action)
    }
      .disabled(!isActionEnabled(action))
      .opacity(isActionEnabled(action) ? 1 : 0.6)
      .transition(buttonTransition(delay: delay))
  }

  private func buttonTransition(delay: Int) -> AnyTransition {
    if reduceMotion {
      return .opacity
    }
    let stagger = Double(delay) * QuickAccessAnimations.buttonStaggerDelay
    return .scale(scale: 0.6)
      .combined(with: .opacity)
      .animation(QuickAccessAnimations.buttonReveal.delay(stagger))
  }

  private var cornerButtons: some View {
    ZStack {
      if let action = overlayAction(in: .topTrailing) {
        cornerButton(action, delay: 2)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      }
      if let action = overlayAction(in: .topLeading) {
        cornerButton(action, delay: 3)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      if let action = overlayAction(in: .bottomLeading) {
        cornerButton(action, delay: 4)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      }
      if let action = overlayAction(in: .bottomTrailing) {
        cornerButton(action, delay: 5)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
      }
    }
  }

  private func cornerButton(_ action: QuickAccessActionKind, delay: Int) -> some View {
    QuickAccessIconButton(
      icon: actionIcon(for: action),
      action: { performAction(action) },
      helpText: actionTitle(for: action)
    )
    .transition(cornerButtonTransition(delay: delay))
    .padding(6)
    .disabled(!isActionEnabled(action))
    .opacity(isActionEnabled(action) ? 1 : 0.6)
  }

  private func cornerButtonTransition(delay: Int) -> AnyTransition {
    if reduceMotion {
      return .opacity
    }
    let stagger = Double(delay) * QuickAccessAnimations.buttonStaggerDelay
    return .scale(scale: 0.5)
      .combined(with: .opacity)
      .animation(QuickAccessAnimations.buttonReveal.delay(stagger))
  }

  /// Creates drag preview for the card
  private var dragPreview: some View {
    Image(nsImage: item.thumbnail)
      .resizable()
      .aspectRatio(contentMode: .fill)
      .frame(width: scaledWidth * 0.8, height: scaledHeight * 0.8)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
  }

  private var quickAccessContextMenuEntries: [QuickAccessContextMenuEntry] {
    guard canPerformCardActions else { return [] }

    let contextActions = orderedEnabledActions.filter {
      isActionAvailable($0, on: .contextMenu)
    }
    let orderedContextActions = QuickAccessActionKind.contextMenuOrder(from: contextActions)
    var entries: [QuickAccessContextMenuEntry] = []
    var insertedDestructiveSeparator = false

    for action in orderedContextActions {
      if action.isContextMenuDestructiveGroup && !insertedDestructiveSeparator {
        if !entries.isEmpty {
          entries.append(.separator)
        }
        insertedDestructiveSeparator = true
      }

      entries.append(
        .action(
          title: actionTitle(for: action),
          systemImage: actionIcon(for: action),
          isEnabled: isActionEnabled(action),
          action: { performAction(action) }
        )
      )
    }

    return entries
  }

  // MARK: - Cloud Upload

  /// Whether to show the cloud upload button
  private var shouldShowCloudButton: Bool {
    guard cloudManager.isConfigured else { return false }
    return preferencesManager.isActionEnabled(.uploadToCloud, for: captureType)
  }

  /// Upload the current item to cloud storage
  private func uploadToCloud() {
    guard !isCloudUploading, !alreadyUploadedToCloud else {
      DiagnosticLogger.shared.log(
        .debug,
        .cloud,
        "Quick access cloud upload skipped",
        context: [
          "fileName": item.url.lastPathComponent,
          "isUploading": isCloudUploading ? "true" : "false",
          "alreadyUploaded": alreadyUploadedToCloud ? "true" : "false",
        ]
      )
      return
    }

    isCloudUploading = true
    cloudUploadProgress = 0
    manager.pauseCountdownForActivity(item.id)
    let uploadStartTime = Date()
    let oldCloudKey = item.cloudKey  // Save old key for cleanup
    DiagnosticLogger.shared.log(
      .info,
      .cloud,
      "Quick access cloud upload started",
      context: [
        "fileName": item.url.lastPathComponent,
        "hasOldCloudKey": oldCloudKey == nil ? "false" : "true",
      ]
    )

    // Animate to 80% quickly to show activity
    withAnimation(.easeOut(duration: 0.4)) {
      cloudUploadProgress = 0.8
    }

    Task {
      defer {
        manager.resumeCountdownForActivity(item.id)
      }

      do {
        let fileAccess = SandboxFileAccessManager.shared.beginAccessingURL(item.url)
        defer { fileAccess.stop() }

        // Always upload with a fresh key (new URL avoids CDN cache)
        let result = try await cloudManager.upload(fileURL: item.url)

        // Delete old cloud file in background (no garbage)
        if let oldKey = oldCloudKey {
          Task.detached(priority: .utility) {
            do {
              try await CloudManager.shared.deleteByKey(key: oldKey)
            } catch {
              await DiagnosticLogger.shared.logError(.cloud, error, "Quick access old cloud object cleanup failed")
            }
          }
        }

        // Update item with new cloud URL and key
        manager.setCloudURL(id: item.id, url: result.publicURL, key: result.key)

        // Auto-copy cloud link
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.publicURL.absoluteString, forType: .string)

        // Ensure minimum visual duration (~600ms total)
        let elapsed = Date().timeIntervalSince(uploadStartTime)
        let remainingDelay = max(0, 0.6 - elapsed)

        withAnimation(.easeIn(duration: 0.15)) {
          cloudUploadProgress = 1.0
        }

        if remainingDelay > 0 {
          try? await Task.sleep(nanoseconds: UInt64(remainingDelay * 1_000_000_000))
        }

        isCloudUploading = false
        SoundManager.play("Pop")
        DiagnosticLogger.shared.log(
          .info,
          .cloud,
          "Quick access cloud upload completed",
          context: ["fileName": item.url.lastPathComponent]
        )
      } catch {
        isCloudUploading = false
        cloudUploadProgress = 0
        DiagnosticLogger.shared.logError(
          .cloud,
          error,
          "Quick access cloud upload failed",
          context: ["fileName": item.url.lastPathComponent]
        )
      }
    }
  }
}

// MARK: - Context Menu

private enum QuickAccessContextMenuEntry {
  case action(
    title: String,
    systemImage: String,
    isEnabled: Bool = true,
    action: () -> Void
  )
  case separator
}

private struct QuickAccessContextMenuPresenter: NSViewRepresentable {
  let entries: [QuickAccessContextMenuEntry]

  func makeCoordinator() -> Coordinator {
    Coordinator(entries: entries)
  }

  func makeNSView(context: Context) -> ContextMenuHostView {
    let view = ContextMenuHostView()
    view.coordinator = context.coordinator
    return view
  }

  func updateNSView(_ nsView: ContextMenuHostView, context: Context) {
    context.coordinator.entries = entries
    nsView.coordinator = context.coordinator
  }

  final class Coordinator: NSObject {
    var entries: [QuickAccessContextMenuEntry]

    init(entries: [QuickAccessContextMenuEntry]) {
      self.entries = entries
    }

    var hasMenuItems: Bool {
      entries.contains { entry in
        if case .action = entry { return true }
        return false
      }
    }

    func showMenu(for event: NSEvent, in view: NSView) {
      guard hasMenuItems else { return }
      guard let window = view.window else { return }

      let menu = NSMenu()
      menu.autoenablesItems = false

      for entry in entries {
        switch entry {
        case .action(let title, let systemImage, let isEnabled, let action):
          let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
          item.target = self
          item.isEnabled = isEnabled
          item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
          item.representedObject = QuickAccessContextMenuAction(action)

          menu.addItem(item)
        case .separator:
          menu.addItem(.separator())
        }
      }

      menu.update()

      let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
      let menuLocation = menuTopLeftLocationWithCursorNearTailItem(
        from: screenPoint,
        menu: menu,
        window: window
      )
      menu.popUp(positioning: nil, at: menuLocation, in: nil)
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
      guard let action = sender.representedObject as? QuickAccessContextMenuAction else { return }
      action.perform()
    }

    private func menuTopLeftLocationWithCursorNearTailItem(
      from point: NSPoint,
      menu: NSMenu,
      window: NSWindow
    ) -> NSPoint {
      let targetIndex = menuItemIndexNearCursor(in: menu)
      let targetCenterY = verticalOffsetToItemCenter(at: targetIndex, in: menu)
      let menuSize = menuSize(for: menu)
      let preferredPoint = NSPoint(
        x: point.x - 28,
        y: point.y + targetCenterY
      )
      let screen = window.screen ?? NSScreen.screens.first

      guard let visibleFrame = screen?.visibleFrame else {
        return preferredPoint
      }

      return NSPoint(
        x: min(max(preferredPoint.x, visibleFrame.minX + 8), visibleFrame.maxX - menuSize.width - 8),
        y: min(max(preferredPoint.y, visibleFrame.minY + menuSize.height + 8), visibleFrame.maxY - 8)
      )
    }

    private func menuItemIndexNearCursor(in menu: NSMenu) -> Int {
      let candidateIndex = max(0, menu.items.count - 2)
      if !menu.items[candidateIndex].isSeparatorItem {
        return candidateIndex
      }

      return menu.items.lastIndex { !$0.isSeparatorItem } ?? 0
    }

    private func verticalOffsetToItemCenter(at targetIndex: Int, in menu: NSMenu) -> CGFloat {
      let rowsAbove = menu.items.prefix(targetIndex).reduce(6) { partial, item in
        partial + menuItemHeight(item)
      }
      return rowsAbove + menuItemHeight(menu.items[targetIndex]) / 2
    }

    private func menuItemHeight(_ item: NSMenuItem) -> CGFloat {
      item.isSeparatorItem ? 9 : 22
    }

    private func menuSize(for menu: NSMenu) -> NSSize {
      let measured = menu.size
      guard measured.width > 0, measured.height > 0 else {
        let height = menu.items.reduce(12) { partial, item in
          partial + menuItemHeight(item)
        }
        return NSSize(width: 220, height: height)
      }
      return measured
    }
  }

  final class ContextMenuHostView: NSView {
    weak var coordinator: Coordinator?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      updateEventMonitor()
    }

    deinit {
      if let eventMonitor {
        NSEvent.removeMonitor(eventMonitor)
      }
    }

    private func updateEventMonitor() {
      if let eventMonitor {
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
      }

      guard window != nil else { return }

      eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
        guard let self else { return event }
        return self.handleMouseDown(event)
      }
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
      guard event.window === window else { return event }
      guard isContextClick(event) else { return event }
      guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return event }
      guard coordinator?.hasMenuItems == true else { return event }

      coordinator?.showMenu(for: event, in: self)
      return nil
    }

    private func isContextClick(_ event: NSEvent) -> Bool {
      event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }
  }
}

private final class QuickAccessContextMenuAction: NSObject {
  private let action: () -> Void

  init(_ action: @escaping () -> Void) {
    self.action = action
    super.init()
  }

  func perform() {
    action()
  }
}

// MARK: - QuickAccessItem Drag Support

extension QuickAccessItem {
  /// Creates NSItemProvider for drag & drop to external apps
  func dragItemProvider() -> NSItemProvider {
    let fileURL = self.url
    let provider = NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
    provider.suggestedName = fileURL.lastPathComponent
    return provider
  }
}

// MARK: - Conditional View Extension

extension View {
  /// Conditionally applies a transformation to the view
  @ViewBuilder
  func `if`<Transform: View>(
    _ condition: Bool,
    transform: (Self) -> Transform
  ) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
