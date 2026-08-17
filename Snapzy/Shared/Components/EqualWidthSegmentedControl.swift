//
//  EqualWidthSegmentedControl.swift
//  Snapzy
//
//  A segmented control whose segments all share one width.
//

import AppKit
import SwiftUI

/// SwiftUI's `.pickerStyle(.segmented)` sizes every segment to its own label,
/// so a two-item picker comes out lopsided — and the imbalance shifts with each
/// translation. `NSSegmentedControl` can distribute segments equally and SwiftUI
/// has no way to ask for it, so this is the thin bridge that does.
///
/// Sizing stays intrinsic: with `.fillEqually`, `sizeToFit()` widens every
/// segment to the widest label, which is the right width in any language.
struct EqualWidthSegmentedControl: NSViewRepresentable {
  let titles: [String]
  @Binding var selectedIndex: Int

  func makeNSView(context: Context) -> NSSegmentedControl {
    let control = NSSegmentedControl(
      labels: titles,
      trackingMode: .selectOne,
      target: context.coordinator,
      action: #selector(Coordinator.selectionChanged(_:))
    )
    control.segmentStyle = .automatic
    control.segmentDistribution = .fillEqually
    control.selectedSegment = selectedIndex
    control.sizeToFit()
    control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    control.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    return control
  }

  func updateNSView(_ control: NSSegmentedControl, context: Context) {
    context.coordinator.onChange = { selectedIndex = $0 }

    var needsResize = false
    if control.segmentCount != titles.count {
      control.segmentCount = titles.count
      needsResize = true
    }
    for (index, title) in titles.enumerated() where index < control.segmentCount {
      if control.label(forSegment: index) != title {
        control.setLabel(title, forSegment: index)
        needsResize = true
      }
    }
    if needsResize {
      control.sizeToFit()
    }

    let clamped = min(max(selectedIndex, 0), control.segmentCount - 1)
    if control.selectedSegment != clamped {
      control.selectedSegment = clamped
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  final class Coordinator: NSObject {
    var onChange: (Int) -> Void = { _ in }

    @objc func selectionChanged(_ sender: NSSegmentedControl) {
      onChange(sender.selectedSegment)
    }
  }
}
