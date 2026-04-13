//
//  AnnotateQuickPropertiesBar.swift
//  Snapzy
//
//  Contextual quick properties bar for common annotation styling.
//

import SwiftUI

struct AnnotateQuickPropertiesBar: View {
  @ObservedObject var state: AnnotateState

  private let strokeColors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]
  private let fillColors: [Color] = [.clear, .red, .orange, .yellow, .green, .blue, .purple, .white, .black]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Spacing.md) {
        contextChip

        if state.quickPropertiesSupportsStrokeColor {
          QuickPropertiesGroup(title: colorTitle) {
            QuickPropertiesColorPalette(
              selectedColor: state.quickStrokeColorBinding,
              colors: strokeColors
            )
          }
        }

        if state.quickPropertiesSupportsFill {
          QuickPropertiesDivider()
          QuickPropertiesGroup(title: L10n.Common.fill) {
            QuickPropertiesColorPalette(
              selectedColor: state.quickFillColorBinding,
              colors: fillColors
            )
          }
        }

        if state.quickPropertiesSupportsStrokeWidth {
          QuickPropertiesDivider()
          QuickStrokeWidthControl(value: state.quickStrokeWidthBinding)
        }

        if state.quickPropertiesSupportsArrowStyle {
          QuickPropertiesDivider()
          QuickArrowStyleControl(selectedStyle: state.quickArrowStyleBinding)
        }

        Spacer(minLength: 0)

        if !state.showSidebar {
          sidebarButton
        }
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var colorTitle: String {
    state.quickPropertiesTool == .text ? L10n.Common.text : L10n.Common.color
  }

  private var contextChip: some View {
    HStack(spacing: 6) {
      Image(systemName: state.quickPropertiesTool?.icon ?? "slider.horizontal.3")
        .font(.system(size: 11, weight: .semibold))
      Text(state.quickPropertiesContextTitle)
        .font(Typography.labelMedium)
    }
    .foregroundColor(.primary)
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(
      Capsule()
        .fill(Color.accentColor.opacity(state.quickPropertiesMode == .selectedItem ? 0.18 : 0.1))
    )
    .overlay(
      Capsule()
        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
    )
  }

  private var sidebarButton: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        state.showSidebar = true
      }
    } label: {
      Label(L10n.Common.more, systemImage: "sidebar.left")
        .font(Typography.labelMedium)
        .foregroundColor(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
          RoundedRectangle(cornerRadius: Size.radiusSm)
            .fill(SidebarColors.itemDefault)
        )
        .overlay(
          RoundedRectangle(cornerRadius: Size.radiusSm)
            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .help(L10n.AnnotateUI.openSidebarForMoreControls)
  }
}

private struct QuickPropertiesGroup<Content: View>: View {
  let title: String
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    HStack(spacing: Spacing.sm) {
      Text(title)
        .font(Typography.labelSmall)
        .foregroundColor(SidebarColors.labelSecondary)
      content
    }
  }
}

private struct QuickPropertiesColorPalette: View {
  @Binding var selectedColor: Color
  let colors: [Color]

  var body: some View {
    HStack(spacing: 6) {
      ForEach(colors, id: \.self) { color in
        Button {
          selectedColor = color
        } label: {
          swatch(for: color)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func swatch(for color: Color) -> some View {
    ZStack {
      Circle()
        .fill(color == .clear ? Color.clear : color)
        .frame(width: 22, height: 22)
        .overlay(
          Circle()
            .strokeBorder(
              selectedColor == color ? Color.accentColor : Color.secondary.opacity(0.35),
              lineWidth: selectedColor == color ? 2 : 1
            )
        )

      if color == .clear {
        Circle()
          .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
          .frame(width: 22, height: 22)
        Image(systemName: "slash.circle")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.secondary)
      }
    }
  }
}

private struct QuickStrokeWidthControl: View {
  @Binding var value: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: L10n.Common.stroke) {
      HStack(spacing: 8) {
        Image(systemName: "line.diagonal")
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        Slider(value: $value, in: 1...20, step: 1)
          .frame(width: 120)
          .controlSize(.small)

        Text("\(Int(value))")
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
          .frame(width: 22, alignment: .trailing)
      }
    }
  }
}

private struct QuickArrowStyleControl: View {
  @Binding var selectedStyle: ArrowStyle

  var body: some View {
    QuickPropertiesGroup(title: L10n.Common.style) {
      HStack(spacing: 6) {
        ForEach(ArrowStyle.allCases) { style in
          Button {
            selectedStyle = style
          } label: {
            Image(systemName: style.icon)
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(selectedStyle == style ? .accentColor : .secondary)
              .frame(width: 28, height: 24)
              .background(
                RoundedRectangle(cornerRadius: 7)
                  .fill(selectedStyle == style ? Color.accentColor.opacity(0.16) : SidebarColors.itemDefault)
              )
              .overlay(
                RoundedRectangle(cornerRadius: 7)
                  .stroke(
                    selectedStyle == style ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.14),
                    lineWidth: 1
                  )
              )
          }
          .buttonStyle(.plain)
          .help(style.displayName)
        }
      }
    }
  }
}

private struct QuickPropertiesDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color(nsColor: .separatorColor))
      .frame(width: 1, height: 24)
  }
}
