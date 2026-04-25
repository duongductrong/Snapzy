//
//  AnnotateQuickPropertiesBar.swift
//  Snapzy
//
//  Contextual quick properties bar for common annotation styling.
//

import SwiftUI

private enum QuickPropertiesDensity {
  case regular
  case compact

  var rowSpacing: CGFloat {
    switch self {
    case .regular: return 12
    case .compact: return 6
    }
  }

  var groupSpacing: CGFloat {
    switch self {
    case .regular: return Spacing.sm
    case .compact: return 6
    }
  }

  var horizontalPadding: CGFloat {
    switch self {
    case .regular: return Spacing.md
    case .compact: return 10
    }
  }

  var contextChipWidth: CGFloat {
    switch self {
    case .regular: return 172
    case .compact: return 30
    }
  }

  var selectionInfoWidth: CGFloat {
    switch self {
    case .regular: return 108
    case .compact: return 76
    }
  }

  var selectionStyleControlWidth: CGFloat {
    switch self {
    case .regular: return 224
    case .compact: return 192
    }
  }

  var selectionToolPickerWidth: CGFloat {
    switch self {
    case .regular: return 176
    case .compact: return 148
    }
  }

  var strokeControlWidth: CGFloat {
    switch self {
    case .regular: return 184
    case .compact: return 146
    }
  }

  var textSizeControlWidth: CGFloat {
    switch self {
    case .regular: return 184
    case .compact: return 146
    }
  }

  var watermarkTextControlWidth: CGFloat {
    switch self {
    case .regular: return 210
    case .compact: return 158
    }
  }

  var watermarkStyleControlWidth: CGFloat {
    switch self {
    case .regular: return 142
    case .compact: return 124
    }
  }

  var opacityControlWidth: CGFloat {
    switch self {
    case .regular: return 220
    case .compact: return 184
    }
  }

  var rotationControlWidth: CGFloat {
    switch self {
    case .regular: return 232
    case .compact: return 196
    }
  }

  var cornerControlWidth: CGFloat {
    switch self {
    case .regular: return 190
    case .compact: return 154
    }
  }

  var blurTypeControlWidth: CGFloat {
    switch self {
    case .regular: return 142
    case .compact: return 124
    }
  }

  var arrowControlWidth: CGFloat {
    switch self {
    case .regular: return 138
    case .compact: return 116
    }
  }

  var toolPickerWidth: CGFloat {
    switch self {
    case .regular: return 148
    case .compact: return 124
    }
  }

  var sliderWidth: CGFloat {
    switch self {
    case .regular: return 96
    case .compact: return 56
    }
  }

  var controlButtonWidth: CGFloat {
    switch self {
    case .regular: return 28
    case .compact: return 24
    }
  }

  var showsFullContext: Bool {
    self == .regular
  }
}

struct AnnotateQuickPropertiesBar: View {
  @ObservedObject var state: AnnotateState

