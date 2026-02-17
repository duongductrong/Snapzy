//
//  AnnotationToolbarContentBuilder.swift
//  Snapzy
//
//  Builds the NSVisualEffectView + NSHostingView content for the annotation toolbar.
//  Extracted from RecordingAnnotationToolbarWindow for modularity.
//

import AppKit
import SwiftUI

/// Accepts first mouse so the toolbar is draggable without needing a focus click first.
class FirstMouseVisualEffectView: NSVisualEffectView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Result of building toolbar content — holds references the window needs.
struct AnnotationToolbarContent {
  let effectView: NSVisualEffectView
  let hostingView: NSHostingView<AnyView>
  let fittingSize: CGSize
}

@MainActor
enum AnnotationToolbarContentBuilder {

  /// Build the visual-effect backdrop + SwiftUI hosting view for a given direction.
  static func build(
    state: RecordingAnnotationState,
    direction: AnnotationToolbarDirection
  ) -> AnnotationToolbarContent {
    let view = RecordingAnnotationToolbarView(state: state, direction: direction)
    let themed = view.preferredColorScheme(ThemeManager.shared.systemAppearance)
    let hosting = NSHostingView(rootView: AnyView(themed))
    hosting.translatesAutoresizingMaskIntoConstraints = false

    let effect = FirstMouseVisualEffectView()
    effect.material = .hudWindow
    effect.state = .active
    effect.blendingMode = .behindWindow
    effect.wantsLayer = true
    effect.layer?.cornerRadius = ToolbarConstants.toolbarCornerRadius
    effect.layer?.masksToBounds = true

    hosting.layer?.backgroundColor = .clear
    effect.addSubview(hosting)
    NSLayoutConstraint.activate([
      hosting.topAnchor.constraint(equalTo: effect.topAnchor),
      hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
      hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
      hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
    ])

    let fittingSize = hosting.fittingSize
    effect.frame = CGRect(origin: .zero, size: fittingSize)

    return AnnotationToolbarContent(
      effectView: effect,
      hostingView: hosting,
      fittingSize: fittingSize
    )
  }

  /// Compute the fitting size for a given direction without building the full view tree.
  static func fittingSize(
    state: RecordingAnnotationState,
    direction: AnnotationToolbarDirection
  ) -> CGSize {
    let view = RecordingAnnotationToolbarView(state: state, direction: direction)
    let themed = view.preferredColorScheme(ThemeManager.shared.systemAppearance)
    let hosting = NSHostingView(rootView: AnyView(themed))
    return hosting.fittingSize
  }
}
