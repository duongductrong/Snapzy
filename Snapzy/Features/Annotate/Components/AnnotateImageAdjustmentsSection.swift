//
//  AnnotateImageAdjustmentsSection.swift
//  Snapzy
//
//  Sidebar "Adjust" tab: filter preset grid (+ strength), then collapsible Light / Color /
//  Effects slider groups. Reset lives in `AnnotateImageAdjustmentsResetBar`, pinned below
//  the scroll view by the sidebar. Takes plain values so the Equatable sidebar only
//  re-renders when they change; live slider drags stay inside each row's own state.
//

import AppKit
import SwiftUI

struct AnnotateImageAdjustmentsSection: View {
  let state: AnnotateState
  let adjustments: ImageAdjustments
  let thumbnails: [ImageFilterPreset: NSImage]

  /// Filter grid columns: square tiles, rendered at their display size so 3 stay sharp.
  var presetColumnCount: Int = 3

  /// Comma-separated `ImageAdjustmentGroup` raw values the user collapsed.
  @AppStorage("annotate.adjust.collapsedGroups") private var collapsedGroupsRaw = ""

  private var presetColumns: [GridItem] {
    Array(
      repeating: GridItem(.flexible(minimum: 0), spacing: GridConfig.gap, alignment: .top),
      count: max(1, presetColumnCount)
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      filtersBlock
      ForEach(ImageAdjustmentGroup.allCases) { group in
        groupBlock(group)
      }
    }
    .onAppear {
      state.prepareImageFilterPresetThumbnailsIfNeeded()
    }
    .onDisappear {
      // A slider torn down mid-drag never reports its release; commit the step now.
      state.endImageAdjustmentGesture()
    }
  }

  // MARK: - Reset bar

  /// Exact compare: a preset at 0% strength renders nothing but is still selected.
  static func canReset(_ adjustments: ImageAdjustments) -> Bool {
    adjustments != .identity
  }

  // MARK: - Filters

  private var filtersBlock: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(L10n.AnnotateAdjust.filters)
        .font(Typography.labelMedium)
        .foregroundColor(SidebarColors.labelSecondary)

      LazyVGrid(columns: presetColumns, alignment: .leading, spacing: Spacing.sm) {
        ForEach(ImageFilterPreset.allCases) { preset in
          ImageFilterPresetTile(
            preset: preset,
            thumbnail: thumbnails[preset],
            isSelected: adjustments.preset == preset
          ) {
            state.selectImageFilterPreset(preset)
          }
        }
      }

