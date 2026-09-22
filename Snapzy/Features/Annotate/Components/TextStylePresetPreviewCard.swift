import SwiftUI

/// A real render of a saved text style, floated on hover.
///
/// The preset buttons in the toolbar are colour dots with a name in a tooltip,
/// which cannot convey size, face, curvature, or whether the style has a tail.
/// This card draws the style from its own stored properties — including a
/// callout tail — so the user sees the result before applying it.
struct TextStylePresetPreviewCard: View {
  let name: String
  let properties: AnnotationProperties

  /// Reuse the shared bubble geometry so the preview and the canvas agree.
  private static let bubbleWidth: CGFloat = 150
  /// Headroom under the bubble so a callout tail is not clipped.
  private static let tailRoom: CGFloat = 26

  /// A saved 36 pt style would blow the card up, so the sample is drawn at a
  /// bounded size. The relative difference between presets still shows.
  private var previewFontSize: CGFloat {
    min(max(properties.fontSize, 11), 17)
  }

  private var insets: CGSize {
    TextBubbleGeometry.contentInsets(for: properties.textPresentation, fontSize: previewFontSize)
  }

  private var isCallout: Bool { properties.textPresentation == .callout }

  private var bubbleHeight: CGFloat {
    ceil(previewFontSize * 1.4) + insets.height * 2
  }

  /// Placed below the bubble in the card's own (top-left origin) space, which
  /// is where `attachmentSide` reads as a bottom-edge attachment.
  private var tailTarget: CGPoint? {
    guard isCallout else { return nil }
    return CGPoint(x: Self.bubbleWidth * 0.74, y: bubbleHeight + Self.tailRoom * 0.7)
  }

  private var hasVisibleBorder: Bool {
    properties.isBorderEnabled
      && !AnnotateColorPaletteStore.isClear(properties.textBorderColor)
      && properties.textBorderWidth > 0
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(name)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.primary)

      sample
        .frame(
          width: Self.bubbleWidth,
          height: bubbleHeight + (isCallout ? Self.tailRoom : 0),
          alignment: .top
        )

      Text(detail)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(10)
    .frame(width: 190, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 3)
  }

  private var sample: some View {
    ZStack(alignment: .topLeading) {
      if properties.textPresentation != .plain {
        let bubble = TextBubbleShape(
          tailTarget: tailTarget,
          fontSize: previewFontSize,
          cornerRadius: properties.cornerRadius
        )
        bubble
          .fill(properties.fillColor)
          .frame(width: Self.bubbleWidth, height: bubbleHeight)
        if hasVisibleBorder {
          bubble
            .stroke(properties.textBorderColor, lineWidth: max(1, properties.textBorderWidth))
            .frame(width: Self.bubbleWidth, height: bubbleHeight)
        }
      }

      Text(L10n.AnnotateUI.textStylePreviewSample)
        .font(Font(AnnotateTextLayout.font(size: previewFontSize, fontName: properties.fontName)))
        .foregroundStyle(properties.strokeColor)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, insets.width)
        .padding(.vertical, insets.height)
        .frame(width: Self.bubbleWidth, height: bubbleHeight)
    }
    .frame(width: Self.bubbleWidth, height: bubbleHeight, alignment: .topLeading)
  }

  private var detail: String {
    var parts = [properties.textPresentation.helpText]
    parts.append(String(format: L10n.AnnotateUI.textStylePreviewSize, Int(properties.fontSize.rounded())))
    if !properties.fontName.isEmpty {
      parts.append(AnnotateTextLayout.textFontDisplayName(properties.fontName))
    }
    return parts.joined(separator: " · ")
  }
}

/// Wraps a saved-style button so hovering it floats `TextStylePresetPreviewCard`.
///
/// Follows the app's existing hover-tooltip pattern (see `HintModifier`) so the
/// popover behaves the same as every other tooltip in the window. The card does
/// not take hit testing, so moving the pointer onto it does not dismiss it.
struct TextStylePresetHoverPreview<Content: View>: View {
  let name: String
  let properties: AnnotationProperties
  @ViewBuilder var content: () -> Content

  @State private var isHovering = false

  var body: some View {
    content()
      .onHover { hovering in
        isHovering = hovering
      }
      .popover(isPresented: $isHovering, arrowEdge: .bottom) {
        TextStylePresetPreviewCard(name: name, properties: properties)
          .allowsHitTesting(false)
      }
  }
}