  private let strokeColors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]
  private let fillColors: [Color] = [.clear, .red, .orange, .yellow, .green, .blue, .purple, .white, .black]
  private let textBackgroundColors: [Color] = [.clear, .white, .black, .yellow, .blue]
  private let selectionStyleTools: [AnnotationToolType] = [.selection, .rectangle, .arrow, .text, .watermark, .highlighter]

  var body: some View {
    ViewThatFits(in: .horizontal) {
      barContent(density: .regular)
      barContent(density: .compact)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .clipped()
    .background(Color(nsColor: .windowBackgroundColor))
  }

  @ViewBuilder
  private func barContent(density: QuickPropertiesDensity) -> some View {
    if state.showsQuickPropertiesBar {
      activePropertiesContent(density: density)
    } else {
      idlePropertiesContent(density: density)
    }
  }

  private func activePropertiesContent(density: QuickPropertiesDensity) -> some View {
    let showStrokeColor = state.quickPropertiesSupportsStrokeColor
    let showFill = state.quickPropertiesSupportsFill
    let showTextBackground = state.quickPropertiesSupportsTextBackground
    let showTextFontSize = state.quickPropertiesSupportsTextFontSize
    let showWatermark = state.quickPropertiesSupportsWatermark
    let showBlurType = state.quickPropertiesSupportsBlurType
    let showStrokeWidth = state.quickPropertiesSupportsStrokeWidth
    let showCornerRadius = state.quickPropertiesSupportsCornerRadius
    let showArrowStyle = state.quickPropertiesSupportsArrowStyle
    let hasEditableStyleControls = showStrokeColor
      || showFill
      || showTextBackground
      || showTextFontSize
      || showWatermark
      || showBlurType
      || showStrokeWidth
      || showCornerRadius
      || showArrowStyle
    let showSelectionStyle = state.quickPropertiesShowsSelectionStyle && !hasEditableStyleControls
    let showSelectionInfo = state.quickPropertiesSelectedAnnotationCount > 0 && showSelectionStyle
    let hasBeforeTextBackground = showStrokeColor || showFill
    let hasBeforeTextFontSize = hasBeforeTextBackground || showTextBackground
    let hasBeforeWatermarkText = hasBeforeTextFontSize || showTextFontSize
    let hasBeforeWatermarkStyle = hasBeforeWatermarkText || showWatermark
    let hasBeforeWatermarkOpacity = hasBeforeWatermarkStyle || showWatermark
    let hasBeforeWatermarkRotation = hasBeforeWatermarkOpacity || showWatermark
    let hasBeforeBlurType = hasBeforeWatermarkRotation || showWatermark
    let hasBeforeStrokeWidth = hasBeforeBlurType || showBlurType
    let hasBeforeCornerRadius = hasBeforeStrokeWidth || showStrokeWidth
    let hasBeforeArrowStyle = hasBeforeCornerRadius || showCornerRadius

    return HStack(spacing: density.rowSpacing) {
      contextChip(density: density)
        .frame(width: density.contextChipWidth, alignment: .leading)

      activePropertySlot(
        isVisible: showSelectionInfo,
        isEnabled: true,
        showsLeadingDivider: false,
        width: density.selectionInfoWidth
      ) {
        QuickSelectionInfoControl(
          count: state.quickPropertiesSelectedAnnotationCount,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showSelectionStyle,
        isEnabled: state.editorMode == .annotate,
        showsLeadingDivider: showSelectionInfo,
        width: density.selectionStyleControlWidth
      ) {
        QuickSelectionStyleControl(
          selectedTool: state.selectedTool,
          tools: selectionStyleTools,
          isEnabled: state.editorMode == .annotate,
          width: density.selectionToolPickerWidth,
          buttonWidth: density.controlButtonWidth,
          groupSpacing: density.groupSpacing
        ) { tool in
          state.activateTool(tool)
        }
      }

      activePropertySlot(
        isVisible: showStrokeColor,
        isEnabled: state.quickPropertiesSupportsStrokeColor,
        showsLeadingDivider: false,
        width: nil
      ) {
        QuickPropertiesColorPopoverControl(
          title: colorTitle,
          selectedColor: state.quickStrokeColorBinding,
          colors: strokeColors,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showFill,
        isEnabled: state.quickPropertiesSupportsFill,
        showsLeadingDivider: showStrokeColor,
        width: nil
      ) {
        QuickPropertiesColorPopoverControl(
          title: L10n.Common.fill,
          selectedColor: state.quickFillColorBinding,
          colors: fillColors,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showTextBackground,
        isEnabled: state.quickPropertiesSupportsTextBackground,
        showsLeadingDivider: hasBeforeTextBackground,
        width: nil
      ) {
        QuickPropertiesColorPopoverControl(
          title: L10n.Common.background,
          selectedColor: state.quickTextBackgroundBinding,
          colors: textBackgroundColors,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showTextFontSize,
        isEnabled: state.quickPropertiesSupportsTextFontSize,
        showsLeadingDivider: hasBeforeTextFontSize,
        width: density.textSizeControlWidth
      ) {
        QuickTextFontSizeControl(
          value: state.quickTextFontSizeBinding,
          sliderWidth: density.sliderWidth,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showWatermark,
        isEnabled: state.quickPropertiesSupportsWatermark,
        showsLeadingDivider: hasBeforeWatermarkText,
        width: density.watermarkTextControlWidth
      ) {
        QuickWatermarkTextControl(
          text: state.quickWatermarkTextBinding,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showWatermark,
        isEnabled: state.quickPropertiesSupportsWatermark,
        showsLeadingDivider: hasBeforeWatermarkStyle,
        width: density.watermarkStyleControlWidth
      ) {
        QuickWatermarkStyleControl(
          selectedStyle: state.quickWatermarkStyleBinding,
          buttonWidth: density.controlButtonWidth,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showWatermark,
        isEnabled: state.quickPropertiesSupportsWatermark,
        showsLeadingDivider: hasBeforeWatermarkOpacity,
        width: density.opacityControlWidth
      ) {
        QuickWatermarkOpacityControl(
          value: state.quickWatermarkOpacityBinding,
          sliderWidth: density.sliderWidth,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showWatermark,
        isEnabled: state.quickPropertiesSupportsWatermark,
        showsLeadingDivider: hasBeforeWatermarkRotation,
        width: density.rotationControlWidth
      ) {
        QuickWatermarkRotationControl(
          value: state.quickWatermarkRotationBinding,
          sliderWidth: density.sliderWidth,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showBlurType,
        isEnabled: state.quickPropertiesSupportsBlurType,
        showsLeadingDivider: hasBeforeBlurType,
        width: density.blurTypeControlWidth
      ) {
        QuickBlurTypeControl(
          selectedType: state.quickBlurTypeBinding,
          buttonWidth: density.controlButtonWidth,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showStrokeWidth,
        isEnabled: state.quickPropertiesSupportsStrokeWidth,
        showsLeadingDivider: hasBeforeStrokeWidth,
        width: density.strokeControlWidth
      ) {
        QuickStrokeWidthControl(
          title: state.quickStrokeWidthLabel,
          iconName: state.quickStrokeWidthIcon,
          value: state.quickStrokeWidthBinding,
          displayText: state.quickStrokeWidthDisplayText,
          sliderWidth: density.sliderWidth,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showCornerRadius,
        isEnabled: state.quickPropertiesSupportsCornerRadius,
        showsLeadingDivider: hasBeforeCornerRadius,
        width: density.cornerControlWidth
      ) {
        QuickCornerRadiusControl(
          value: state.quickCornerRadiusBinding,
          sliderWidth: density.sliderWidth,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showArrowStyle,
        isEnabled: state.quickPropertiesSupportsArrowStyle,
        showsLeadingDivider: hasBeforeArrowStyle,
        width: density.arrowControlWidth
      ) {
        QuickArrowStyleControl(
          selectedStyle: state.quickArrowStyleBinding,
          buttonWidth: density.controlButtonWidth,
          groupSpacing: density.groupSpacing
        )
      }
    }
    .fixedSize(horizontal: true, vertical: false)
    .padding(.horizontal, density.horizontalPadding)
    .padding(.vertical, Spacing.sm)
  }

  private func idlePropertiesContent(density: QuickPropertiesDensity) -> some View {
    HStack(spacing: density.rowSpacing) {
      idleContextChip(density: density)
        .frame(width: density.contextChipWidth, alignment: .leading)

      if state.quickPropertiesShowsSelectionStyle {
        stableSlot(isEnabled: state.editorMode == .annotate, width: density.selectionStyleControlWidth) {
          QuickSelectionStyleControl(
            selectedTool: state.selectedTool,
            tools: selectionStyleTools,
            isEnabled: state.editorMode == .annotate,
            width: density.selectionToolPickerWidth,
            buttonWidth: density.controlButtonWidth,
            groupSpacing: density.groupSpacing
          ) { tool in
            state.activateTool(tool)
          }
        }
      }
    }
    .fixedSize(horizontal: true, vertical: false)
    .padding(.horizontal, density.horizontalPadding)
    .padding(.vertical, Spacing.sm)
  }

  private func stableSlot<Content: View>(
    isEnabled: Bool,
    width: CGFloat?,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .frame(width: width, alignment: .leading)
      .disabled(!isEnabled)
      .opacity(isEnabled ? 1 : 0.26)
  }

  @ViewBuilder
  private func activePropertySlot<Content: View>(
    isVisible: Bool,
    isEnabled: Bool,
    showsLeadingDivider: Bool,
    width: CGFloat?,
    @ViewBuilder content: () -> Content
  ) -> some View {
    if isVisible {
      if showsLeadingDivider {
        QuickPropertiesDivider()
      }
      stableSlot(isEnabled: isEnabled, width: width) {
        content()
      }
    }
  }

  private var colorTitle: String {
    state.quickPropertiesTool == .text ? L10n.Common.text : L10n.Common.color
  }

  @ViewBuilder
  private func contextChip(density: QuickPropertiesDensity) -> some View {
    let icon = state.quickPropertiesTool?.icon ?? "slider.horizontal.3"
    let title = state.quickPropertiesContextTitle

    if density.showsFullContext {
      quickPropertiesChip(
        icon: icon,
        title: title,
        isSelectedItem: state.quickPropertiesMode == .selectedItem
      )
    } else {
      compactContextChip(
        icon: icon,
        title: title,
        isSelectedItem: state.quickPropertiesMode == .selectedItem
      )
    }
  }

  @ViewBuilder
  private func idleContextChip(density: QuickPropertiesDensity) -> some View {
    let isSelectionTool = state.selectedTool == .selection
    let icon = isSelectionTool ? state.selectedTool.icon : "slider.horizontal.3"
    let title = isSelectionTool ? L10n.Annotate.selectionTool : L10n.AnnotateContext.defaults(L10n.AnnotateUI.annotation)

    if density.showsFullContext {
      quickPropertiesChip(
        icon: icon,
        title: title,
        isSelectedItem: false
      )
    } else {
      compactContextChip(
        icon: icon,
        title: title,
        isSelectedItem: false
      )
    }
  }

  private func quickPropertiesChip(icon: String, title: String, isSelectedItem: Bool) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .semibold))
      Text(title)
        .font(Typography.labelMedium)
        .lineLimit(1)
        .truncationMode(.tail)
        .layoutPriority(1)
    }
    .foregroundColor(.primary)
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Capsule()
        .fill(Color.accentColor.opacity(isSelectedItem ? 0.18 : 0.1))
    )
    .overlay(
      Capsule()
        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
    )
    .help(title)
  }

  private func compactContextChip(icon: String, title: String, isSelectedItem: Bool) -> some View {
    Image(systemName: icon)
      .font(.system(size: 11, weight: .semibold))
      .foregroundColor(.primary)
      .frame(width: 28, height: 26)
      .background(
        Circle()
          .fill(Color.accentColor.opacity(isSelectedItem ? 0.18 : 0.1))
      )
      .overlay(
        Circle()
          .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
      )
      .help(title)
      .accessibilityLabel(title)
  }
}

private struct QuickSelectionStyleControl: View {
  let selectedTool: AnnotationToolType
  let tools: [AnnotationToolType]
  let isEnabled: Bool
  let width: CGFloat
  let buttonWidth: CGFloat
  let groupSpacing: CGFloat
  let action: (AnnotationToolType) -> Void

  var body: some View {
    QuickPropertiesGroup(title: L10n.Common.style, spacing: groupSpacing) {
      QuickToolPicker(
        selectedTool: selectedTool,
        tools: tools,
        isEnabled: isEnabled,
        width: width,
        buttonWidth: buttonWidth,
        action: action
      )
    }
  }
}

private struct QuickToolPicker: View {
  let selectedTool: AnnotationToolType
  let tools: [AnnotationToolType]
  let isEnabled: Bool
  let width: CGFloat
  let buttonWidth: CGFloat
  let action: (AnnotationToolType) -> Void

  var body: some View {
    HStack(spacing: 5) {
      ForEach(tools, id: \.self) { tool in
        Button {
          action(tool)
        } label: {
          Image(systemName: tool.icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(selectedTool == tool ? .accentColor : .secondary)
            .frame(width: buttonWidth, height: 26)
            .background(
              RoundedRectangle(cornerRadius: 7)
                .fill(selectedTool == tool ? Color.accentColor.opacity(0.16) : SidebarColors.itemDefault)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 7)
                .stroke(
                  selectedTool == tool ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.14),
                  lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .help(tool.displayName)
      }
    }
    .frame(width: width, alignment: .leading)
  }
}

private struct QuickPropertiesColorPopoverControl: View {
  let title: String
  @Binding var selectedColor: Color
  let colors: [Color]
  let groupSpacing: CGFloat

  @State private var showsPopover = false

  var body: some View {
    QuickPropertiesGroup(title: title, spacing: groupSpacing) {
      Button {
        showsPopover.toggle()
      } label: {
        HStack(spacing: 5) {
          QuickPropertiesColorSwatch(
            color: selectedColor,
            isSelected: false,
            size: 16
          )
          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.secondary)
        }
        .frame(width: 42, height: 26)
        .background(
          RoundedRectangle(cornerRadius: 7)
            .fill(SidebarColors.itemDefault)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 7)
            .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
      }
      .buttonStyle(.plain)
      .help(title)
      .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
        QuickPropertiesColorPopover(
          title: title,
          selectedColor: $selectedColor,
          colors: colors
        ) {
          showsPopover = false
        }
      }
    }
  }
}

private struct QuickPropertiesColorPopover: View {
  let title: String
  @Binding var selectedColor: Color
  let colors: [Color]
  let dismiss: () -> Void

  private let columns = Array(
    repeating: GridItem(.fixed(24), spacing: 8),
    count: 5
  )

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(title)
        .font(Typography.labelMedium)
        .foregroundColor(SidebarColors.labelSecondary)
        .lineLimit(1)

      LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
        colorButtons
      }
    }
    .padding(12)
    .frame(width: 184, alignment: .leading)
  }

  @ViewBuilder
  private var colorButtons: some View {
    ForEach(colors, id: \.self) { color in
      Button {
        selectedColor = color
        dismiss()
      } label: {
        QuickPropertiesColorSwatch(
          color: color,
          isSelected: selectedColor == color,
          size: 22
        )
      }
      .buttonStyle(.plain)
      .help(color == .clear ? L10n.Common.none : title)
    }
  }
}

private struct QuickPropertiesColorSwatch: View {
  let color: Color
  let isSelected: Bool
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(color == .clear ? Color.clear : color)
        .frame(width: size, height: size)
        .overlay(
          Circle()
            .strokeBorder(
              isSelected ? Color.accentColor : Color.secondary.opacity(0.35),
              lineWidth: isSelected ? 2 : 1
            )
        )

      if color == .clear {
        Circle()
          .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
          .frame(width: size, height: size)
        Image(systemName: "slash.circle")
          .font(.system(size: max(9, size * 0.5), weight: .semibold))
          .foregroundColor(.secondary)
      }
    }
  }
}

private struct QuickPropertiesGroup<Content: View>: View {
  let title: String
  let spacing: CGFloat
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.spacing = Spacing.sm
    self.content = content()
  }

  init(title: String, spacing: CGFloat, @ViewBuilder content: () -> Content) {
    self.title = title
    self.spacing = spacing
    self.content = content()
  }

  var body: some View {
    HStack(spacing: spacing) {
      Text(title)
        .font(Typography.labelSmall)
        .foregroundColor(SidebarColors.labelSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .fixedSize(horizontal: true, vertical: false)
      content
    }
  }
}

private struct QuickSelectionInfoControl: View {
  let count: Int
  let groupSpacing: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: L10n.Annotate.selectionTool, spacing: groupSpacing) {
      HStack(spacing: 5) {
        Image(systemName: "square.stack.3d.up")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.secondary)

        Text("\(count)")
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
          .lineLimit(1)
          .monospacedDigit()
      }
      .frame(height: 24)
    }
  }
}

