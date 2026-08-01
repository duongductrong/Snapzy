//
//  PreferencesMenuBarSettingsView.swift
//  Snapzy
//
//  Menu Bar preferences tab: icon style picker and menu item visibility/order.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  static let menuBarItemReorder = UTType("com.snapzy.menu-bar-reorder") ?? .text
}

struct MenuBarSettingsView: View {
  @ObservedObject private var store = MenuBarCustomizationStore.shared
  @State private var draggedItem: MenuBarItemKind?
  @State private var activeDragID: UUID?
  @State private var mouseUpMonitor: Any?
  @State private var iconRefreshID = UUID()
  @State private var showImportError = false
  @State private var isCustomDropTargeted = false

  private let iconRenderer = MenuBarIconRenderer.shared

  var body: some View {
    Form {
      iconSection

      ForEach(MenuBarItemGroup.allCases, id: \.self) { group in
        itemGroupSection(group)
      }

      Section(L10n.PreferencesMenuBar.appSection) {
        SettingRow(
          icon: MenuBarItemKind.checkForUpdates.systemImage,
          title: MenuBarItemKind.checkForUpdates.settingsTitle,
          description: nil
        ) {
          Toggle("", isOn: Binding(
            get: { !store.isHidden(.checkForUpdates) },
            set: { store.setHidden(.checkForUpdates, hidden: !$0) }
          ))
          .labelsHidden()
        }
      }

      Section {
        HStack {
          Spacer()
          Button(L10n.PreferencesMenuBar.resetButton) {
            store.resetToDefaults()
            iconRefreshID = UUID()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      } footer: {
        Text(L10n.PreferencesMenuBar.itemsDescription)
      }
    }
    .formStyle(.grouped)
    .alert(L10n.PreferencesMenuBar.importFailedTitle, isPresented: $showImportError) {
      Button(L10n.Common.ok, role: .cancel) {}
    } message: {
      Text(L10n.PreferencesMenuBar.importFailedMessage)
    }
  }

  // MARK: - Icon Section

  private var iconSection: some View {
    Section(L10n.PreferencesMenuBar.iconSection) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
          ForEach(MenuBarIconStyle.allCases) { style in
            MenuBarIconTile(
              style: style,
              isSelected: store.iconStyle == style,
              hasCustomIcon: iconRenderer.hasCustomIcon,
              isDropTargeted: style == .custom && isCustomDropTargeted,
              previewImage: previewImage(for: style),
              title: iconTitle(style),
              action: { selectIconStyle(style) }
            )
            .onDrop(
              of: style == .custom ? [.fileURL] : [],
              isTargeted: $isCustomDropTargeted,
              perform: { providers in
                guard style == .custom else { return false }
                return handleCustomIconDrop(providers)
              }
            )
          }
        }
        .id(iconRefreshID)

        Text(L10n.PreferencesMenuBar.iconSectionDescription)
          .font(.caption)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if store.iconStyle == .custom {
          HStack(spacing: 8) {
            Button(L10n.PreferencesMenuBar.importButton) {
              presentImportPanel()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(L10n.PreferencesMenuBar.removeCustomButton) {
              iconRenderer.removeCustomIcon()
              store.setIconStyle(.default)
              iconRefreshID = UUID()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
          .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
      .padding(.vertical, 4)
      .animation(.easeInOut(duration: 0.15), value: store.iconStyle)
    }
  }

  private func previewImage(for style: MenuBarIconStyle) -> NSImage? {
    switch style {
    case .default:
      return iconRenderer.statusImage(for: .default)
    case .custom:
      return iconRenderer.hasCustomIcon ? iconRenderer.statusImage(for: .custom) : nil
    default:
      return nil
    }
  }

  private func iconTitle(_ style: MenuBarIconStyle) -> String {
    switch style {
    case .default: return L10n.PreferencesMenuBar.iconDefault
    case .custom: return L10n.PreferencesMenuBar.iconCustom
    default: return style.rawValue.capitalized
    }
  }

  private func selectIconStyle(_ style: MenuBarIconStyle) {
    // The custom slot is an add action until an icon has been imported.
    if style == .custom && !iconRenderer.hasCustomIcon {
      presentImportPanel()
      return
    }
    store.setIconStyle(style)
  }

  private func presentImportPanel() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.prompt = L10n.PreferencesMenuBar.importButton

    guard panel.runModal() == .OK, let url = panel.url else { return }
    importCustomIcon(from: url)
  }

  private func handleCustomIconDrop(_ providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first else { return false }
    _ = provider.loadObject(ofClass: URL.self) { url, _ in
      guard let url else { return }
      Task { @MainActor in
        if url.pathExtension.lowercased() == "png" {
          self.importCustomIcon(from: url)
        } else {
          self.showImportError = true
        }
      }
    }
    return true
  }

  private func importCustomIcon(from url: URL) {
    if iconRenderer.saveCustomIcon(from: url) {
      store.setIconStyle(.custom)
      iconRefreshID = UUID()
    } else {
      showImportError = true
    }
  }

  // MARK: - Item Group Sections

  private func itemGroupSection(_ group: MenuBarItemGroup) -> some View {
    Section(itemGroupTitle(group)) {
      VStack(spacing: 0) {
        ForEach(Array(store.orderedItems(for: group).enumerated()), id: \.element.rawValue) { index, item in
          MenuBarItemRow(
            item: item,
            index: index,
            group: group,
            store: store,
            isVisible: Binding(
              get: { !store.isHidden(item) },
              set: { store.setHidden(item, hidden: !$0) }
            ),
            draggedItem: $draggedItem,
            activeDragID: $activeDragID
          )

          if index < store.orderedItems(for: group).count - 1 {
            Divider()
          }
        }
      }
      .padding(.vertical, 4)
      .onAppear {
        // Authoritative drag-end signal: leftMouseUp always fires on the main
        // thread at the end of every drag, even when SwiftUI replaces a row's
        // drop delegate mid-reorder.
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
          if self.draggedItem != nil {
            self.draggedItem = nil
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
    }
  }

  private func itemGroupTitle(_ group: MenuBarItemGroup) -> String {
    switch group {
    case .capture: return L10n.PreferencesMenuBar.captureSection
    case .recording: return L10n.PreferencesMenuBar.recordingSection
    case .tools: return L10n.PreferencesMenuBar.toolsSection
    }
  }
}

// MARK: - Icon Tile

/// Menu bar icon choice tile. Label-less for a consistent grid rhythm; the
/// custom slot renders as a dashed "add" action until an icon is imported.
private struct MenuBarIconTile: View {
  let style: MenuBarIconStyle
  let isSelected: Bool
  let hasCustomIcon: Bool
  let isDropTargeted: Bool
  let previewImage: NSImage?
  let title: String
  let action: () -> Void

  @State private var isHovered = false

  private var showsAddAction: Bool {
    style == .custom && !hasCustomIcon
  }

  var body: some View {
    Button(action: action) {
      ZStack {
        tileBackground

        tileContent
      }
      .frame(width: 44, height: 44)
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(
            isSelected ? Color.accentColor : Color.clear,
            lineWidth: 2.5
          )
      )
      .overlay(alignment: .bottomTrailing) {
        if isSelected {
          selectionBadge
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 10))
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(title)
    .accessibilityLabel(title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  @ViewBuilder
  private var tileBackground: some View {
    if showsAddAction {
      // Dashed "add" affordance — reads as an action, not a choice.
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(
          style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        )
        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    } else {
      RoundedRectangle(cornerRadius: 10)
        .fill(fillColor)
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
  }

  private var fillColor: Color {
    if isSelected {
      return Color.accentColor.opacity(0.15)
    }
    if isHovered {
      return Color.primary.opacity(0.1)
    }
    return Color.primary.opacity(0.05)
  }

  @ViewBuilder
  private var tileContent: some View {
    if showsAddAction {
      Image(systemName: "plus")
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
    } else if let symbolName = style.symbolName {
      Image(systemName: symbolName)
        .font(.system(size: 19))
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
    } else if let previewImage {
      Image(nsImage: previewImage)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: 20, height: 20)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
    }
  }

  private var selectionBadge: some View {
    Image(systemName: "checkmark.circle.fill")
      .font(.system(size: 14))
      .foregroundStyle(.white, Color.accentColor)
      .background(Circle().fill(Color.accentColor))
      .offset(x: 5, y: 5)
  }
}

// MARK: - Item Row

private struct MenuBarItemRow: View {
  let item: MenuBarItemKind
  let index: Int
  let group: MenuBarItemGroup
  let store: MenuBarCustomizationStore
  @Binding var isVisible: Bool
  @Binding var draggedItem: MenuBarItemKind?
  @Binding var activeDragID: UUID?
  @State private var isHandleHovered = false

  var body: some View {
    HStack(spacing: 10) {
      // Drag handle — reorder within the group only
      Image(systemName: "line.3.horizontal")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(isHandleHovered ? .secondary : .quaternary)
        .frame(width: 14)
        .contentShape(Rectangle().inset(by: -4))
        .onHover { isHandleHovered = $0 }
        .onDrag {
          let dragID = UUID()
          self.activeDragID = dragID
          self.draggedItem = item

          let provider = MenuBarDragTrackingItemProvider()
          if let data = item.rawValue.data(using: .utf8) {
            provider.registerDataRepresentation(
              forTypeIdentifier: UTType.menuBarItemReorder.identifier,
              visibility: .all
            ) { completion in
              completion(data, nil)
              return nil
            }
          }

          provider.onDeinit = { [dragID] in
            Task { @MainActor in
              if self.activeDragID == dragID {
                self.activeDragID = nil
                self.draggedItem = nil
              }
            }
          }
          return provider
        } preview: {
          // No visual ghost — handle-drag is a reorder-only gesture.
          Color.clear.frame(width: 1, height: 1)
        }

      Image(systemName: item.systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 18)

      Text(item.settingsTitle)
        .lineLimit(1)

      Spacer()

      Toggle("", isOn: $isVisible)
        .labelsHidden()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .opacity(isVisible ? 1.0 : 0.6)
    .background(draggedItem == item ? Color(NSColor.selectedControlColor).opacity(0.15) : Color.clear)
    .onDrop(of: [UTType.menuBarItemReorder], delegate: MenuBarReorderDropDelegate(
      targetItem: item,
      targetIndex: index,
      group: group,
      store: store,
      draggedItem: $draggedItem
    ))
  }
}

private struct MenuBarReorderDropDelegate: DropDelegate {
  let targetItem: MenuBarItemKind
  let targetIndex: Int
  let group: MenuBarItemGroup
  let store: MenuBarCustomizationStore
  @Binding var draggedItem: MenuBarItemKind?

  func validateDrop(info: DropInfo) -> Bool {
    draggedItem != nil
  }

  func dropEntered(info: DropInfo) {
    guard let sourceItem = draggedItem,
          sourceItem != targetItem else { return }

    let groupItems = store.orderedItems(for: group)
    guard let sourceIndex = groupItems.firstIndex(of: sourceItem) else { return }

    if sourceIndex != targetIndex {
      withAnimation(.default) {
        store.moveItem(
          from: IndexSet(integer: sourceIndex),
          to: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex,
          in: group
        )
      }
    }
  }

  func performDrop(info: DropInfo) -> Bool {
    // Belt-and-suspenders: also reset here for cases where the monitor fires late.
    Task { @MainActor in
      draggedItem = nil
    }
    return true
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }
}

private final class MenuBarDragTrackingItemProvider: NSItemProvider {
  var onDeinit: (() -> Void)?
  deinit {
    onDeinit?()
  }
}

#Preview {
  MenuBarSettingsView()
    .frame(width: 600, height: 500)
}
