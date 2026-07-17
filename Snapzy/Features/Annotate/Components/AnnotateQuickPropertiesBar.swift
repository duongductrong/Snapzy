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
    30
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
    let buttonCount = CGFloat(BlurType.allCases.count)
    let spacing: CGFloat = 5
    switch self {
    case .regular:
      return buttonCount * 28 + (buttonCount - 1) * spacing + 48
    case .compact:
      return buttonCount * 24 + (buttonCount - 1) * spacing + 40
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
    let showTextPresentation = state.quickPropertiesSupportsTextPresentation
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
    let hasBeforeTextPresentation = showStrokeColor || showFill
    let hasBeforeTextBackground = hasBeforeTextPresentation || showTextPresentation
    let hasBeforeTextFontSize = hasBeforeTextBackground || showTextBackground
    let hasBeforeWatermarkText = hasBeforeTextFontSize || showTextFontSize
    let hasBeforeWatermarkStyle = hasBeforeWatermarkText || showWatermark
    let hasBeforeWatermarkOpacity = hasBeforeWatermarkStyle || showWatermark
    let hasBeforeWatermarkRotation = hasBeforeWatermarkOpacity || showWatermark
    let hasBeforeBlurType = hasBeforeWatermarkRotation || showWatermark
    let hasBeforeSpotlightOpacity = hasBeforeBlurType || showBlurType
    let hasBeforeStrokeWidth = hasBeforeSpotlightOpacity || state.quickPropertiesSupportsSpotlightOpacity
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
          role: .annotationStroke,
          quickColorLimit: density == .regular ? 4 : 2,
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
          role: .annotationFill,
          quickColorLimit: density == .regular ? 4 : 2,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: showTextPresentation,
        isEnabled: state.quickPropertiesSupportsTextPresentation,
        showsLeadingDivider: hasBeforeTextPresentation,
        width: nil
      ) {
        QuickTextPresentationControl(
          buttonWidth: density.controlButtonWidth,
          groupSpacing: density.groupSpacing,
          selectedPresentation: state.quickTextPresentation,
          onSelect: state.setTextPresentation
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
          role: .textBackground,
          quickColorLimit: density == .regular ? 3 : 1,
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
        isVisible: showBlurType,
        isEnabled: state.quickPropertiesSupportsBlurType && state.hasImage && !state.isSensitiveRedactionScanning && state.editorMode == .annotate && !state.isCropInteractionActive,
        showsLeadingDivider: true,
        width: nil
      ) {
        QuickAutoRedactControl(
          state: state,
          buttonWidth: density.controlButtonWidth,
          groupSpacing: density.groupSpacing
        )
      }

      activePropertySlot(
        isVisible: state.quickPropertiesSupportsSpotlightOpacity,
        isEnabled: state.quickPropertiesSupportsSpotlightOpacity,
        showsLeadingDivider: hasBeforeSpotlightOpacity,
        width: density.opacityControlWidth
      ) {
        QuickSpotlightOpacityControl(
          value: state.quickSpotlightOpacityBinding,
          sliderWidth: density.sliderWidth,
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
          groupSpacing: density.groupSpacing,
          onEditingChanged: { isEditing in
            state.setQuickPropertiesControlEditing(isEditing)
          }
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
        width: nil
      ) {
        QuickArrowStyleControl(
          selectedStyle: state.quickArrowStyleBinding,
          selectedType: state.quickArrowTypeBinding,
          bendDirection: state.quickArrowBendDirectionBinding,
          startHead: state.quickArrowStartHeadBinding,
          endHead: state.quickArrowEndHeadBinding,
          showsBendDirection: state.quickPropertiesSupportsArrowBendDirection,
          showsEndpoints: state.quickPropertiesSupportsArrowEndpoints,
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

    compactContextChip(
      icon: icon,
      title: title,
      isSelectedItem: state.quickPropertiesMode == .selectedItem
    )
  }

  @ViewBuilder
  private func idleContextChip(density: QuickPropertiesDensity) -> some View {
    let isSelectionTool = state.selectedTool == .selection
    let icon = isSelectionTool ? state.selectedTool.icon : "slider.horizontal.3"
    let title = isSelectionTool ? L10n.Annotate.selectionTool : L10n.AnnotateContext.defaults(L10n.AnnotateUI.annotation)

    compactContextChip(
      icon: icon,
      title: title,
      isSelectedItem: false
    )
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
  let role: AnnotateColorPaletteRole
  let quickColorLimit: Int
  let groupSpacing: CGFloat

  @ObservedObject private var paletteStore = AnnotateColorPaletteStore.shared
  @State private var showsPopover = false

  var body: some View {
    QuickPropertiesGroup(title: title, spacing: groupSpacing) {
      HStack(spacing: 5) {
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
            colors: colors,
            role: role
          ) {
            showsPopover = false
          }
        }

        ForEach(Array(paletteStore.favoriteColors(for: role).prefix(quickColorLimit)), id: \.self) { color in
          Button {
            selectedColor = color
          } label: {
            QuickPropertiesColorSwatch(
              color: color,
              isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color),
              size: 16
            )
            .frame(width: 22, height: 26)
          }
          .buttonStyle(.plain)
          .help(L10n.Common.favorite)
          .annotateColorDraggable(color, sourceFavoriteRole: role)
        }
      }
    }
  }
}