private struct QuickStrokeWidthControl: View {
  let title: String
  let iconName: String
  @Binding var value: CGFloat
  let displayText: String
  let sliderWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: title, spacing: groupSpacing) {
      HStack(spacing: 6) {
        Image(systemName: iconName)
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        Slider(value: $value, in: AnnotationProperties.controlValueRange, step: 1)
          .frame(width: sliderWidth)
          .controlSize(.small)

        Text(displayText)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
          .lineLimit(1)
          .monospacedDigit()
          .frame(width: 28, alignment: .trailing)
      }
    }
  }
}

private struct QuickTextFontSizeControl: View {
  @Binding var value: CGFloat
  let sliderWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: L10n.Common.size, spacing: groupSpacing) {
      HStack(spacing: 6) {
        Image(systemName: "textformat.size")
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        Slider(value: $value, in: 12...72, step: 1)
          .frame(width: sliderWidth)
          .controlSize(.small)

        Text("\(Int(value))pt")
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
          .lineLimit(1)
          .monospacedDigit()
          .frame(width: 34, alignment: .trailing)
      }
    }
  }
}

private struct QuickWatermarkTextControl: View {
  @Binding var text: String
  let groupSpacing: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: L10n.Common.text, spacing: groupSpacing) {
      TextField("", text: $text)
        .textFieldStyle(.plain)
        .font(Typography.labelSmall)
        .foregroundColor(SidebarColors.labelPrimary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
          RoundedRectangle(cornerRadius: 7)
            .fill(SidebarColors.itemDefault)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 7)
            .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }
  }
}

