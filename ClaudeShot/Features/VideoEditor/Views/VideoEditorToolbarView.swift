//
//  VideoEditorToolbarView.swift
//  ClaudeShot
//
//  Top toolbar for video editor with undo/redo, filename, and save actions
//

import SwiftUI

/// Top toolbar for video editor window
struct VideoEditorToolbarView: View {
  @ObservedObject var state: VideoEditorState
  var onSave: () -> Void

  @State private var editingFilename: String = ""
  @State private var renameError: String?

  var body: some View {
    HStack(spacing: 0) {
      // LEFT: Undo/Redo/Folder
      leftSection

      Spacer()

      // CENTER: Filename
      centerSection

      Spacer()

      // RIGHT: Save actions
      rightSection
    }
    .frame(height: 44)
    .padding(.horizontal, 12)
    .background(Color(NSColor.windowBackgroundColor))
  }

  // MARK: - Left Section

  private var leftSection: some View {
    HStack(spacing: 8) {
      // Undo button
      Button(action: { state.undo() }) {
        Image(systemName: "arrow.uturn.backward")
          .font(.system(size: 14))
          .frame(width: 28, height: 28)
          .background(Color.white.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .disabled(!state.canUndo)
      .opacity(state.canUndo ? 1 : 0.4)
      .keyboardShortcut("z", modifiers: [.command])
      .help("Undo (⌘Z)")

      // Redo button
      Button(action: { state.redo() }) {
        Image(systemName: "arrow.uturn.forward")
          .font(.system(size: 14))
          .frame(width: 28, height: 28)
          .background(Color.white.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .disabled(!state.canRedo)
      .opacity(state.canRedo ? 1 : 0.4)
      .keyboardShortcut("z", modifiers: [.command, .shift])
      .help("Redo (⌘⇧Z)")

      Divider()
        .frame(height: 20)

      // Open in Folder button
      Button(action: { state.openInFinder() }) {
        Image(systemName: "folder")
          .font(.system(size: 14))
          .frame(width: 28, height: 28)
          .background(Color.white.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .help("Open in Finder")

      // Video Info button
      Button(action: { state.toggleVideoInfoSidebar() }) {
        Image(systemName: state.isVideoInfoSidebarVisible ? "info.circle.fill" : "info.circle")
          .font(.system(size: 14))
          .foregroundColor(state.isVideoInfoSidebarVisible ? ZoomColors.primary : .primary)
          .frame(width: 28, height: 28)
          .background(state.isVideoInfoSidebarVisible ? ZoomColors.primary.opacity(0.15) : Color.white.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .keyboardShortcut("i", modifiers: [])
      .help(state.isVideoInfoSidebarVisible ? "Hide Video Info (I)" : "Show Video Info (I)")
    }
  }

  // MARK: - Center Section

  private var centerSection: some View {
    HStack(spacing: 6) {
      if state.isRenamingFile {
        TextField("Filename", text: $editingFilename, onCommit: commitRename)
          .textFieldStyle(.plain)
          .font(.system(size: 13, weight: .medium))
          .frame(width: 200)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color.white.opacity(0.1))
          .cornerRadius(6)
          .onAppear {
            editingFilename = filenameWithoutExtension
          }
          .onExitCommand {
            state.isRenamingFile = false
            renameError = nil
          }
      } else {
        Text(state.filename)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 300)

        Button(action: startRename) {
          Image(systemName: "pencil")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Rename file")
      }

      if let error = renameError {
        Text(error)
          .font(.system(size: 10))
          .foregroundColor(.red)
      }
    }
  }

  // MARK: - Right Section

  private var rightSection: some View {
    HStack(spacing: 8) {
      // Unsaved changes indicator
      if state.hasUnsavedChanges {
        HStack(spacing: 4) {
          Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundColor(.orange)
          Text("Unsaved")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
      }

      // Save button (primary)
      Button(action: onSave) {
        Text("Save")
          .font(.system(size: 13, weight: .medium))
          .frame(minWidth: 60)
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut("s", modifiers: [.command])
      .disabled(!state.hasUnsavedChanges)
    }
  }

  // MARK: - Helpers

  private var filenameWithoutExtension: String {
    let filename = state.filename
    if let dotIndex = filename.lastIndex(of: ".") {
      return String(filename[..<dotIndex])
    }
    return filename
  }

  private func startRename() {
    editingFilename = filenameWithoutExtension
    renameError = nil
    state.isRenamingFile = true
  }

  private func commitRename() {
    do {
      try state.renameFile(to: editingFilename)
      state.isRenamingFile = false
      renameError = nil
    } catch {
      renameError = error.localizedDescription
    }
  }
}

// MARK: - Preview

#Preview {
  VideoEditorToolbarView(
    state: VideoEditorState(url: URL(fileURLWithPath: "/tmp/test-video.mov")),
    onSave: {}
  )
  .frame(width: 800)
  .background(Color(NSColor.windowBackgroundColor))
}
