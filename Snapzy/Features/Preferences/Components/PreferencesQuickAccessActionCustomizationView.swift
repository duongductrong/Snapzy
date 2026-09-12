//
//  PreferencesQuickAccessActionCustomizationView.swift
//  Snapzy
//
//  Quick Access card preview and action ordering controls.
//

import SwiftUI
import UniformTypeIdentifiers

struct QuickAccessActionCustomizationView: View {
  @ObservedObject var manager: QuickAccessManager
  @ObservedObject private var actionStore = QuickAccessActionConfigurationStore.shared
  @ObservedObject private var swipeActionStore = QuickAccessSwipeActionStore.shared
  @State private var draggedAction: QuickAccessActionKind? = nil
  @State private var activeDragID: UUID? = nil
  @State private var mouseUpMonitor: Any?

  var body: some View {
    Section(L10n.PreferencesQuickAccess.previewSection) {
      HStack {
        Spacer()
        QuickAccessSettingsPreviewCard(
          scale: CGFloat(manager.overlayScale),
          actionStore: actionStore,
          swipeActionStore: swipeActionStore,
          isReordering: draggedAction != nil
        )
        Spacer()
      }
      .padding(.vertical, 10)
    }

    Section(L10n.PreferencesQuickAccess.quickActionsSection) {
      VStack(alignment: .leading, spacing: 10) {
        Text(L10n.PreferencesQuickAccess.quickActionsDescription)
          .font(.caption)
          .foregroundColor(.secondary)
          .padding(.horizontal, 10)

        VStack(spacing: 0) {
          ForEach(Array(actionStore.actionOrder.enumerated()), id: \.element.id) { index, action in
            QuickAccessActionConfigurationRow(
              action: action,
              assignedSlot: actionStore.assignedSlot(for: action),
              index: index,
              actionStore: actionStore,
              isEnabled: Binding(
                get: { actionStore.isEnabled(action) },
                set: { actionStore.setEnabled(action, enabled: $0) }
              ),
              draggedAction: $draggedAction,
              activeDragID: $activeDragID
            )

            if index < actionStore.actionOrder.count - 1 {
              Divider()
            }
          }
        }
        .onAppear {
          // Authoritative drag-end signal: leftMouseUp always fires on the main thread
          // at the end of every drag, even when performDrop is skipped because SwiftUI
          // replaced a List row's drop delegate mid-reorder.
          mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            if self.draggedAction != nil {
              self.draggedAction = nil
            }
            if self.activeDragID != nil {
              self.activeDragID = nil
            }
            return event
          }
        }
        .onDisappear {
          if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
          }
        }

        HStack {
          Spacer()
          Button(L10n.PreferencesQuickAccess.resetActions) {
            actionStore.resetToDefaults()
            swipeActionStore.resetToDefaults()
          }
        }
      }
      .padding(.vertical, 4)
    }
  }
}

private struct QuickAccessActionConfigurationRow: View {
  let action: QuickAccessActionKind
  let assignedSlot: QuickAccessActionSlot?
  let index: Int
  let actionStore: QuickAccessActionConfigurationStore
  @Binding var isEnabled: Bool
  @Binding var draggedAction: QuickAccessActionKind?
  @Binding var activeDragID: UUID?
  @State private var isHandleHovered = false

  var body: some View {
    HStack(spacing: 6) {
      // Drag handle — reorder only
      Image(systemName: "line.3.horizontal")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(isHandleHovered ? .secondary : .quaternary)
        .frame(width: 14)
        .contentShape(Rectangle().inset(by: -4))
        .onHover { isHandleHovered = $0 }
        .onDrag {
          let dragID = UUID()
          self.activeDragID = dragID
          self.draggedAction = action
          
          let provider = DragTrackingItemProvider()
          if let data = action.rawValue.data(using: .utf8) {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.quickAccessReorder.identifier, visibility: .all) { completion in
              completion(data, nil)
              return nil
            }
          }
          
          provider.onDeinit = { [dragID] in
            Task { @MainActor in
              if self.activeDragID == dragID {
                self.activeDragID = nil
                self.draggedAction = nil
              }
            }
          }
          return provider
        } preview: {
          // No visual ghost — handle-drag is a reorder-only gesture.
          // Returning an empty view keeps the system from spawning a default snapshot.
          Color.clear.frame(width: 1, height: 1)
        }

      // Row body — slot assignment drag
      HStack(spacing: 10) {
        actionLabel

        Spacer()

        placementBadge

        Toggle("", isOn: $isEnabled)
          .labelsHidden()
      }
      .contentShape(Rectangle())
      .onDrag {
        self.draggedAction = nil
        return QuickAccessActionDragPayload.itemProvider(action: action, source: .actionList)
      } preview: {
        QuickAccessActionDragPreview(action: action)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(draggedAction == action ? Color(NSColor.selectedControlColor).opacity(0.15) : Color.clear)
    .opacity(draggedAction == action ? 0.35 : 1.0)
    .onDrop(of: [UTType.quickAccessReorder], delegate: ReorderDropDelegate(
      targetAction: action,
      targetIndex: index,
      actionStore: actionStore,
      draggedAction: $draggedAction
    ))
  }

  private var actionLabel: some View {
    HStack(spacing: 10) {
      Image(systemName: action.systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 18)

      Text(action.settingsTitle)
        .lineLimit(1)
    }
  }

  private var placementBadge: some View {
    Text(assignedSlot?.settingsTitle ?? L10n.PreferencesQuickAccess.notOnCard)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(.quaternary, in: Capsule())
  }
}

private struct QuickAccessActionDragPreview: View {
  let action: QuickAccessActionKind

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: action.systemImage)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 16)

      Text(action.settingsTitle)
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(.regularMaterial, in: Radius.rect(Radius.card))
    .overlay(
      Radius.rect(Radius.card)
        .stroke(.quaternary, lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 4)
    .fixedSize(horizontal: true, vertical: false)
  }
}

private struct ReorderDropDelegate: DropDelegate {
  private static let reorderMarker = "com.snapzy.quick-access-reorder"

  let targetAction: QuickAccessActionKind
  let targetIndex: Int
  let actionStore: QuickAccessActionConfigurationStore
  @Binding var draggedAction: QuickAccessActionKind?

  func validateDrop(info: DropInfo) -> Bool {
    draggedAction != nil
  }

  func dropEntered(info: DropInfo) {
    guard let sourceAction = draggedAction,
          sourceAction != targetAction else { return }

    guard let sourceIndex = actionStore.actionOrder.firstIndex(of: sourceAction) else { return }

    if sourceIndex != targetIndex {
      withAnimation(.default) {
        actionStore.moveAction(
          from: IndexSet(integer: sourceIndex),
          to: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        )
      }
    }
  }

  func performDrop(info: DropInfo) -> Bool {
    // Belt-and-suspenders: also reset here for cases where the monitor fires late.
    Task { @MainActor in
      draggedAction = nil
    }
    return true
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }
}

private final class DragTrackingItemProvider: NSItemProvider {
  var onDeinit: (() -> Void)?
  deinit {
    onDeinit?()
  }
}