private struct QuickPropertiesColorPopover: View {
  let title: String
  @Binding var selectedColor: Color
  let colors: [Color]
  let role: AnnotateColorPaletteRole
  let dismiss: () -> Void

  @ObservedObject private var paletteStore = AnnotateColorPaletteStore.shared
  @State private var draftCustomColor = Color.red
  @State private var activeDraftTarget: ColorDraftTarget?
  @State private var originalSelectedColor: Color?
  @State private var showsFavoriteSelectionPopover = false

  private enum ColorDraftTarget {
    case customPalette
    case favorite
  }

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

      let favorites = favoriteColors
      if !favorites.isEmpty {
        Text(L10n.Common.favorite)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)

        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
          ForEach(favorites, id: \.self) { color in
            favoriteColorButton(color)
          }

          if canAddFavorite {
            favoriteDropSlot
          }
        }
      } else {
        Text(L10n.Common.favorite)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)

        favoriteEmptyDropTarget
      }

      Divider()

      Text(L10n.Common.colors)
        .font(Typography.labelSmall)
        .foregroundColor(SidebarColors.labelSecondary)

      LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
        ForEach(colors, id: \.self) { color in
          paletteColorButton(color, overlayAction: nil, overlayHelp: "")
        }

        ForEach(paletteStore.customColors, id: \.self) { color in
          paletteColorButton(
            color,
            overlayAction: {
              paletteStore.removeColor(color)
            },
            overlayHelp: L10n.Common.deleteAction
          )
        }

        if activeDraftTarget == .customPalette {
          draftCustomColorButton
        }

        if activeDraftTarget != .customPalette {
          Button {
            beginCustomColorDraft()
          } label: {
            AnnotateAddColorSwatch(size: 22)
          }
          .buttonStyle(.plain)
          .help(L10n.Common.custom)
          .accessibilityLabel(L10n.Common.custom)
        }
      }

      if activeDraftTarget == .customPalette {
        colorPickerPanel
          .padding(.top, 2)
      }
    }
    .padding(12)
    .frame(width: 196, alignment: .leading)
    .onAppear {
      syncDraftColor(with: selectedColor)
    }
    .onChange(of: selectedColor) { color in
      syncDraftColor(with: color)
    }
    .onChange(of: favoriteColors.count) { count in
      if count >= AnnotateColorPaletteStore.maximumFavoriteColorCount {
        closeFavoriteSelectionPopover()
      }
    }
    .onDisappear {
      showsFavoriteSelectionPopover = false
      cancelCustomColorDraftIfNeeded(keepFavoriteSelectionPopoverOpen: false)
    }
  }

  private var favoriteColors: [Color] {
    paletteStore.favoriteColors(for: role)
  }

  private var canAddFavorite: Bool {
    favoriteColors.count < AnnotateColorPaletteStore.maximumFavoriteColorCount
  }

  private var favoriteVaultColors: [Color] {
    guard canAddFavorite else { return [] }

    return (colors + paletteStore.customColors).reduce(into: [Color]()) { result, color in
      guard !AnnotateColorPaletteStore.isClear(color),
            !paletteStore.isFavorite(color, for: role),
            !result.contains(where: { AnnotateColorPaletteStore.colorsMatch($0, color) })
      else {
        return
      }

      result.append(color)
    }
  }

  private var favoriteDropSlot: some View {
    QuickPropertiesFavoriteDropSlot(
      onTap: showFavoriteSelectionPopover
    ) { payload in
      handleFavoriteDrop(payload)
    }
    .popover(isPresented: $showsFavoriteSelectionPopover, arrowEdge: .trailing) {
      favoriteSelectionPopover
    }
  }

  private var favoriteEmptyDropTarget: some View {
    QuickPropertiesFavoriteEmptyDropTarget(
      onTap: showFavoriteSelectionPopover
    ) { payload in
      handleFavoriteDrop(payload)
    }
    .popover(isPresented: $showsFavoriteSelectionPopover, arrowEdge: .trailing) {
      favoriteSelectionPopover
    }
  }

  private var favoriteSelectionPopover: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(L10n.Common.colors)
        .font(Typography.labelSmall)
        .foregroundColor(SidebarColors.labelSecondary)

      LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
        ForEach(favoriteVaultColors, id: \.self) { color in
          favoriteVaultColorButton(color)
        }

        if activeDraftTarget == .favorite {
          draftFavoriteColorButton
        }

        if activeDraftTarget != .favorite && canAddFavorite {
          Button {
            beginFavoriteColorDraft()
          } label: {
            AnnotateAddColorSwatch(size: 22)
          }
          .buttonStyle(.plain)
          .help(L10n.Common.custom)
          .accessibilityLabel(L10n.Common.custom)
        }
      }

      if activeDraftTarget == .favorite {
        colorPickerPanel
          .padding(.top, 2)
      }
    }
    .padding(12)
    .frame(width: 196, alignment: .leading)
    .onDisappear {
      if activeDraftTarget == .favorite {
        cancelColorDraft(keepFavoriteSelectionPopoverOpen: false)
      }
    }
  }

  private var draftFavoriteColorButton: some View {
    QuickPropertiesColorSwatch(
      color: draftCustomColor,
      isSelected: true,
      size: 22
    )
    .contentShape(Circle())
    .onTapGesture {
      selectedColor = draftCustomColor
    }
    .frame(width: 24, height: 24)
    .help(L10n.Common.custom)
  }

  private var draftCustomColorButton: some View {
    QuickPropertiesColorSwatch(
      color: draftCustomColor,
      isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, draftCustomColor),
      size: 22
    )
    .contentShape(Circle())
    .onTapGesture {
      selectedColor = draftCustomColor
    }
    .frame(width: 24, height: 24)
    .help(L10n.Common.custom)
  }

  private var colorPickerPanel: some View {
    AnnotateCustomColorPickerPanel(
      selectedColor: $selectedColor,
      draftColor: $draftCustomColor,
      onCancel: {
        cancelColorDraft()
      },
      onApply: applyColorDraft
    )
  }

  private func favoriteVaultColorButton(_ color: Color) -> some View {
    QuickPropertiesPaletteColorButton(
      color: color,
      title: AnnotateColorPaletteStore.isClear(color) ? L10n.Common.none : title,
      isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color),
      sourceFavoriteRole: nil,
      overlayAction: nil,
      overlayHelp: "",
      onSelect: {
        addVaultColorToFavorites(color)
      }
    )
  }

  private func favoriteColorButton(_ color: Color) -> some View {
    QuickPropertiesPaletteColorButton(
      color: color,
      title: AnnotateColorPaletteStore.isClear(color) ? L10n.Common.none : title,
      isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color),
      sourceFavoriteRole: role,
      overlayAction: {
        paletteStore.removeFavorite(color, for: role)
      },
      overlayHelp: L10n.Common.deleteAction,
      onDropPayload: { payload in
        handleFavoriteDrop(payload, targetColor: color)
      },
      onSelect: {
        selectColorAndDismiss(color)
      }
    )
  }

  private func paletteColorButton(
    _ color: Color,
    overlayAction: (() -> Void)?,
    overlayHelp: String
  ) -> some View {
    QuickPropertiesPaletteColorButton(
      color: color,
      title: AnnotateColorPaletteStore.isClear(color) ? L10n.Common.none : title,
      isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color),
      sourceFavoriteRole: nil,
      overlayAction: overlayAction,
      overlayHelp: overlayHelp,
      onSelect: {
        selectColorAndDismiss(color)
      }
    )
  }

  private func handleFavoriteDrop(_ payload: AnnotateColorDragPayload) {
    guard canAcceptFavoriteDrop(payload) else { return }

    paletteStore.acceptFavoriteDrop(
      payload,
      for: role
    )
    if !canAddFavorite {
      closeFavoriteSelectionPopover()
    }
  }

  private func handleFavoriteDrop(
    _ payload: AnnotateColorDragPayload,
    targetColor: Color
  ) {
    guard canAcceptFavoriteDrop(payload) else { return }

    paletteStore.acceptFavoriteDrop(
      payload,
      for: role,
      targetColor: targetColor
    )
    if !canAddFavorite {
      closeFavoriteSelectionPopover()
    }
  }

  private func canAcceptFavoriteDrop(_ payload: AnnotateColorDragPayload) -> Bool {
    paletteStore.isFavorite(payload.color, for: role) || canAddFavorite
  }

  private func syncDraftColor(with color: Color) {
    guard !AnnotateColorPaletteStore.isClear(color) else { return }
    draftCustomColor = color
  }

  private func selectColorAndDismiss(_ color: Color) {
    originalSelectedColor = nil
    activeDraftTarget = nil
    showsFavoriteSelectionPopover = false
    selectedColor = color
    dismiss()
  }

  private func beginCustomColorDraft() {
    showsFavoriteSelectionPopover = false
    beginColorDraft(target: .customPalette)
  }

  private func showFavoriteSelectionPopover() {
    guard canAddFavorite else {
      closeFavoriteSelectionPopover()
      return
    }

    if activeDraftTarget == .customPalette {
      cancelColorDraft()
    }

    showsFavoriteSelectionPopover = true
  }

  private func beginFavoriteColorDraft() {
    guard canAddFavorite else {
      closeFavoriteSelectionPopover()
      return
    }

    beginColorDraft(target: .favorite)
  }

  private func beginColorDraft(target: ColorDraftTarget) {
    if activeDraftTarget != nil {
      cancelColorDraft()
    }

    originalSelectedColor = selectedColor
    syncDraftColor(with: selectedColor)
    selectedColor = draftCustomColor
    activeDraftTarget = target
  }

  private func applyColorDraft() {
    guard !AnnotateColorPaletteStore.isClear(draftCustomColor) else { return }

    let target = activeDraftTarget

    switch target {
    case .customPalette:
      paletteStore.addColor(draftCustomColor)
    case .favorite:
      guard canAddFavorite else {
        cancelColorDraft(keepFavoriteSelectionPopoverOpen: false)
        return
      }

      paletteStore.addColor(draftCustomColor)
      paletteStore.addFavorite(draftCustomColor, for: role)
    case nil:
      return
    }

    selectedColor = draftCustomColor
    originalSelectedColor = nil
    activeDraftTarget = nil
    if target == .favorite {
      showsFavoriteSelectionPopover = false
    }
  }

  private func cancelColorDraft(keepFavoriteSelectionPopoverOpen: Bool = true) {
    let target = activeDraftTarget
    let shouldKeepFavoriteSelectionPopover = target == .favorite && keepFavoriteSelectionPopoverOpen

    guard let originalSelectedColor else {
      activeDraftTarget = nil
      if target == .favorite {
        showsFavoriteSelectionPopover = shouldKeepFavoriteSelectionPopover
      }
      return
    }

    selectedColor = originalSelectedColor
    draftCustomColor = originalSelectedColor
    self.originalSelectedColor = nil
    activeDraftTarget = nil
    if target == .favorite {
      showsFavoriteSelectionPopover = shouldKeepFavoriteSelectionPopover
    }
  }

  private func cancelCustomColorDraftIfNeeded(keepFavoriteSelectionPopoverOpen: Bool = true) {
    guard activeDraftTarget != nil else { return }
    cancelColorDraft(keepFavoriteSelectionPopoverOpen: keepFavoriteSelectionPopoverOpen)
  }

  private func closeFavoriteSelectionPopover() {
    showsFavoriteSelectionPopover = false
    if activeDraftTarget == .favorite {
      cancelColorDraft(keepFavoriteSelectionPopoverOpen: false)
    }
  }

  private func addVaultColorToFavorites(_ color: Color) {
    guard canAddFavorite else {
      closeFavoriteSelectionPopover()
      return
    }

    originalSelectedColor = nil
    activeDraftTarget = nil
    paletteStore.addFavorite(color, for: role)
    selectedColor = color
    showsFavoriteSelectionPopover = false
  }
}

