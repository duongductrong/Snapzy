//
//  PreferencesQuickAccessPreviewCard.swift
//  Snapzy
//
//  A interactive preview card displaying configurable quick access actions.
//

import SwiftUI
import UniformTypeIdentifiers

struct QuickAccessSettingsPreviewCard: View {
  let scale: CGFloat
  @ObservedObject var actionStore: QuickAccessActionConfigurationStore
  @ObservedObject var swipeActionStore: QuickAccessSwipeActionStore
  let isReordering: Bool

  @State private var hoveredSlot: QuickAccessActionSlot?
  @State private var dropTargetSlot: QuickAccessActionSlot?
  @State private var isRemoveTargeted = false
  @State private var hoveredSwipeDirection: QuickAccessSwipeDirection?
  @State private var dropTargetSwipeDirection: QuickAccessSwipeDirection?

  private var cardWidth: CGFloat {
    QuickAccessLayout.scaledCardWidth(scale)
  }

  private var cardHeight: CGFloat {
    QuickAccessLayout.scaledCardHeight(scale)
  }

  private var stackViewportWidth: CGFloat {
    cardWidth + QuickAccessLayout.containerPadding * 2
  }

  private var stackViewportHeight: CGFloat {
    cardHeight + 96
  }

  private var previewStackSpacing: CGFloat {
    QuickAccessLayout.cardSpacing * 2
  }

  private var popoverSideGap: CGFloat {
    84
  }

  private let swipeTargetDiameter: CGFloat = 24
  private var swipeTargetHitWidth: CGFloat {
    swipeTargetDiameter + 72
  }

  private var swipeTargetOffsetX: CGFloat {
    cardWidth / 2 + 76
  }

  private var previewFrameWidth: CGFloat {
    (swipeTargetOffsetX + swipeTargetHitWidth / 2) * 2
  }

  var body: some View {
    ZStack {
      removalDropArea
        .zIndex(0)

      swipeMotionLayer
        .zIndex(1)

      previewStack
        .zIndex(2)

      swipeTarget(.left)
        .offset(x: -swipeTargetOffsetX)
        .zIndex(3)

      swipeTarget(.right)
        .offset(x: swipeTargetOffsetX)
        .zIndex(3)

      if let hoveredSlot,
         let action = actionStore.action(in: hoveredSlot) {
        QuickAccessPreviewActionPopover(
          action: action,
          slot: hoveredSlot,
          isEnabled: actionStore.isEnabled(action)
        )
        .offset(popoverOffset(for: hoveredSlot))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(4)
        .allowsHitTesting(false)
      }

      if let hoveredSwipeDirection, hoveredSlot == nil {
        QuickAccessPreviewSwipeZonePopover(
          direction: hoveredSwipeDirection,
          action: swipeActionStore.action(for: hoveredSwipeDirection)
        )
        .offset(swipePopoverOffset(for: hoveredSwipeDirection))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(4)
        .allowsHitTesting(false)
      }
    }
    .frame(width: previewFrameWidth, height: stackViewportHeight)
    .animation(.easeOut(duration: 0.12), value: hoveredSlot)
    .animation(.easeOut(duration: 0.12), value: hoveredSwipeDirection)
  }

  private var swipeMotionLayer: some View {
    ZStack {
      swipeArrow(.left)
      swipeArrow(.right)
    }
    .allowsHitTesting(false)
  }

  private func swipeArrow(_ direction: QuickAccessSwipeDirection) -> some View {
    QuickAccessPreviewSwipeArrow(
      direction: direction,
      isHighlighted: hoveredSwipeDirection == direction || dropTargetSwipeDirection == direction,
      cardWidth: cardWidth,
      targetOffsetX: swipeTargetOffsetX,
      targetDiameter: swipeTargetDiameter
    )
  }

  private var previewStack: some View {
    ZStack {
      VStack(spacing: previewStackSpacing) {
        simulatedCardSurface
        cardSurface
        simulatedCardSurface
      }
    }
    .frame(width: stackViewportWidth, height: stackViewportHeight)
    .clipped()
  }

