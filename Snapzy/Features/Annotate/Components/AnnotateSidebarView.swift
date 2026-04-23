//
//  AnnotateSidebarView.swift
//  Snapzy
//
//  Left sidebar for background and styling settings
//

import AppKit
import SwiftUI

/// Left sidebar with background customization options
struct AnnotateSidebarView: View {
  @ObservedObject var state: AnnotateState
  @State private var isPresetDropdownPresented = false
  
  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        presetControlsSection

        // Compact gradient section
        gradientSection

        // Wallpaper section
        wallpaperSection

        // Compact color section
        colorSection

        Divider().background(Color(nsColor: .separatorColor))

        // Sliders section
        slidersSection

        // Alignment section
        alignmentSection

        // Ratio section
        // ratioSection

        // Text styling section (shown when text annotation is selected)
        if state.selectedTextAnnotation != nil {
          Divider().background(Color(nsColor: .separatorColor))
          TextStylingSection(state: state)
        }

        // Blur type section (shown when blur tool is active)
        if state.selectedTool == .blur {
          Divider().background(Color(nsColor: .separatorColor))
          BlurTypeSection(state: state)
        }

        // Mockup section (shown when mockup mode is active)
        if state.editorMode == .mockup {
          Divider().background(Color(nsColor: .separatorColor))
          MockupControlsSection(state: state)
        }

        Spacer(minLength: Spacing.lg)
      }
      .padding(Spacing.md)
    }
    .frame(maxHeight: .infinity)