      if adjustments.preset != .none {
        sliderRow(
          label: L10n.AnnotateAdjust.intensity,
          keyPath: \.presetIntensity,
          range: ImageAdjustments.presetIntensityRange,
          neutral: 100,
          track: .plain
        )
        .padding(.top, Spacing.xs)
      }
    }
  }

  // MARK: - Slider groups

  private func groupBlock(_ group: ImageAdjustmentGroup) -> some View {
    let isCollapsed = collapsedGroups.contains(group.rawValue)
    let isModified = group.isModified(in: adjustments)
    return VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(spacing: Spacing.xs) {
        Button {
          toggleCollapsed(group)
        } label: {
          HStack(spacing: Spacing.xs) {
            Image(systemName: "chevron.right")
              .font(.system(size: 8, weight: .bold))
              .rotationEffect(.degrees(isCollapsed ? 0 : 90))
              .frame(width: 10)
            Text(group.title)
              .font(Typography.labelMedium)
            if isModified {
              Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
            }
            Spacer(minLength: 0)
          }
          .foregroundColor(SidebarColors.labelSecondary)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.title)
        .accessibilityAddTraits(isCollapsed ? [] : .isSelected)

        if isModified {
          Button {
            state.resetImageAdjustmentGroup(group)
          } label: {
            Image(systemName: "arrow.counterclockwise")
              .font(.system(size: 9, weight: .semibold))
              .foregroundColor(SidebarColors.labelTertiary)
              .frame(width: 16, height: 16)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help(L10n.AnnotateAdjust.groupResetHelp)
          .accessibilityLabel(L10n.AnnotateAdjust.groupResetHelp)
        }
      }

      if !isCollapsed {
        ForEach(group.parameters) { parameter in
          sliderRow(
            label: parameter.label,
            keyPath: parameter.keyPath,
            range: parameter.range,
            neutral: 0,
            track: AdjustmentSliderTrack(parameter)
          )
        }
      }
    }
  }

  private var collapsedGroups: Set<String> {
    Set(collapsedGroupsRaw.split(separator: ",").map(String.init))
  }

  private func toggleCollapsed(_ group: ImageAdjustmentGroup) {
    var groups = collapsedGroups
    if groups.contains(group.rawValue) {
      groups.remove(group.rawValue)
    } else {
      groups.insert(group.rawValue)
    }
    collapsedGroupsRaw = groups.sorted().joined(separator: ",")
  }

  /// One slider drag = one undo step: live values go through the gesture API, the final
  /// value commits on release. Typed values and double-click resets commit immediately.
  private func sliderRow(
    label: String,
    keyPath: WritableKeyPath<ImageAdjustments, Double>,
    range: ClosedRange<Double>,
    neutral: Double,
    track: AdjustmentSliderTrack
  ) -> some View {
    AdjustmentSliderRow(
      label: label,
      value: adjustments[keyPath: keyPath],
      range: range,
      neutral: neutral,
      track: track
    ) { newValue, phase in
      var updated = state.liveImageAdjustments
      updated[keyPath: keyPath] = newValue.rounded()
      switch phase {
      case .dragging:
        state.updateImageAdjustmentGesture(updated)
      case .released:
        state.updateImageAdjustmentGesture(updated)
        state.endImageAdjustmentGesture()
      case .committed:
        state.setImageAdjustments(updated)
      }
    }
  }
}

/// Full-width Liquid Glass Reset pinned to the bottom of the Adjust tab (outside the scroll
/// view, so it stays reachable however far the sliders scroll).
struct AnnotateImageAdjustmentsResetBar: View {
  let state: AnnotateState
  let adjustments: ImageAdjustments

  var body: some View {
    let canReset = AnnotateImageAdjustmentsSection.canReset(adjustments)
    Button {
      state.resetImageAdjustments()
    } label: {
      Label(L10n.AnnotateAdjust.reset, systemImage: "arrow.counterclockwise")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))
    .disabled(!canReset)
    .opacity(canReset ? 1 : 0.5)
    .help(L10n.AnnotateAdjust.resetHelp)
  }
}

// MARK: - Slider

/// Track look: plain fills from the neutral point; gradient tracks preview the color shift.
enum AdjustmentSliderTrack: Equatable {
  case plain
  case gradient([Color])

  init(_ parameter: ImageAdjustmentParameter) {
    switch parameter {
    case .temperature:
      self = .gradient([Color(red: 0.33, green: 0.58, blue: 1.0), Color(white: 0.82), Color(red: 1.0, green: 0.76, blue: 0.25)])
    case .tint:
      self = .gradient([Color(red: 0.36, green: 0.80, blue: 0.38), Color(white: 0.82), Color(red: 0.88, green: 0.38, blue: 0.84)])
    case .saturation, .vibrance:
      self = .gradient([Color(white: 0.6), Color(red: 0.95, green: 0.45, blue: 0.30)])
    case .exposure, .brightness, .whites, .blacks, .highlights, .shadows:
      self = .gradient([Color(white: 0.18), Color(white: 0.95)])
    default:
      self = .plain
    }
  }
}

/// Compact color-grading slider: label, signed value field, custom track with a neutral tick.
/// The drag lives in local state, so only this row re-renders while it moves.
struct AdjustmentSliderRow: View {
  enum Phase {
    /// Live drag value (preview only, no undo step).
    case dragging
    /// Drag ended on this value (one undo step).
    case released
    /// Discrete change: typed value, double-click reset, keyboard step.
    case committed
  }