private struct QuickWatermarkStyleControl: View {
  @Binding var selectedStyle: WatermarkStyle
  let buttonWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: L10n.Common.style, spacing: groupSpacing) {
      HStack(spacing: 5) {
        ForEach(WatermarkStyle.allCases) { style in
          Button {
            selectedStyle = style
          } label: {
            Image(systemName: style.icon)
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(selectedStyle == style ? .accentColor : .secondary)
              .frame(width: buttonWidth, height: 24)
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

private struct QuickWatermarkOpacityControl: View {
  @Binding var value: CGFloat
  let sliderWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: L10n.AnnotateUI.watermarkOpacity, spacing: groupSpacing) {
      HStack(spacing: 6) {
        Image(systemName: "circle.lefthalf.filled")
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        Slider(value: $value, in: 0.05...0.65, step: 0.01)
          .frame(width: sliderWidth)
          .controlSize(.small)

        Text("\(Int((value * 100).rounded()))%")
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
          .lineLimit(1)
          .monospacedDigit()
          .frame(width: 38, alignment: .trailing)
      }
    }
  }
}

private struct QuickWatermarkRotationControl: View {
  @Binding var value: CGFloat
  let sliderWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: L10n.Common.rotation, spacing: groupSpacing) {
      HStack(spacing: 6) {
        Image(systemName: "rotate.right")
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        Slider(value: $value, in: -45...45, step: 1)
          .frame(width: sliderWidth)
          .controlSize(.small)

        Text("\(Int(value.rounded()))deg")
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
          .lineLimit(1)
          .monospacedDigit()
          .frame(width: 44, alignment: .trailing)
      }
    }
  }
}