private struct QuickPropertiesPaletteColorButton: View {
  let color: Color
  let title: String
  let isSelected: Bool
  let sourceFavoriteRole: AnnotateColorPaletteRole?
  let overlayAction: (() -> Void)?
  let overlayHelp: String
  var onDropPayload: ((AnnotateColorDragPayload) -> Void)? = nil
  let onSelect: () -> Void

  var body: some View {
    if let onDropPayload {
      content
        .onDrop(of: AnnotateColorDragPayload.supportedContentTypes, isTargeted: $isDropTargeted) { providers in
          AnnotateColorDragPayload.load(from: providers) { payload in
            guard let payload else { return }
            onDropPayload(payload)
          }
        }
    } else {
      content
    }
  }

  @State private var isDropTargeted = false

  private var content: some View {
    ZStack(alignment: .topTrailing) {
      QuickPropertiesColorSwatch(
        color: color,
        isSelected: isSelected,
        size: 22
      )
      .contentShape(Circle())
      .onTapGesture(perform: onSelect)
      .help(title)
      .annotateColorDraggable(color, sourceFavoriteRole: sourceFavoriteRole)

      if let overlayAction {
        Button(action: overlayAction) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Color.secondary.opacity(0.9))
            .background(
              Circle()
                .fill(SidebarColors.itemDefault)
                .frame(width: 8, height: 8)
            )
        }
        .buttonStyle(.plain)
        .offset(x: 5, y: -5)
        .help(overlayHelp)
      }

