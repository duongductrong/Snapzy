//
//  VerticalTabBar.swift
//  Snapzy
//
//  Reusable vertical tab bar component for sidebar navigation
//

import SwiftUI

// MARK: - Vertical Tab Item

struct VerticalTabItem: View {
  let icon: String
  let title: String
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(isSelected ? .white : .primary)
        .frame(width: 36, height: 36)
        .background(
          Group {
            if isSelected {
              RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor)
            } else if isHovered {
              RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
            } else {
              Color.clear
            }
          }
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(title)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.1)) {
        isHovered = hovering
      }
    }
  }
}

// MARK: - Vertical Tab Bar

struct VerticalTabBar<Tab: Hashable>: View {
  @Binding var selection: Tab
  let tabs: [Tab]
  let label: (Tab) -> (icon: String, title: String)

  var body: some View {
    VStack(spacing: 4) {
      ForEach(tabs, id: \.self) { tab in
        let info = label(tab)
        VerticalTabItem(
          icon: info.icon,
          title: info.title,
          isSelected: selection == tab
        ) {
          withAnimation(.easeInOut(duration: 0.15)) {
            selection = tab
          }
        }
      }

      Spacer()
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 6)
    .frame(width: 48)
  }
}

// MARK: - Preview

@available(macOS 14.0, *)
#Preview {
  @Previewable @State var selectedTab = "background"

  HStack(spacing: 0) {
    Color.gray.opacity(0.2)
      .frame(width: 256)

    Divider()

    VerticalTabBar(
      selection: $selectedTab,
      tabs: ["background", "zoom"]
    ) { tab in
      switch tab {
      case "background":
        return (icon: "rectangle.on.rectangle", title: L10n.VideoEditor.backgroundTab)
      case "zoom":
        return (icon: "plus.magnifyingglass", title: L10n.VideoEditor.zoomTab)
      default:
        return (icon: "questionmark", title: L10n.VideoEditor.unknownTab)
      }
    }
  }
  .frame(width: 320, height: 400)
}
