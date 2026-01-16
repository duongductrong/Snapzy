//
//  TextEditOverlay.swift
//  ZapShot
//
//  SwiftUI overlay for inline text annotation editing
//

import SwiftUI

/// Overlay for editing text annotations inline on the canvas
struct TextEditOverlay: View {
  @ObservedObject var state: AnnotateState
  let scale: CGFloat
  let imageOffset: CGPoint
  let imageSize: CGSize

  @State private var editingText: String = ""
  @FocusState private var isFocused: Bool

  // MARK: - Constants

  private let minTextFieldWidth: CGFloat = 80 // Minimum comfortable typing width

  var body: some View {
    if let editingId = state.editingTextAnnotationId,
       let annotation = state.annotations.first(where: { $0.id == editingId }),
       case .text(let currentText) = annotation.type {

      let displayBounds = calculateDisplayBounds(annotation.bounds)
      let fontSize = annotation.properties.fontSize * scale

      TextField("Type here...", text: $editingText)
        .textFieldStyle(.plain)
        .font(.system(size: max(fontSize, 12)))
        .foregroundColor(Color(annotation.properties.strokeColor))
        .padding(.horizontal, 4)
        .frame(minWidth: max(displayBounds.width, minTextFieldWidth))
        .background(
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.9))
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        )
        .focused($isFocused)
        .position(
          x: displayBounds.midX,
          y: displayBounds.midY
        )
        .onAppear {
          editingText = currentText
          isFocused = true
        }
        .onSubmit {
          commitEdit(id: editingId)
        }
        .onExitCommand {
          cancelEdit()
        }
        .onChange(of: isFocused) { _, newValue in
          // Commit when focus is lost
          if !newValue && state.editingTextAnnotationId == editingId {
            commitEdit(id: editingId)
          }
        }
    }
  }

  /// Convert image bounds to display coordinates within the canvas
  /// - Parameter imageBounds: Bounds in image coordinate space (bottom-left origin, AppKit)
  /// - Returns: Bounds in display coordinate space (top-left origin, SwiftUI)
  private func calculateDisplayBounds(_ imageBounds: CGRect) -> CGRect {
    // Coordinate system transformation:
    // - Image coordinates: bottom-left origin (AppKit)
    // - Display coordinates: top-left origin (SwiftUI)

    let displayX = imageBounds.origin.x * scale + imageOffset.x + imageSize.width / 2

    // Flip Y: convert from bottom-left to top-left origin
    let flippedY = imageSize.height - imageBounds.origin.y - imageBounds.height
    let displayY = flippedY * scale + imageOffset.y + imageSize.height / 2

    let rect = CGRect(
      x: displayX,
      y: displayY,
      width: imageBounds.width * scale,
      height: imageBounds.height * scale
    )

    // Validate bounds to catch coordinate transformation bugs early
    assert(rect.width > 0 && rect.height > 0, "Invalid display bounds calculated: \(rect)")

    return rect
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
