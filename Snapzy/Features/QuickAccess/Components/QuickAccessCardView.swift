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
  @ObservedObject private var actionShortcuts = QuickAccessActionShortcutStore.shared
  @ObservedObject private var trackpadSwipeModeStore = QuickAccessTrackpadSwipeModeStore.shared
  @ObservedObject private var swipeActionStore = QuickAccessSwipeActionStore.shared
  @ObservedObject private var cloudManager = CloudManager.shared
  @State private var isHovering = false
  @State private var isDragging = false
  @State private var isSwiping = false
  @State private var isDismissing = false
  @State private var isCollapsing = false
  /// 0...1 progress of a live two-finger move down toward the edge (#591).
  @State private var collapseSwipeProgress: CGFloat = 0
  @State private var swipeOffset: CGFloat = 0
  @State private var isCloudUploading = false
  @State private var cloudUploadProgress: Double = 0
  @State private var cardAnchor = QuickAccessCardAnchor()
  @State private var optimizeButtonAnchor = QuickAccessCardAnchor()
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  private let cornerRadius = Radius.card

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
      if isHovering && !isSwiping && collapseSwipeProgress == 0 && canPerformCardActions && hasVisibleOverlayActions {
        hoverOverlay
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
      }

      // Corner buttons (only visible on hover, hidden during cloud upload and swipe).
      if isHovering && !isSwiping && collapseSwipeProgress == 0 && canPerformCardActions && !cornerOverlayActions.isEmpty {
        cornerButtons
      }
    }
    .frame(width: scaledWidth, height: scaledHeight)
    .quickAccessCardSurface(cornerRadius: cornerRadius)
    .scaleEffect(
      reduceMotion ? 1 : QuickAccessCollapseSwipePolicy.cardScale(progress: collapseSwipeProgress),
      anchor: manager.position.isLeftSide ? .leading : .trailing
    )
    .opacity(cardOpacity)
    .offset(
      x: reduceMotion ? 0 : swipeOffset + collapseSwipeDrift,
      y: reduceMotion ? 0 : QuickAccessCollapseSwipePolicy.cardDrop(progress: collapseSwipeProgress)
    )
    .rotationEffect(.degrees(reduceMotion || isCollapseMotion ? 0 : Double(swipeOffset) * 0.03))
    .onHover { hovering in
      withAnimation(QuickAccessAnimations.hoverOverlay) {
        isHovering = hovering
      }
      onHover?(hovering)

      // Arms/disarms the card action shortcuts for this card.
      manager.setHoveredItem(id: item.id, hovering: hovering)

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
    .background(
      QuickAccessCardAnchorView(anchor: cardAnchor)
        .frame(width: scaledWidth, height: scaledHeight)
        .allowsHitTesting(false)
    )
    .overlay(dragInteractionBridge.frame(width: scaledWidth, height: scaledHeight))
    .onDisappear {
      isDragging = false
      isHovering = false
      // A card can be pulled out from under the pointer (editor opened, countdown
      // fired) without SwiftUI reporting hover-exit.
      manager.setHoveredItem(id: item.id, hovering: false)
    }
    .onAppear {
      isDismissing = false
      isCollapsing = false
      collapseSwipeProgress = 0
      swipeOffset = 0
      isSwiping = false
      isDragging = false
      isHovering = false
    }
    .onReceive(manager.$items) { updatedItems in
      guard let currentItem = updatedItems.first(where: { $0.id == item.id }) else { return }
      if !currentItem.isWindowOpen && swipeOffset != 0 && !isSwiping && !isDismissing && !isCollapsing {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
          swipeOffset = 0
        }
      }
    }
    .onReceive(manager.cardShortcutTrigger) { trigger in
      guard trigger.itemID == item.id, canPerformCardActions else { return }
      performAction(trigger.action)
    }
    .animation(QuickAccessAnimations.hoverOverlay, value: isHovering)
  }

  // MARK: - Computed Properties

  private var cardOpacity: Double {
    if isDragging { return 0.6 }
    if isDismissing { return 0 }

    if reduceMotion { return 1.0 }
    // Collapsing slides the card into the edge intact; it does not fade like a dismiss.
    if isCollapseMotion { return 1.0 }
    return 1.0 - Double(abs(swipeOffset)) / 200.0
  }

  /// True while the card is (or is being swiped toward) collapsing into its edge.
  private var isCollapseMotion: Bool {
    if isCollapsing { return true }
    guard swipeOffset != 0 else { return false }
    if manager.swipeTowardEdgeCollapses && swipeOffset * dismissDirection > 0 { return true }
    return swipeActionStore.action(for: swipeOffset > 0 ? .right : .left) == .collapseToEdge
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
        let finalTranslation = swipeResolver.liveTranslation(translation)

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
        handleSwipeEnded(translation: translation, velocity: velocity)
      },
      swipeSensitivity: CGFloat(manager.swipeSensitivity),
      dragOnly: false,
      reservedScrollAxis: nil,
      onVerticalSwipe: collapseSwipeHandler
    )
  }

  private var swipeResolver: QuickAccessSwipeResolver {
    QuickAccessSwipeResolver(
      leftAction: swipeActionStore.action(for: .left),
      rightAction: swipeActionStore.action(for: .right),
      hideCardWhenWindowOpen: manager.hideCardWhenWindowOpen,
      collapsesTowardEdge: manager.swipeTowardEdgeCollapses,
      edgeDirection: dismissDirection
    )
  }

  // MARK: - Two-finger move down to collapse (#591)

  private var collapseSwipeHandler: ((QuickAccessVerticalSwipeTracker.Update) -> Void)? {
    guard actionConfiguration.isEnabled(.collapseToEdge), canPerformCardActions else { return nil }
    return { update in handleCollapseSwipe(update) }
  }

  private var collapseSwipeDrift: CGFloat {
    QuickAccessCollapseSwipePolicy.cardDrift(progress: collapseSwipeProgress, edgeDirection: dismissDirection)
  }

  /// The card follows the fingers down, shrinking toward its edge; releasing
  /// past the threshold (or flicking) tucks it in, otherwise it springs back.
  private func handleCollapseSwipe(_ update: QuickAccessVerticalSwipeTracker.Update) {
    switch update {
    case let .changed(distance):
      guard !reduceMotion else { return }
      // Live tracking: no animation, the card is glued to the fingers.
      collapseSwipeProgress = QuickAccessCollapseSwipePolicy.collapseProgress(distance: distance)
    case let .ended(distance, velocity):
      if QuickAccessCollapseSwipePolicy.shouldCollapse(distance: distance, velocity: velocity) {
        collapseToEdge()
      } else {
        withAnimation(QuickAccessEdgePeekView.motion) {
          collapseSwipeProgress = 0
        }
      }
    case .cancelled:
      withAnimation(QuickAccessEdgePeekView.motion) {
        collapseSwipeProgress = 0
      }
    }
  }

  private func handleSwipeEnded(translation: CGFloat, velocity: CGFloat) {
    let outcome = swipeResolver.resolveEnd(
      translation: translation,
      velocity: velocity,
      isActionEnabled: isActionEnabled
    )

    if outcome == .collapse {
      collapseToEdge()
      return
    }

    guard case let .perform(configuredAction, willHideCard) = outcome else {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        swipeOffset = 0
      }
      return
    }

    if willHideCard {
      let offScreenOffset: CGFloat = translation > 0 ? scaledWidth + 200 : -(scaledWidth + 200)
      withAnimation(.easeOut(duration: 0.2)) {
        swipeOffset = offScreenOffset
        if configuredAction == .dismiss || configuredAction == .delete {
          isDismissing = true
        }
      }

      performAction(configuredAction)
    } else {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        swipeOffset = 0
      }
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
    case .optimize:
      return L10n.PreferencesQuickAccess.optimizeAction
    case .collapseToEdge:
      return L10n.QuickAccess.collapseToEdge
    }
  }

  /// Tooltip text with the card action shortcut appended, so the binding is
  /// discoverable without opening Settings.
  private func actionHelpText(for action: QuickAccessActionKind) -> String {
    let title = actionTitle(for: action)
    guard actionShortcuts.isEnabled,
          actionShortcuts.isEnabled(for: action),
          let shortcut = actionShortcuts.shortcut(for: action),
          !QuickAccessActionShortcutStore.containsFunctionModifier(shortcut) else {
      return title
    }
    return "\(title)  \(shortcut.displayString)"
  }

  private func actionIcon(for action: QuickAccessActionKind) -> String {
    switch action {
    case .saveOrOpen:
      return isTempFile ? "square.and.arrow.down" : "folder"
    case .uploadToCloud:
      return cloudActionIcon
    case .pinToScreen:
      return item.isPinned ? "pin.fill" : "pin"
    case .collapseToEdge:
      return manager.position.isLeftSide ? "arrow.left.to.line" : "arrow.right.to.line"
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
    case .optimize:
      return QuickAccessOptimizeStore.shared.canOptimize(item)
    case .collapseToEdge:
      return true
    }
  }

  private func isActionEnabled(_ action: QuickAccessActionKind) -> Bool {
    switch action {
    case .pinToScreen:
      return !item.isVideo
    case .uploadToCloud:
      return shouldShowCloudButton && !alreadyUploadedToCloud && !isCloudUploading
    case .optimize:
      // An open editor would write its own pixels back over the optimized file.
      let isEditorOpen = item.isWindowOpen && !item.isPinned
      return QuickAccessOptimizeStore.shared.canOptimize(item) && !isEditorOpen
    case .copy, .saveOrOpen, .dismiss, .delete, .edit, .collapseToEdge:
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
    case .optimize:
      presentOptimizeMenu()
    case .collapseToEdge:
      collapseToEdge()
    }
  }

  private func presentOptimizeMenu() {
    QuickAccessOptimizePanelController.shared.present(
      for: item,
      buttonFrame: optimizeButtonAnchor.screenFrame,
      cardFrame: cardAnchor.screenFrame
    )
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

  /// Slide the card into its screen edge, where it continues as a peek strip.
  private func collapseToEdge() {
    isCollapsing = true
    if !reduceMotion {
      // Same spring as the peek, so a swipe flows straight into the edge.
      withAnimation(QuickAccessEdgePeekView.motion) {
        swipeOffset = dismissDirection * (scaledWidth + 200)
      }
    }
    manager.collapseItem(id: item.id)
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
            Capsule()
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
      .help(actionHelpText(for: action))
      .background(optimizeAnchor(for: action))
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
      helpText: actionHelpText(for: action)
    )
    .background(optimizeAnchor(for: action))
    .transition(cornerButtonTransition(delay: delay))
    .padding(6)
    .disabled(!isActionEnabled(action))
    .opacity(isActionEnabled(action) ? 1 : 0.6)
  }

  /// Lets the Optimize menu open over the button that triggered it.
  @ViewBuilder
  private func optimizeAnchor(for action: QuickAccessActionKind) -> some View {
    if action == .optimize {
      QuickAccessCardAnchorView(anchor: optimizeButtonAnchor)
    }
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
    let orderedContextActions = contextActions
    var entries: [QuickAccessContextMenuEntry] = []
    var insertedDestructiveSeparator = false

    for action in orderedContextActions {
      if action.isContextMenuDestructiveGroup && !insertedDestructiveSeparator {
        if !entries.isEmpty {
          entries.append(.separator)
        }
        insertedDestructiveSeparator = true
      }

      if action == .optimize {
        entries.append(optimizeContextMenuEntry)
        continue
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

  /// Optimize as a submenu so the levels stay reachable from the context menu even
  /// when the action has no slot on the card. Levels are read when the menu opens.
  private var optimizeContextMenuEntry: QuickAccessContextMenuEntry {
    let item = item
    return .submenu(
      title: actionTitle(for: .optimize),
      systemImage: actionIcon(for: .optimize),
      isEnabled: isActionEnabled(.optimize),
      makeEntries: {
        let store = QuickAccessOptimizeStore.shared
        guard let plan = store.plan(for: item) else { return [] }
        var entries: [QuickAccessContextMenuEntry] = plan.levels.map { level in
          .option(
            title: QuickAccessOptimizeMenuFormatting.title(for: level),
            detail: level.dimensionsLabel,
            isChecked: level.fraction == plan.currentFraction,
            action: { store.applyReportingFailure(.level(level), to: item.id) }
          )
        }
        let presets = QuickAccessOptimizePresetStore.shared.presets
        if !presets.isEmpty {
          entries.append(.separator)
          entries += presets.map { preset in
            .option(
              title: preset.name,
              detail: preset.settings.summary(originalExtension: plan.fileExtension),
              isChecked: false,
              action: { store.applyReportingFailure(.custom(preset.settings), to: item.id) }
            )
          }
        }
        entries.append(.separator)
        entries.append(.option(
          title: L10n.QuickAccess.optimizeCustom,
          detail: nil,
          isChecked: false,
          action: { [cardAnchor] in
            QuickAccessOptimizePanelController.shared.presentCustom(for: item, anchor: cardAnchor.screenFrame)
          }
        ))
        return entries
      }
    )
  }

  // MARK: - Cloud Upload

  /// Whether to show the cloud upload button
  private var shouldShowCloudButton: Bool {
    cloudManager.isConfigured
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
              DiagnosticLogger.shared.logError(.cloud, error, "Quick access old cloud object cleanup failed")
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
        QuickAccessSound.copy.play(reduceMotion: reduceMotion)
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
  case submenu(
    title: String,
    systemImage: String,
    isEnabled: Bool,
    makeEntries: () -> [QuickAccessContextMenuEntry]
  )
  case option(
    title: String,
    detail: String?,
    isChecked: Bool,
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
        switch entry {
        case .action, .submenu, .option: return true
        case .separator: return false
        }
      }
    }

    func showMenu(for event: NSEvent, in view: NSView) {
      guard hasMenuItems else { return }
      guard let window = view.window else { return }

      let menu = NSMenu()
      menu.autoenablesItems = false

      populate(menu, with: entries)
      menu.update()

      let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
      let menuLocation = menuTopLeftLocationWithCursorNearTailItem(
        from: screenPoint,
        menu: menu,
        window: window
      )
      menu.popUp(positioning: nil, at: menuLocation, in: nil)
    }

    private func populate(_ menu: NSMenu, with entries: [QuickAccessContextMenuEntry]) {
      for entry in entries {
        switch entry {
        case .action(let title, let systemImage, let isEnabled, let action):
          let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
          item.target = self
          item.isEnabled = isEnabled
          item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
          item.representedObject = QuickAccessContextMenuAction(action)

          menu.addItem(item)
        case .submenu(let title, let systemImage, let isEnabled, let makeEntries):
          let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
          item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
          let children = isEnabled ? makeEntries() : []
          item.isEnabled = isEnabled && !children.isEmpty
          if item.isEnabled {
            let submenu = NSMenu(title: title)
            submenu.autoenablesItems = false
            populate(submenu, with: children)
            item.submenu = submenu
          }
          menu.addItem(item)
        case .option(let title, let detail, let isChecked, let action):
          let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
          item.target = self
          item.isEnabled = true
          item.state = isChecked ? .on : .off
          item.representedObject = QuickAccessContextMenuAction(action)
          if let detail {
            item.attributedTitle = Self.optionTitle(title, detail: detail)
          }
          menu.addItem(item)
        case .separator:
          menu.addItem(.separator())
        }
      }
    }

    private static func optionTitle(_ title: String, detail: String) -> NSAttributedString {
      let font = NSFont.menuFont(ofSize: 0)
      let result = NSMutableAttributedString(string: title, attributes: [.font: font])
      result.append(NSAttributedString(
        string: "   \(detail)",
        attributes: [
          .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize - 1, weight: .regular),
          .foregroundColor: NSColor.secondaryLabelColor,
        ]
      ))
      return result
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