  let label: String
  let value: Double
  let range: ClosedRange<Double>
  let neutral: Double
  let track: AdjustmentSliderTrack
  let onChange: (Double, Phase) -> Void

  @State private var dragValue: Double?
  @State private var textValue = ""
  /// Text last written into the field by the row; blur only commits when the user changed it.
  @State private var programmaticText = ""
  @State private var grabOffset: CGFloat = 0
  @State private var isHoveringTrack = false
  @FocusState private var isTextFieldFocused: Bool

  private static let trackHeight: CGFloat = 4
  private static let thumbDiameter: CGFloat = 12
  private static let rowHeight: CGFloat = 16

  private var displayedValue: Double { dragValue ?? value }
  private var isBipolar: Bool { range.lowerBound < 0 }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: Spacing.xs) {
        Text(label)
          .font(Typography.labelSmall)
          .foregroundColor(displayedValue == neutral ? SidebarColors.labelSecondary : SidebarColors.labelPrimary)
          .onTapGesture(count: 2) { onChange(neutral, .committed) }
          .help(L10n.AnnotateAdjust.sliderResetHelp)
        Spacer(minLength: 0)
        valueField
      }
      trackView
        .frame(height: Self.rowHeight)
    }
    .onAppear { setText(format(value)) }
    .onChange(of: displayedValue) { newValue in
      if !isTextFieldFocused { setText(format(newValue)) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(format(displayedValue))
    .accessibilityAdjustableAction { direction in
      let step = (range.upperBound - range.lowerBound) / 40
      switch direction {
      case .increment: onChange(clamp(value + step), .committed)
      case .decrement: onChange(clamp(value - step), .committed)
      @unknown default: break
      }
    }
  }

  private var valueField: some View {
    TextField("", text: $textValue)
      .font(Typography.labelSmall.monospacedDigit())
      .foregroundColor(SidebarColors.labelSecondary.opacity(0.9))
      .multilineTextAlignment(.trailing)
      .textFieldStyle(.plain)
      .frame(width: 32)
      .padding(.horizontal, Spacing.xs)
      .padding(.vertical, 1)
      .background(
        Radius.rect(Radius.control(forHeight: AnnotateSidebarMetrics.inlineFieldHeight))
          .fill(SidebarColors.itemDefault)
      )
      .focused($isTextFieldFocused)
      .onChange(of: isTextFieldFocused) { focused in
        if focused {
          setText(format(displayedValue))
        } else {
          applyTextValue()
          // The value may have moved (drag, reset, undo) while the field held focus.
          setText(format(displayedValue))
        }
      }
      .onSubmit {
        applyTextValue()
        isTextFieldFocused = false
      }
  }

  private var trackView: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let usable = max(1, width - Self.thumbDiameter)
      let thumbX = Self.thumbDiameter / 2 + fraction(displayedValue) * usable
      let neutralX = Self.thumbDiameter / 2 + fraction(neutral) * usable

      ZStack(alignment: .leading) {
        trackBackground
          .frame(height: Self.trackHeight)
          .clipShape(Capsule())

        if case .plain = track {
          Capsule()
            .fill(Color.accentColor)
            .frame(width: abs(thumbX - neutralX), height: Self.trackHeight)
            .offset(x: min(thumbX, neutralX))
        }

        if isBipolar {
          Rectangle()
            .fill(SidebarColors.labelTertiary)
            .frame(width: 1, height: 8)
            .offset(x: neutralX - 0.5)
        }

        Circle()
          .fill(Color.white)
          .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
          .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
          .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
          .scaleEffect(dragValue != nil ? 1.15 : (isHoveringTrack ? 1.05 : 1))
          .offset(x: thumbX - Self.thumbDiameter / 2)
      }
      .frame(width: width, height: proxy.size.height)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { gesture in
            if dragValue == nil {
              // Grabbing the thumb keeps its value; clicking the bare track jumps there.
              let offset = gesture.startLocation.x - thumbX
              grabOffset = abs(offset) <= Self.thumbDiameter / 2 + 2 ? offset : 0
            }
            let newValue = value(atX: gesture.location.x - grabOffset, usable: usable)
            guard newValue != dragValue else { return }
            dragValue = newValue
            onChange(newValue, .dragging)
          }
          .onEnded { gesture in
            let newValue = value(atX: gesture.location.x - grabOffset, usable: usable)
            dragValue = nil
            onChange(newValue, .released)
          }
      )
      .onHover { isHoveringTrack = $0 }
    }
  }

  @ViewBuilder
  private var trackBackground: some View {
    switch track {
    case .plain:
      Rectangle().fill(Color.primary.opacity(0.12))
    case .gradient(let colors):
      LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
        .opacity(0.85)
    }
  }

  // MARK: Helpers

  private func fraction(_ value: Double) -> CGFloat {
    let span = range.upperBound - range.lowerBound
    guard span > 0 else { return 0 }
    return CGFloat((clamp(value) - range.lowerBound) / span)
  }

  private func value(atX x: CGFloat, usable: CGFloat) -> Double {
    let fraction = Double(min(max((x - Self.thumbDiameter / 2) / usable, 0), 1))
    var newValue = (range.lowerBound + fraction * (range.upperBound - range.lowerBound)).rounded()
    // Light detent at the neutral point so it is easy to land back on "unchanged".
    if abs(newValue - neutral) <= 1 { newValue = neutral }
    return newValue
  }

  private func clamp(_ value: Double) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
  }

  private func format(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    return isBipolar && rounded > 0 ? "+\(rounded)" : "\(rounded)"
  }

  private func setText(_ text: String) {
    programmaticText = text
    textValue = text
  }

  private func applyTextValue() {
    // Untouched field: never let stale text overwrite a value changed elsewhere.
    guard textValue != programmaticText else { return }
    guard let typed = Double(textValue.trimmingCharacters(in: .whitespaces)), typed.isFinite else {
      setText(format(displayedValue))
      return
    }
    let newValue = clamp(typed.rounded())
    setText(format(newValue))
    if newValue != value { onChange(newValue, .committed) }
  }
}

