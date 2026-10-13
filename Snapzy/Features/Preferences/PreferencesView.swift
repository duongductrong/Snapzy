//
//  PreferencesView.swift
//  Snapzy
//
//  Root preferences window with modern macOS NavigationSplitView sidebar interface.
//

import SwiftUI

struct PreferencesView: View {
  @ObservedObject private var themeManager = ThemeManager.shared
  @ObservedObject private var navigationState = PreferencesNavigationState.shared

  /// Fixed sidebar width prevents divider dragging and accidental collapsing.
  private static let fixedSidebarWidth: CGFloat = 220

  var body: some View {
    NavigationSplitView(columnVisibility: columnVisibilityBinding) {
      sidebar
    } detail: {
      detail
    }
    .navigationSplitViewStyle(.balanced)
    .preferredColorScheme(themeManager.systemAppearance)
    .frame(minWidth: PreferencesWindowController.minimumContentSize.width,
           minHeight: PreferencesWindowController.minimumContentSize.height)
    .background(NonCollapsibleSplitViewModifier())
  }

  /// Lock column visibility to .all so the sidebar cannot be collapsed.
  private var columnVisibilityBinding: Binding<NavigationSplitViewVisibility> {
    Binding(
      get: { .all },
      set: { _ in }
    )
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    List(selection: sidebarSelection) {
      ForEach(Array(PreferencesTab.groups.enumerated()), id: \.offset) { _, group in
        Section {
          ForEach(group) { tab in
            PreferencesSidebarRow(tab: tab)
              .tag(tab)
          }
        }
      }
    }
    .listStyle(.sidebar)
    .modifier(SidebarToggleRemovalModifier())
    .safeAreaInset(edge: .bottom) {
      PreferencesSidebarUpdateBadge()
    }
    .navigationSplitViewColumnWidth(
      min: Self.fixedSidebarWidth,
      ideal: Self.fixedSidebarWidth,
      max: Self.fixedSidebarWidth
    )
    .accessibilityLabel(L10n.PreferencesGeneral.sidebarAccessibilityLabel)
  }

  private var sidebarSelection: Binding<PreferencesTab?> {
    Binding(
      get: { navigationState.selectedTab },
      set: { tab in
        guard let tab else { return }
        navigationState.select(tab)
      }
    )
  }

  // MARK: - Detail

  private var detail: some View {
    Group {
      switch navigationState.selectedTab {
      case .general:
        LazyView(GeneralSettingsView())
      case .menuBar:
        LazyView(MenuBarSettingsView())
      case .capture:
        LazyView(CaptureSettingsView())
      case .annotate:
        LazyView(AnnotateSettingsView())
      case .quickAccess:
        LazyView(QuickAccessSettingsView())
      case .history:
        LazyView(HistorySettingsView())
      case .shortcuts:
        LazyView(ShortcutsSettingsView())
      case .permissions:
        LazyView(PermissionsSettingsView())
      case .cloud:
        LazyView(CloudSettingsView())
      case .advanced:
        LazyView(AdvancedSettingsView())
      case .about:
        LazyView(AboutSettingsView())
      }
    }
    .id(navigationState.selectedTab)
    .transition(.opacity)
    .animation(.easeOut(duration: 0.12), value: navigationState.selectedTab)
    .navigationTitle(navigationState.selectedTab.title)
    .navigationSplitViewColumnWidth(min: 480, ideal: 580)
    .toolbar {
      ToolbarItemGroup(placement: .navigation) {
        Button {
          navigationState.goBack()
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(!navigationState.canGoBack)
        .help(L10n.PreferencesGeneral.navigationBack)
        .keyboardShortcut("[", modifiers: .command)

        Button {
          navigationState.goForward()
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled(!navigationState.canGoForward)
        .help(L10n.PreferencesGeneral.navigationForward)
        .keyboardShortcut("]", modifiers: .command)
      }
    }
  }
}

// MARK: - Sidebar Row

/// Clean, unboxed sidebar row using native SF Symbols (matching Ruru and macOS System Settings style).
private struct PreferencesSidebarRow: View {
  let tab: PreferencesTab

  var body: some View {
    Label {
      Text(tab.title)
    } icon: {
      Image(systemName: tab.symbol)
        .font(.system(size: 13, weight: .regular))
        .frame(width: 18, alignment: .center)
    }
  }
}

// MARK: - Sidebar Toggle Modifier

private struct SidebarToggleRemovalModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 14.0, *) {
      content.toolbar(removing: .sidebarToggle)
    } else {
      content
    }
  }
}

// MARK: - Non-Collapsible Split View Modifier

/// Enforces non-collapsible behavior on the underlying AppKit `NSSplitViewItem`
/// for the sidebar column, preventing collapsing via shortcuts (⌘⌥S),
/// divider dragging, or divider double-clicking.
private struct NonCollapsibleSplitViewModifier: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      configure(from: view)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      configure(from: nsView)
    }
  }

  private func configure(from view: NSView) {
    guard let window = view.window else { return }
    guard let splitView = window.contentView?.firstDescendant(ofType: NSSplitView.self),
          let splitViewController = splitView.delegate as? NSSplitViewController,
          let sidebarItem = splitViewController.splitViewItems.first else {
      return
    }

    if sidebarItem.canCollapse {
      sidebarItem.canCollapse = false
    }
    if sidebarItem.isCollapsed {
      sidebarItem.isCollapsed = false
    }
  }
}

#Preview {
  PreferencesView()
}