private struct QuickCornerRadiusControl: View {
  @Binding var value: CGFloat
  let sliderWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: L10n.Common.corners, spacing: groupSpacing) {
      HStack(spacing: 6) {
        Image(systemName: "roundedbottom.horizontal")
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        Slider(value: $value, in: 0...60, step: 1)
          .frame(width: sliderWidth)
          .controlSize(.small)

        Text("\(Int(value))")
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
          .lineLimit(1)
          .monospacedDigit()
          .frame(width: 22, alignment: .trailing)
      }
    }
  }
}

private struct QuickBlurTypeControl: View {
  @Binding var selectedType: BlurType
  let buttonWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: L10n.AnnotateUI.blurType, spacing: groupSpacing) {
      HStack(spacing: 5) {
        ForEach(BlurType.allCases) { blurType in
          Button {
            selectedType = blurType
          } label: {
            Image(systemName: blurType.icon)
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(selectedType == blurType ? .accentColor : .secondary)
              .frame(width: buttonWidth, height: 24)
              .background(
                RoundedRectangle(cornerRadius: 7)
                  .fill(selectedType == blurType ? Color.accentColor.opacity(0.16) : SidebarColors.itemDefault)
              )
              .overlay(
                RoundedRectangle(cornerRadius: 7)
                  .stroke(
                    selectedType == blurType ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.14),
                    lineWidth: 1
                  )
              )
          }
          .buttonStyle(.plain)
          .help(blurType.displayName)
        }
      }
    }
  }
}

private struct QuickArrowStyleControl: View {
  @Binding var selectedStyle: ArrowStyle
  let buttonWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: L10n.Common.style, spacing: groupSpacing) {
      HStack(spacing: 5) {
        ForEach(ArrowStyle.allCases) { style in
          Button {
            selectedStyle = style
          } label: {
            Image(systemName: style.icon)
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(selectedStyle == style ? .accentColor : .secondary)
              .frame(width: buttonWidth, height: 24)
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