      if isDropTargeted {
        Circle()
          .stroke(Color.accentColor.opacity(0.75), lineWidth: 2)
          .frame(width: 28, height: 28)
      }
    }
    .frame(width: 24, height: 24)
  }
}

private struct QuickPropertiesFavoriteEmptyDropTarget: View {
  let onTap: () -> Void
  let onDropPayload: (AnnotateColorDragPayload) -> Void

  @State private var isTargeted = false

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: isTargeted ? "arrow.down" : "plus")
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(isTargeted ? .accentColor : .secondary)
        .frame(width: 24, height: 24)
        .background(Circle().fill(isTargeted ? Color.accentColor.opacity(0.1) : SidebarColors.itemDefault.opacity(0.55)))
        .overlay(
          Circle()
            .stroke(
              isTargeted ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.35),
              style: StrokeStyle(lineWidth: 1, dash: [3, 2])
            )
        )

      Text(L10n.Common.dragColorsHere)
        .font(Typography.labelSmall)
        .lineLimit(1)
    }
    .foregroundColor(isTargeted ? .accentColor : SidebarColors.labelSecondary)
    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
    .contentShape(Rectangle())
    .help(L10n.Common.custom)
    .accessibilityLabel(L10n.Common.custom)
    .onTapGesture(perform: onTap)
    .accessibilityAddTraits(.isButton)
    .onDrop(of: AnnotateColorDragPayload.supportedContentTypes, isTargeted: $isTargeted) { providers in
      AnnotateColorDragPayload.load(from: providers) { payload in
        guard let payload else { return }
        onDropPayload(payload)
      }
    }
  }
}

