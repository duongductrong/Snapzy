//
//  AnnotateState+Stamp.swift
//  Snapzy
//
//  Stamp tool: creation defaults and quick-properties edits for selected stamps.
//  Tool defaults live in `AnnotateStampStore` (shared by every editor surface).
//

import CoreGraphics
import Foundation

extension AnnotateState {
  // MARK: Creation

  var stampForNewAnnotation: StampAnnotation {
    AnnotateStampStore.shared.currentStamp
  }

  var stampDefaultSize: CGFloat {
    AnnotateStampStore.shared.size
  }

  var stampDefaultOpacity: CGFloat {
    AnnotateStampStore.shared.opacity
  }

  /// Remembers what was placed so it heads the Recent row.
  func noteStampPlaced(_ item: AnnotationItem) {
    guard case .stamp(let stamp) = item.type else { return }
    AnnotateStampStore.shared.noteUsed(stamp.content)
  }

  // MARK: Quick properties

  /// Selected stamps the quick properties bar edits; empty means it edits tool defaults.
  var selectedStampAnnotations: [AnnotationItem] {
    guard editorMode == .annotate else { return [] }
    return selectedAnnotations.filter {
      if case .stamp = $0.type { return true }
      return false
    }
  }

  var quickPropertiesSupportsStamp: Bool {
    quickPropertiesTool == .stamp
  }

  /// The stamp shown on the picker button: the selected one (Selection tool), else what the
  /// next click places.
  var quickStampContent: StampContent {
    guard !stampToolIsActive else { return AnnotateStampStore.shared.current }
    for item in selectedStampAnnotations {
      if case .stamp(let stamp) = item.type { return stamp.content }
    }
    return AnnotateStampStore.shared.current
  }

  var quickStampSize: CGFloat {
    guard let item = selectedStampAnnotations.first, case .stamp(let stamp) = item.type else {
      return AnnotateStampStore.shared.size
    }
    let fitted = AnnotateStampRenderer.fittedRect(for: stamp.content, in: item.bounds)
    return max(fitted.width, fitted.height)
  }

  var quickStampOpacity: CGFloat {
    selectedStampAnnotations.first?.properties.opacity ?? AnnotateStampStore.shared.opacity
  }

  var quickStampIsStickerStyle: Bool {
    guard let item = selectedStampAnnotations.first, case .stamp(let stamp) = item.type else {
      return AnnotateStampStore.shared.isStickerStyle
    }
    return stamp.isStickerStyle
  }

  /// While the Stamp tool is active, quick edits also become the defaults for the next stamp
  /// (the item just placed is auto-selected, and the next one should match it).
  private var stampToolIsActive: Bool {
    selectedTool == .stamp
  }

  /// Picks the stamp for new placements. With another tool active (e.g. Selection), selected
  /// stamps switch to it in one undo step, keeping their center and long side. With the Stamp
  /// tool active it never swaps the stamp just placed.
  func chooseStamp(_ content: StampContent) {
    let store = AnnotateStampStore.shared
    store.choose(content)
    guard !stampToolIsActive else { return }
    updateSelectedStamps { item, stamp in
      let fitted = AnnotateStampRenderer.fittedRect(for: stamp.content, in: item.bounds)
      stamp.content = content
      item.bounds = AnnotateStampRenderer.bounds(
        for: content,
        size: max(fitted.width, fitted.height),
        centeredAt: CGPoint(x: item.bounds.midX, y: item.bounds.midY)
      )
    }
  }

  func setQuickStampSize(_ size: CGFloat) {
    let clamped = min(max(size, AnnotateStampStore.sizeRange.lowerBound), AnnotateStampStore.sizeRange.upperBound)
    if stampToolIsActive || selectedStampAnnotations.isEmpty {
      AnnotateStampStore.shared.size = clamped
    }
    updateSelectedStamps(recordsUndo: { AnnotateStampStore.shared.shouldRecordSliderUndo() }) { item, stamp in
      item.bounds = AnnotateStampRenderer.bounds(
        for: stamp.content,
        size: clamped,
        centeredAt: CGPoint(x: item.bounds.midX, y: item.bounds.midY)
      )
    }
  }

  func setQuickStampOpacity(_ opacity: CGFloat) {
    let clamped = min(max(opacity, AnnotateStampStore.opacityRange.lowerBound), AnnotateStampStore.opacityRange.upperBound)
    if stampToolIsActive || selectedStampAnnotations.isEmpty {
      AnnotateStampStore.shared.opacity = clamped
    }
    updateSelectedStamps(recordsUndo: { AnnotateStampStore.shared.shouldRecordSliderUndo() }) { item, _ in
      item.properties.opacity = clamped
    }
  }

  func setQuickStampStickerStyle(_ isStickerStyle: Bool) {
    if stampToolIsActive || selectedStampAnnotations.isEmpty {
      AnnotateStampStore.shared.isStickerStyle = isStickerStyle
    }
    updateSelectedStamps { _, stamp in
      stamp.isStickerStyle = isStickerStyle
    }
  }

  /// Applies `change` to every selected stamp. When something actually changes, records an
  /// undo checkpoint first if `recordsUndo` says so.
  private func updateSelectedStamps(
    recordsUndo: () -> Bool = { true },
    _ change: (inout AnnotationItem, inout StampAnnotation) -> Void
  ) {
    let ids = Set(selectedStampAnnotations.map(\.id))
    guard !ids.isEmpty else { return }
    var updated = annotations
    var didChange = false
    for index in updated.indices where ids.contains(updated[index].id) {
      guard case .stamp(var stamp) = updated[index].type else { continue }
      var item = updated[index]
      change(&item, &stamp)
      item.type = .stamp(stamp)
      if item.bounds != updated[index].bounds
        || item.properties != updated[index].properties
        || item.type != updated[index].type {
        updated[index] = item
        didChange = true
      }
    }
    guard didChange else { return }
    if recordsUndo() { saveState() }
    annotations = updated
    hasUnsavedChanges = true
  }
}
