//
//  TextEditOverlay.swift
//  Snapzy
//
//  SwiftUI overlay for inline text annotation editing
//

import SwiftUI

/// Overlay for editing text annotations inline on the canvas
struct TextEditOverlay: View {
  @ObservedObject var state: AnnotateState
  let scale: CGFloat
  let imageSize: CGSize

  @State private var editingText: String = ""
  @State private var textHeight: CGFloat = 28
  @FocusState private var isFocused: Bool

  // MARK: - Constants

  private let minTextFieldWidth: CGFloat = AnnotateTextLayout.minWidth
  /// TextEditor has internal horizontal insets (~5pt each side) that reduce
  /// the actual text rendering width compared to the frame width.
  /// We must subtract these when measuring to predict wrap points correctly.
  private let textEditorHorizontalInsets: CGFloat = 10
  /// Extra vertical padding for TextEditor's internal chrome (top/bottom insets)
  private let textEditorVerticalPadding: CGFloat = 4

  var body: some View {
    GeometryReader { _ in
      if let editingId = state.editingTextAnnotationId,
         let annotation = state.annotations.first(where: { $0.id == editingId }),
         case .text(let currentText) = annotation.type {

        let displayBounds = calculateDisplayBounds(annotation.bounds)
        let fontSize = max(annotation.properties.fontSize * scale, 10)
        let fieldWidth = max(displayBounds.width, minTextFieldWidth)
        // Use measured textHeight which accounts for TextEditor's narrower
        // rendering width, plus vertical padding for TextEditor's chrome
        let fieldHeight = max(textHeight + textEditorVerticalPadding, displayBounds.height)

        // Multiline text editor positioned at annotation bounds (top-left anchored)
        TextEditor(text: $editingText)
          .font(.system(size: fontSize))
          .foregroundColor(annotation.properties.strokeColor)
          .scrollContentBackground(.hidden)
          .scrollDisabled(true)
          .frame(
            width: fieldWidth,
            height: fieldHeight,
            alignment: .topLeading
          )
          .background(Color.clear)
          .focused($isFocused)
          .position(
            x: displayBounds.minX + fieldWidth / 2,
            y: displayBounds.minY + fieldHeight / 2
          )
          .onAppear {
            editingText = currentText
            recalculateHeight(text: currentText, fontSize: fontSize, width: fieldWidth)
            // Delay focus to ensure view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
              isFocused = true
            }
          }
          .onExitCommand {
            cancelEdit()
          }
          .onChange(of: editingText) { newValue in
            recalculateHeight(text: newValue, fontSize: fontSize, width: fieldWidth)
            // Live-update annotation text and bounds
            if let editingId = state.editingTextAnnotationId {
              state.updateAnnotationText(id: editingId, text: newValue)
            }
          }
          .onChange(of: isFocused) { newValue in
            if !newValue && state.editingTextAnnotationId == editingId {
              commitEdit(id: editingId)
            }
          }
      }
    }
  }

  /// Recalculate editor height based on wrapped text content.
  /// We subtract TextEditor's internal horizontal insets from the measurement
  /// width so that wrap predictions match the actual narrower rendering area.
  private func recalculateHeight(text: String, fontSize: CGFloat, width: CGFloat) {
    let effectiveWidth = max(width - textEditorHorizontalInsets, minTextFieldWidth)
    textHeight = AnnotateTextLayout.measuredHeight(
      text: text,
      font: AnnotateTextLayout.font(size: fontSize),
      constrainedWidth: effectiveWidth
    )
  }

  /// Convert image bounds to display coordinates
  /// The parent view supplies a frame that matches the full image display size.
  /// Crop clipping and offset are handled by AnnotateCanvasView, so we only:
  /// 1. Scale the bounds
  /// 2. Flip Y axis (AppKit bottom-left origin → SwiftUI top-left origin)
  private func calculateDisplayBounds(_ imageBounds: CGRect) -> CGRect {
    // Scale the bounds
    let scaledX = imageBounds.origin.x * scale
    let scaledWidth = imageBounds.width * scale
    let scaledHeight = imageBounds.height * scale

    // Flip Y axis: AppKit uses bottom-left origin, SwiftUI uses top-left
    // In AppKit: y=0 is bottom, y increases upward
    // In SwiftUI: y=0 is top, y increases downward
    let flippedY = (imageSize.height - imageBounds.origin.y - imageBounds.height) * scale

    return CGRect(
      x: scaledX,
      y: flippedY,
      width: scaledWidth,
      height: scaledHeight
    )
  }

  private func commitEdit(id: UUID) {
    let trimmedText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmedText.isEmpty {
      // Delete annotation if text is empty
      state.saveState()
      state.annotations.removeAll { $0.id == id }
      state.selectedAnnotationId = nil
    } else {
      state.saveState()
      state.updateAnnotationText(id: id, text: trimmedText)
    }
    state.editingTextAnnotationId = nil
  }

  private func cancelEdit() {
    // If it was a new annotation with empty text, delete it
    if let editingId = state.editingTextAnnotationId,
       let annotation = state.annotations.first(where: { $0.id == editingId }),
       case .text(let text) = annotation.type,
       text.isEmpty {
      state.annotations.removeAll { $0.id == editingId }
      state.selectedAnnotationId = nil
    }
    state.editingTextAnnotationId = nil
  }
}
