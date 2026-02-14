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
  @FocusState private var isFocused: Bool

  // MARK: - Constants

  private let minTextFieldWidth: CGFloat = 60
  private let textPadding: CGFloat = 4

  var body: some View {
    GeometryReader { geometry in
      if let editingId = state.editingTextAnnotationId,
         let annotation = state.annotations.first(where: { $0.id == editingId }),
         case .text(let currentText) = annotation.type {

        let displayBounds = calculateDisplayBounds(annotation.bounds, in: geometry.size)
        let fontSize = max(annotation.properties.fontSize * scale, 10)

        // Text input field positioned exactly at annotation bounds
        TextField("", text: $editingText)
          .textFieldStyle(.plain)
          .font(.system(size: fontSize))
          .foregroundColor(annotation.properties.strokeColor)
          .multilineTextAlignment(.leading)
          .frame(
            width: max(displayBounds.width, minTextFieldWidth),
            height: displayBounds.height,
            alignment: .leading
          )
          .padding(.horizontal, textPadding)
          .background(
            // Subtle editing indicator - transparent with light border
            RoundedRectangle(cornerRadius: 2)
              .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
              .background(
                RoundedRectangle(cornerRadius: 2)
                  .fill(Color.primary.opacity(0.05))
              )
          )
          .focused($isFocused)
          .position(
            x: displayBounds.minX + max(displayBounds.width, minTextFieldWidth) / 2,
            y: displayBounds.minY + displayBounds.height / 2
          )
          .onAppear {
            editingText = currentText
            // Delay focus to ensure view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
              isFocused = true
            }
          }
          .onSubmit {
            commitEdit(id: editingId)
          }
          .onExitCommand {
            cancelEdit()
          }
          .onChange(of: isFocused) { newValue in
            if !newValue && state.editingTextAnnotationId == editingId {
              commitEdit(id: editingId)
            }
          }
      }
    }
  }

  /// Convert image bounds to display coordinates
  /// The overlay frame matches the image frame, so we just need to:
  /// 1. Scale the bounds
  /// 2. Flip Y axis (AppKit bottom-left origin → SwiftUI top-left origin)
  private func calculateDisplayBounds(_ imageBounds: CGRect, in containerSize: CGSize) -> CGRect {
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