//    .background(Color(nsColor: .scrubberTexturedBackground))
  }
  
  // MARK: - Preset Controls

  private var presetControlsSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: L10n.AnnotateUI.presets)

      HStack(spacing: Spacing.xs) {
        noneButton
        presetDropdownButton
      }

      if state.canUpdateSelectedCanvasPreset {
        updatePresetButton
      }
    }
  }

  private var noneButton: some View {
    Button {
      state.resetCanvasEffectsToNone()
    } label: {
      Text(L10n.Common.none)
        .font(Typography.labelMedium)
        .foregroundColor(SidebarColors.labelPrimary)
        .frame(minWidth: 50)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 7)
        .background(
          RoundedRectangle(cornerRadius: Size.radiusSm)
            .fill(state.isNoneCanvasEffectsActive ? Color.accentColor.opacity(0.25) : SidebarColors.itemDefault)
        )
        .overlay(
          RoundedRectangle(cornerRadius: Size.radiusSm)
            .stroke(
              state.isNoneCanvasEffectsActive ? Color.accentColor : Color.clear,
              lineWidth: Size.strokeSelected
            )
        )
    }
    .buttonStyle(.plain)
    .help(L10n.AnnotateUI.resetCanvasEffectsHelp)
  }

  private var presetDropdownButton: some View {
    Button {
      isPresetDropdownPresented.toggle()
    } label: {
      HStack(spacing: Spacing.xs) {
        Text(state.selectedCanvasPreset?.name ?? L10n.AnnotateUI.selectPreset)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelPrimary)
          .lineLimit(1)
          .truncationMode(.tail)

        Spacer(minLength: Spacing.xs)

        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(SidebarColors.labelSecondary)
          .rotationEffect(.degrees(isPresetDropdownPresented ? 180 : 0))
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: Size.radiusSm)
          .fill(SidebarColors.itemDefault)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Size.radiusSm)
          .stroke(
            state.selectedCanvasPresetId != nil ? Color.accentColor.opacity(0.7) : Color.clear,
            lineWidth: Size.strokeDefault
          )
      )
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .help(L10n.AnnotateUI.applySavedStylePreset)
    .popover(isPresented: $isPresetDropdownPresented, arrowEdge: .bottom) {
      presetDropdownContent
    }
  }

  private var presetDropdownContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        isPresetDropdownPresented = false
        handleCreatePreset()
      } label: {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "plus")
            .font(.system(size: 11, weight: .semibold))
          Text(L10n.AnnotateUI.addNewPreset)
            .lineLimit(1)
          Spacer(minLength: Spacing.xs)
        }
        .font(Typography.labelSmall)
        .foregroundColor(state.isCanvasPresetLimitReached ? SidebarColors.labelSecondary : SidebarColors.labelPrimary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(state.isCanvasPresetLimitReached)

      Divider()
        .padding(.vertical, 4)

      if state.canvasPresets.isEmpty {
        Text(L10n.AnnotateUI.noPresetsYet)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, 7)
      } else {
        ForEach(state.canvasPresets) { preset in
          presetDropdownRow(preset)
        }
      }
    }
    .padding(.vertical, 4)
    .frame(width: 240)
  }

  private func presetDropdownRow(_ preset: AnnotateCanvasPreset) -> some View {
    HStack(spacing: Spacing.xs) {
      Button {
        state.applyCanvasPreset(preset)
        isPresetDropdownPresented = false
      } label: {
        HStack(spacing: Spacing.xs) {
          Image(systemName: state.selectedCanvasPresetId == preset.id ? "checkmark" : "circle")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(state.selectedCanvasPresetId == preset.id ? .accentColor : SidebarColors.labelSecondary.opacity(0.7))

          Text(preset.name)
            .font(Typography.labelSmall)
            .foregroundColor(SidebarColors.labelPrimary)
            .lineLimit(1)
            .truncationMode(.tail)

          Spacer(minLength: Spacing.xs)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Button {
        handleDeletePreset(preset)
      } label: {
        Image(systemName: "trash")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(SidebarColors.labelSecondary)
          .frame(width: 18, height: 18)
      }
      .buttonStyle(.plain)
      .help(L10n.AnnotateUI.deletePresetHelp)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, 6)
  }

  private var updatePresetButton: some View {
    Button {
      handleUpdatePreset()
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.system(size: 11, weight: .semibold))
        Text(L10n.AnnotateUI.updatePreset)
          .font(Typography.labelSmall)
          .lineLimit(1)
        Spacer(minLength: Spacing.xs)
      }
      .foregroundColor(SidebarColors.labelPrimary)
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: Size.radiusSm)
          .fill(SidebarColors.itemDefault)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Size.radiusSm)
          .stroke(Color.orange.opacity(0.5), lineWidth: Size.strokeDefault)
      )
    }
    .buttonStyle(.plain)
    .help(L10n.AnnotateUI.updateSelectedPresetHelp)
  }

  private func handleCreatePreset() {
    if state.isCanvasPresetLimitReached {
      showPresetLimitAlert()
      return
    }

    guard let name = promptForPresetName(
      title: L10n.AnnotateUI.savePresetTitle,
      message: L10n.AnnotateUI.savePresetMessage,
      defaultValue: state.nextSuggestedCanvasPresetName
    ) else {
      return
    }

    switch state.saveCurrentCanvasAsPreset(name: name) {
    case .success:
      return
    case .limitReached:
      showPresetLimitAlert()
    case .invalidName:
      return
    case .unavailablePayload:
      showPresetUnavailableAlert()
    case .missingSelection:
      return
    }
  }

  private func handleUpdatePreset() {
    guard let preset = state.selectedCanvasPreset else { return }

    let alert = NSAlert()
    alert.messageText = L10n.AnnotateUI.updatePresetTitle
    alert.informativeText = L10n.AnnotateUI.updatePresetMessage(preset.name)
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.AnnotateUI.updatePreset)
    alert.addButton(withTitle: L10n.Common.cancel)

    guard alert.runModal() == .alertFirstButtonReturn else {
      return
    }

    switch state.updateSelectedCanvasPreset() {
    case .success:
      return
    case .unavailablePayload:
      showPresetUnavailableAlert()
    case .missingSelection, .invalidName, .limitReached:
      return
    }
  }

  private func handleDeletePreset(_ preset: AnnotateCanvasPreset) {
    let alert = NSAlert()
    alert.messageText = L10n.AnnotateUI.deletePresetTitle
    alert.informativeText = L10n.AnnotateUI.deletePresetMessage(preset.name)
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.Common.deleteAction)
    alert.addButton(withTitle: L10n.Common.cancel)

    if alert.runModal() == .alertFirstButtonReturn {
      _ = state.deleteCanvasPreset(id: preset.id)
    }
  }

  private func promptForPresetName(
    title: String,
    message: String,
    defaultValue: String
  ) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: L10n.Common.save)
    alert.addButton(withTitle: L10n.Common.cancel)

    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    textField.stringValue = defaultValue
    textField.placeholderString = L10n.AnnotateUI.presetNamePlaceholder
    alert.accessoryView = textField

    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else {
      return nil
    }

    let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  private func showPresetLimitAlert() {
    let alert = NSAlert()
    alert.messageText = L10n.AnnotateUI.presetLimitReachedTitle
    alert.informativeText = L10n.AnnotateUI.presetLimitReachedMessage
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.Common.ok)
    alert.runModal()
  }

  private func showPresetUnavailableAlert() {
    let alert = NSAlert()
    alert.messageText = L10n.AnnotateUI.unableToSavePresetTitle
    alert.informativeText = L10n.AnnotateUI.unableToSavePresetMessage
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.Common.ok)
    alert.runModal()
  }
  
  // MARK: - Sections
  
  private var gradientSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: L10n.Common.gradients)

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.backgroundColumns), spacing: GridConfig.gap) {
        ForEach(GradientPreset.allCases) { preset in
          GradientPresetButton(
            preset: preset,
            isSelected: state.backgroundStyle == .gradient(preset)
          ) {

            if state.padding <= 0 {
              state.padding = 24
            }

            state.backgroundStyle = .gradient(preset)
          }
        }
      }
    }
  }

  private var wallpaperSection: some View {
    SidebarWallpaperSection(state: state)
  }

  private var colorSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: L10n.Common.colors)
      CompactColorSwatchGrid(selectedColor: colorBinding)
    }
  }
  
  private var colorBinding: Binding<Color?> {
    Binding(
      get: {
        if case .solidColor(let color) = state.backgroundStyle {
          return color
        }
        return nil
      },
      set: { newColor in
        if let color = newColor {
          state.backgroundStyle = .solidColor(color)
        }
      }
    )
  }
  
  private var slidersSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      CompactSliderRow(
        label: L10n.Common.padding,
        value: Binding(
          get: { state.padding },
          set: { newValue in
            state.padding = newValue
            // Auto-apply white background when padding increases from 0
            if newValue > 0 && state.backgroundStyle == .none {
              state.backgroundStyle = .solidColor(.white)
            }
          }
        ),
        range: 0...300,
        onDragging: { isDragging, value in
          state.previewPadding = isDragging ? value : nil
        }
      )
      CompactSliderRow(
        label: L10n.Common.shadow,
        value: $state.shadowIntensity,
        range: 0...1,
        onDragging: { isDragging, value in
          state.previewShadowIntensity = isDragging ? value : nil
        }
      )
      CompactSliderRow(
        label: L10n.Common.corners,
        value: $state.cornerRadius,
        range: 0...60,
        onDragging: { isDragging, value in
          state.previewCornerRadius = isDragging ? value : nil
        }
      )
    }
  }
  
  private var alignmentSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: L10n.AnnotateUI.alignment)
      AlignmentGrid(selected: $state.imageAlignment, onAlignmentChange: { newAlignment in
        print("DEBUG [Alignment]: Callback fired with newAlignment = \(newAlignment)")
        print("DEBUG [Alignment]: Current padding = \(state.padding), backgroundStyle = \(state.backgroundStyle)")

        // Auto-apply padding when alignment changes from center
        if state.padding < 24 && newAlignment != .center {
          state.padding = 24
          print("DEBUG [Alignment]: Set padding to 24")
          // Also apply background if none
          if state.backgroundStyle == .none {
            state.backgroundStyle = .solidColor(.white)
            print("DEBUG [Alignment]: Set background to white")
          }
        }

        print("DEBUG [Alignment]: After - padding = \(state.padding), alignment = \(state.imageAlignment)")
      })
    }
  }
  
  // private var ratioSection: some View {
  //   VStack(alignment: .leading, spacing: 6) {
  //     SidebarSectionHeader(title: "Ratio")
  //     Picker("", selection: $state.aspectRatio) {
  //       ForEach(AspectRatioOption.allCases) { option in
  //         Text(option.rawValue).tag(option)
  //       }
  //     }
  //     .pickerStyle(.menu)
  //     .labelsHidden()
  //     .frame(maxWidth: .infinity, alignment: .leading)
  //   }
  // }
}