// MARK: - Filter tile

private struct ImageFilterPresetTile: View {
  let preset: ImageFilterPreset
  let thumbnail: NSImage?
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        // A fixed 1:1 clear box sizes the tile from the column width; the thumbnail (rendered
        // at exactly this ratio) only fills it as an overlay, so it can never push past its cell.
        Color.clear
          .aspectRatio(1, contentMode: .fit)
          .frame(maxWidth: .infinity)
          .background(SidebarColors.itemDefault)
          .overlay {
            if let thumbnail {
              Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .transition(.opacity)
            } else {
              ProgressView()
                .controlSize(.mini)
            }
          }
          .clipShape(Radius.rect(Radius.tile))
          .overlay {
            Radius.rect(Radius.tile)
              .fill(isHovering && !isSelected ? Color.white.opacity(0.08) : Color.clear)
          }
          .overlay {
            Radius.rect(Radius.tile)
              .strokeBorder(borderColor, lineWidth: isSelected ? Size.strokeSelected : Size.strokeDefault)
          }
          .overlay(alignment: .topTrailing) {
            if isSelected {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.accentColor)
                .shadow(color: .black.opacity(0.3), radius: 1)
                .padding(3)
            }
          }
          .animation(.easeOut(duration: 0.15), value: thumbnail != nil)

        Text(preset.displayName)
          .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
          .foregroundColor(isSelected ? SidebarColors.labelPrimary : SidebarColors.labelSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(preset.displayName)
    .accessibilityLabel(preset.displayName)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var borderColor: Color {
    if isSelected { return SidebarColors.borderSelected }
    if isHovering { return SidebarColors.borderHover }
    return Color.primary.opacity(0.08)
  }
}