private struct QuickPropertiesFavoriteDropSlot: View {
  let onTap: () -> Void
  let onDropPayload: (AnnotateColorDragPayload) -> Void

  @State private var isTargeted = false

  var body: some View {
    Image(systemName: isTargeted ? "arrow.down" : "plus")
      .font(.system(size: 9, weight: .semibold))
      .foregroundColor(isTargeted ? .accentColor : .secondary)
      .frame(width: 22, height: 22)
      .background(Circle().fill(SidebarColors.itemDefault.opacity(0.55)))
      .overlay(
        Circle()
          .stroke(
            isTargeted ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.35),
            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
          )
      )
      .frame(width: 24, height: 24)
      .help(L10n.Common.custom)
      .contentShape(Circle())
      .onTapGesture(perform: onTap)
      .accessibilityLabel(L10n.Common.custom)
      .accessibilityAddTraits(.isButton)
      .onDrop(of: AnnotateColorDragPayload.supportedContentTypes, isTargeted: $isTargeted) { providers in
        AnnotateColorDragPayload.load(from: providers) { payload in
          guard let payload else { return }
          onDropPayload(payload)
        }
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
        .fill(AnnotateColorPaletteStore.isClear(color) ? Color.clear : color)
        .frame(width: size, height: size)
        .overlay(
          Circle()
            .strokeBorder(
              isSelected ? Color.accentColor : Color.secondary.opacity(0.35),
              lineWidth: isSelected ? 2 : 1
            )
        )

      if AnnotateColorPaletteStore.isClear(color) {
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
    spacing = Spacing.sm
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
  let onEditingChanged: (Bool) -> Void

  var body: some View {
    QuickPropertiesGroup(title: title, spacing: groupSpacing) {
      HStack(spacing: 6) {
        Image(systemName: iconName)
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        Slider(
          value: $value.stepped(by: 1, in: AnnotationProperties.controlValueRange),
          in: AnnotationProperties.controlValueRange,
          onEditingChanged: onEditingChanged
        )
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

        Slider(value: $value.stepped(by: 1, in: 12 ... 72), in: 12 ... 72)
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

private struct QuickTextPresentationControl: View {
  let buttonWidth: CGFloat
  let groupSpacing: CGFloat
  let selectedPresentation: TextPresentation
  let onSelect: (TextPresentation) -> Void

  var body: some View {
    QuickPropertiesGroup(title: L10n.AnnotateUI.textStyle, spacing: groupSpacing) {
      HStack(spacing: 5) {
        ForEach(TextPresentation.allCases) { presentation in
          Button {
            onSelect(presentation)
          } label: {
            Image(systemName: presentation.icon)
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(selectedPresentation == presentation ? .accentColor : .secondary)
              .frame(width: buttonWidth, height: 24)
              .background(
                RoundedRectangle(cornerRadius: 7)
                  .fill(selectedPresentation == presentation ? Color.accentColor.opacity(0.16) : SidebarColors.itemDefault)
              )
              .overlay(
                RoundedRectangle(cornerRadius: 7)
                  .stroke(selectedPresentation == presentation ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.14), lineWidth: 1)
              )
          }
          .buttonStyle(.plain)
          .help(presentation.helpText)
        }
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

        Slider(value: $value.stepped(by: 0.01, in: 0.05 ... 0.65), in: 0.05 ... 0.65)
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

private struct QuickSpotlightOpacityControl: View {
  @Binding var value: CGFloat
  let sliderWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: L10n.AnnotateUI.spotlightOpacity, spacing: groupSpacing) {
      HStack(spacing: 6) {
        Image(systemName: "circle.lefthalf.filled")
          .font(.system(size: 10))
          .foregroundColor(.secondary)

        Slider(value: $value.stepped(by: 0.01, in: 0.1 ... 0.9), in: 0.1 ... 0.9)
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

        Slider(value: $value.stepped(by: 1, in: -45 ... 45), in: -45 ... 45)
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

        Slider(value: $value.stepped(by: 1, in: 0 ... 60), in: 0 ... 60)
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

private struct QuickAutoRedactControl: View {
  @ObservedObject var state: AnnotateState
  let buttonWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    QuickPropertiesGroup(title: L10n.AnnotateUI.autoRedact, spacing: groupSpacing) {
      Button {
        state.autoRedactSensitiveData()
      } label: {
        Image(systemName: state.isSensitiveRedactionScanning ? "hourglass" : "shield.lefthalf.filled")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(state.isSensitiveRedactionScanning ? .accentColor : .secondary)
          .frame(width: buttonWidth, height: 24)
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
      .disabled(!state.hasImage || state.isSensitiveRedactionScanning || state.editorMode != .annotate || state.isCropInteractionActive)
      .opacity((!state.hasImage || state.isSensitiveRedactionScanning || state.editorMode != .annotate || state.isCropInteractionActive) ? 0.4 : 1)
      .help(
        state.isSensitiveRedactionScanning
          ? L10n.AnnotateUI.autoRedactionScanning
          : L10n.AnnotateUI.autoRedactSensitiveData
      )
    }
  }
}

private struct QuickArrowStyleControl: View {
  @Binding var selectedStyle: ArrowStyle
  @Binding var selectedType: ArrowType
  @Binding var bendDirection: ArrowBendDirection
  @Binding var startHead: ArrowEndpointStyle
  @Binding var endHead: ArrowEndpointStyle
  let showsBendDirection: Bool
  let showsEndpoints: Bool
  let buttonWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    HStack(spacing: groupSpacing) {
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

          if showsBendDirection {
            Rectangle()
              .fill(Color(nsColor: .separatorColor))
              .frame(width: 1, height: 18)
              .padding(.horizontal, 1)

            Button {
              bendDirection = bendDirection.toggled
            } label: {
              Image(systemName: bendDirection.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(bendDirection == .alternate ? .accentColor : .secondary)
                .frame(width: buttonWidth, height: 24)
                .background(
                  RoundedRectangle(cornerRadius: 7)
                    .fill(bendDirection == .alternate ? Color.accentColor.opacity(0.16) : SidebarColors.itemDefault)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 7)
                    .stroke(
                      bendDirection == .alternate ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.14),
                      lineWidth: 1
                    )
                )
            }
            .buttonStyle(.plain)
            .help("\(L10n.AnnotateUI.flipArrowBend): \(bendDirection.displayName)")
            .accessibilityLabel(L10n.AnnotateUI.flipArrowBend)
          }
        }
      }

      Rectangle()
        .fill(Color(nsColor: .separatorColor))
        .frame(width: 1, height: 22)
        .padding(.horizontal, 2)

      QuickPropertiesGroup(title: L10n.Common.display, spacing: groupSpacing) {
        HStack(spacing: 5) {
          ForEach(ArrowType.allCases) { type in
            Button {
              selectedType = type
            } label: {
              Image(systemName: type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selectedType == type ? .accentColor : .secondary)
                .frame(width: buttonWidth, height: 24)
                .background(
                  RoundedRectangle(cornerRadius: 7)
                    .fill(selectedType == type ? Color.accentColor.opacity(0.16) : SidebarColors.itemDefault)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 7)
                    .stroke(
                      selectedType == type ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.14),
                      lineWidth: 1
                    )
                )
            }
            .buttonStyle(.plain)
            .help(type.displayName)
          }
        }
      }

      if showsEndpoints {
        Rectangle()
          .fill(Color(nsColor: .separatorColor))
          .frame(width: 1, height: 22)
          .padding(.horizontal, 2)

        endpointPicker(title: L10n.AnnotateUI.arrowStartHead, selection: $startHead)
        endpointPicker(title: L10n.AnnotateUI.arrowEndHead, selection: $endHead)
      }
    }
  }

  private func endpointPicker(title: String, selection: Binding<ArrowEndpointStyle>) -> some View {
    QuickPropertiesGroup(title: title, spacing: groupSpacing) {
      HStack(spacing: 5) {
        ForEach(ArrowEndpointStyle.allCases) { head in
          Button {
            selection.wrappedValue = head
          } label: {
            Image(systemName: head.icon)
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(selection.wrappedValue == head ? .accentColor : .secondary)
              .frame(width: buttonWidth, height: 24)
              .background(
                RoundedRectangle(cornerRadius: 7)
                  .fill(selection.wrappedValue == head ? Color.accentColor.opacity(0.16) : SidebarColors.itemDefault)
              )
              .overlay(
                RoundedRectangle(cornerRadius: 7)
                  .stroke(
                    selection.wrappedValue == head ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.14),
                    lineWidth: 1
                  )
              )
          }
          .buttonStyle(.plain)
          .help(head.displayName)
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