  private var cardSurface: some View {
    ZStack {
      previewThumbnail

      Radius.rect(Radius.card)
        .fill(Color.black.opacity(0.38))

      VStack(spacing: 8) {
        ForEach(QuickAccessActionSlot.centerSlots) { slot in
          centerSlot(slot)
        }
      }
      .padding(.horizontal, 18)

      cornerSlots
    }
    .frame(width: cardWidth, height: cardHeight)
    .clipShape(Radius.rect(Radius.card))
    .overlay(
      Radius.rect(Radius.card)
        .stroke(Color.white.opacity(0.2), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 5)
  }

  private var simulatedCardSurface: some View {
    ZStack {
      previewThumbnail

      Radius.rect(Radius.card)
        .fill(Color.black.opacity(0.1))
    }
    .frame(width: cardWidth, height: cardHeight)
    .clipShape(Radius.rect(Radius.card))
    .overlay(
      Radius.rect(Radius.card)
        .stroke(Color.white.opacity(0.18), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    .opacity(0.72)
    .allowsHitTesting(false)
  }

  private var removalDropArea: some View {
    Radius.rect(Radius.panel)
      .fill(Color.clear)
      .overlay {
        if isRemoveTargeted {
          Radius.rect(Radius.panel)
            .stroke(
              Color(nsColor: .systemRed).opacity(0.65),
              style: StrokeStyle(lineWidth: 1, dash: [6, 5])
            )
        }
      }
      .contentShape(Rectangle())
      .onDrop(
        of: isReordering ? [] : QuickAccessActionDragPayload.typeIdentifiers,
        isTargeted: $isRemoveTargeted
      ) { providers in
        QuickAccessActionDragPayload.load(from: providers) { payload in
          switch payload.source {
          case .preview(let sourceSlot):
            actionStore.clearSlot(sourceSlot)
          case .swipePreview(let direction):
            swipeActionStore.setAction(direction, action: nil)
          case .actionList:
            break
          }
        }
        return true
      }
  }

  private var previewThumbnail: some View {
    QuickAccessSettingsPreviewThumbnail(width: cardWidth, height: cardHeight)
  }

  private var cornerSlots: some View {
    ZStack {
      cornerSlot(.topTrailing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      cornerSlot(.topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      cornerSlot(.bottomLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      cornerSlot(.bottomTrailing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
  }

  private func centerSlot(_ slot: QuickAccessActionSlot) -> some View {
    let slotView = QuickAccessPreviewTextSlot(
      slot: slot,
      action: actionStore.action(in: slot),
      isEnabled: actionStore.action(in: slot).map(actionStore.isEnabled) ?? false,
      isTargeted: dropTargetSlot == slot,
      onHover: { updateHover($0, slot: slot) }
    )
    return draggableSlot(slotView, slot: slot)
      .onDrop(
        of: isReordering ? [] : QuickAccessActionDragPayload.typeIdentifiers,
        isTargeted: dropTargetBinding(for: slot)
      ) { providers in
        assignDroppedAction(from: providers, to: slot)
      }
  }

  private func cornerSlot(_ slot: QuickAccessActionSlot) -> some View {
    let slotView = QuickAccessPreviewIconSlot(
      slot: slot,
      action: actionStore.action(in: slot),
      isEnabled: actionStore.action(in: slot).map(actionStore.isEnabled) ?? false,
      isTargeted: dropTargetSlot == slot,
      onHover: { updateHover($0, slot: slot) }
    )
    return draggableSlot(slotView, slot: slot)
      .padding(6)
      .onDrop(
        of: isReordering ? [] : QuickAccessActionDragPayload.typeIdentifiers,
        isTargeted: dropTargetBinding(for: slot)
      ) { providers in
        assignDroppedAction(from: providers, to: slot)
      }
  }

  private func updateHover(_ isHovering: Bool, slot: QuickAccessActionSlot) {
    hoveredSlot = isHovering ? slot : (hoveredSlot == slot ? nil : hoveredSlot)
  }

  private func popoverOffset(for slot: QuickAccessActionSlot) -> CGSize {
    CGSize(
      width: popoverXOffset(for: slot),
      height: popoverYOffset(for: slot)
    )
  }

  private func popoverXOffset(for slot: QuickAccessActionSlot) -> CGFloat {
    switch slot {
    case .topLeading, .bottomLeading:
      -(cardWidth / 2 + popoverSideGap)
    case .centerTop, .centerBottom, .topTrailing, .bottomTrailing:
      cardWidth / 2 + popoverSideGap
    }
  }

  private func popoverYOffset(for slot: QuickAccessActionSlot) -> CGFloat {
    switch slot {
    case .centerTop:
      -18
    case .centerBottom:
      18
    case .topLeading, .topTrailing:
      -(cardHeight / 2) + 20
    case .bottomLeading, .bottomTrailing:
      cardHeight / 2 - 20
    }
  }

  @ViewBuilder
  private func draggableSlot(_ content: some View, slot: QuickAccessActionSlot) -> some View {
    if let action = actionStore.action(in: slot) {
      content.onDrag {
        QuickAccessActionDragPayload.itemProvider(action: action, source: .preview(slot: slot))
      }
    } else {
      content
    }
  }

  private func assignDroppedAction(from providers: [NSItemProvider], to slot: QuickAccessActionSlot) -> Bool {
    QuickAccessActionDragPayload.load(from: providers) { payload in
      actionStore.assignAction(payload.action, to: slot)
    }
    return true
  }

  private func dropTargetBinding(for slot: QuickAccessActionSlot) -> Binding<Bool> {
    Binding(
      get: { dropTargetSlot == slot },
      set: { isTargeted in
        dropTargetSlot = isTargeted ? slot : (dropTargetSlot == slot ? nil : dropTargetSlot)
      }
    )
  }

  // MARK: - Swipe Zones

  private func swipeTarget(_ direction: QuickAccessSwipeDirection) -> some View {
    let action = swipeActionStore.action(for: direction)
    let swipeView = QuickAccessPreviewSwipeZone(
      direction: direction,
      action: action,
      isTargeted: dropTargetSwipeDirection == direction,
      isHighlighted: hoveredSwipeDirection == direction,
      diameter: swipeTargetDiameter,
      onHover: { isHovering in
        hoveredSwipeDirection = isHovering ? direction :
          (hoveredSwipeDirection == direction ? nil : hoveredSwipeDirection)
      }
    )

    return draggableSwipeTarget(swipeView, direction: direction, action: action)
      .onDrop(
        of: isReordering ? [] : QuickAccessActionDragPayload.typeIdentifiers,
        isTargeted: swipeDropTargetBinding(for: direction)
      ) { providers in
        assignDroppedSwipeAction(from: providers, to: direction)
      }
      .contextMenu {
        Button(L10n.PreferencesQuickAccess.swipeZoneResetToDismiss) {
          swipeActionStore.setAction(direction, action: .dismiss)
        }
        Button(L10n.PreferencesQuickAccess.swipeZoneClearAction) {
          swipeActionStore.setAction(direction, action: nil)
        }
      }
  }

  @ViewBuilder
  private func draggableSwipeTarget(
    _ content: some View,
    direction: QuickAccessSwipeDirection,
    action: QuickAccessActionKind?
  ) -> some View {
    if let action {
      content.onDrag {
        QuickAccessActionDragPayload.itemProvider(action: action, source: .swipePreview(direction: direction))
      }
    } else {
      content
    }
  }

  private func assignDroppedSwipeAction(from providers: [NSItemProvider],
                                        to direction: QuickAccessSwipeDirection) -> Bool {
    QuickAccessActionDragPayload.load(from: providers) { payload in
      swipeActionStore.setAction(direction, action: payload.action)
    }
    return true
  }

  private func swipeDropTargetBinding(for direction: QuickAccessSwipeDirection) -> Binding<Bool> {
    Binding(
      get: { dropTargetSwipeDirection == direction },
      set: { isTargeted in
        dropTargetSwipeDirection = isTargeted ? direction :
          (dropTargetSwipeDirection == direction ? nil : dropTargetSwipeDirection)
      }
    )
  }

  private func swipePopoverOffset(for direction: QuickAccessSwipeDirection) -> CGSize {
    switch direction {
    case .left:
      CGSize(width: -swipeTargetOffsetX, height: -54)
    case .right:
      CGSize(width: swipeTargetOffsetX, height: -54)
    }
  }
}