// MARK: - Compact Components

struct CompactColorSwatchGrid: View {
  @Binding var selectedColor: Color?

  private let colors: [Color] = [
    .red, .orange, .yellow, .green, .blue, .purple, .pink, .gray, .white, .black
  ]

  var body: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.colorColumns), spacing: GridConfig.gap) {
      ForEach(colors, id: \.self) { color in
        Button {
          selectedColor = color
        } label: {
          Circle()
            .fill(color)
            .colorSwatchStyle(isSelected: selectedColor == color)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

struct CompactSliderRow: View {
  let label: String
  @Binding var value: CGFloat
  let range: ClosedRange<CGFloat>
  var onDragging: ((Bool, CGFloat) -> Void)? = nil

  @State private var localValue: CGFloat = 0
  @State private var isDragging: Bool = false
  @State private var textValue: String = ""
  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(label)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
        Spacer()
        TextField("", text: $textValue)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary.opacity(0.9))
          .multilineTextAlignment(.trailing)
          .textFieldStyle(.plain)
          .frame(width: 36)
          .padding(.horizontal, Spacing.xs)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: Size.radiusXs)
              .fill(SidebarColors.itemDefault)
          )
          .focused($isTextFieldFocused)
          .onAppear {
            textValue = String(format: "%.0f", value)
          }
          .onChange(of: localValue) { newValue in
            if !isTextFieldFocused {
              textValue = String(format: "%.0f", newValue)
            }
          }
          .onChange(of: isTextFieldFocused) { focused in
            if !focused {
              applyTextValue()
            }
          }
          .onSubmit {
            applyTextValue()
            isTextFieldFocused = false
          }
      }
      Slider(
        value: $localValue,
        in: range,
        onEditingChanged: { editing in
          isDragging = editing
          if !editing {
            // Sync to binding only when drag ends
            value = localValue
            onDragging?(false, localValue)
          } else {
            // Drag started
            onDragging?(true, localValue)
          }
        }
      )
      .controlSize(.small)
    }
    .onAppear { localValue = value }
    .onChange(of: localValue) { newValue in
      // Update preview in real-time during drag
      if isDragging {
        onDragging?(true, newValue)
      }
    }
    .onChange(of: value) { newValue in
      // External changes sync to local (e.g., preset selection)
      if !isDragging { localValue = newValue }
    }
  }

  private func applyTextValue() {
    if let newValue = Double(textValue) {
      let clampedValue = min(max(CGFloat(newValue), range.lowerBound), range.upperBound)
      localValue = clampedValue
      value = clampedValue
      textValue = String(format: "%.0f", clampedValue)
    } else {
      textValue = String(format: "%.0f", localValue)
    }
  }
}
