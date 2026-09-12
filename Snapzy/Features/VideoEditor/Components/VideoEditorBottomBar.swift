//
//  VideoEditorBottomBar.swift
//  Snapzy
//
//  Bottom bar for video editor with Cancel, Cloud Upload, and Convert actions
//

import SwiftUI

/// Bottom bar for video editor with Cancel, Cloud Upload, and Convert buttons
struct VideoEditorBottomBar: View {
  @ObservedObject var state: VideoEditorState
  var primaryActionTitle: String = L10n.VideoEditor.convert
  var onCancel: () -> Void
  var onConvert: () -> Void

  @ObservedObject private var cloudManager = CloudManager.shared

  @State private var isCloudUploading = false
  @State private var cloudUploadProgress: Double = 0
  @State private var cloudUploadError: String?
  @State private var showCloudNotConfiguredAlert = false
  @State private var showOverwriteConfirmation = false

  private var shouldShowCloudButton: Bool {
    cloudManager.isConfigured && QuickAccessActionConfigurationStore.shared.isEnabled(.uploadToCloud)
  }

  private var alreadyUploadedToCloud: Bool {
    state.cloudURL != nil
  }

  var body: some View {
    VStack(spacing: 0) {
      Divider()

      HStack(spacing: 12) {
        // Cancel button (left)
        Button(L10n.Common.cancel, action: onCancel)
          .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))

        Spacer()

        if shouldShowCloudButton {
          let tooltip = alreadyUploadedToCloud 
            ? L10n.AnnotateUI.uploadedToCloud 
            : (state.cloudKey != nil ? L10n.AnnotateUI.reuploadToCloud : L10n.AnnotateUI.uploadToCloud)

          BottomBarButton(
            icon: alreadyUploadedToCloud ? "checkmark.icloud" : "icloud.and.arrow.up",
            tooltip: tooltip
          ) {
            if state.cloudKey != nil && !alreadyUploadedToCloud {
              showOverwriteConfirmation = true
            } else {
              handleCloudUpload()
            }
          }
          .disabled(isCloudUploading || alreadyUploadedToCloud)
        }

        // Primary action button (right) - always enabled
        Button(primaryActionTitle, action: onConvert)
          .buttonStyle(.liquidGlass(emphasis: .primary, capsule: true))
          .keyboardShortcut("s", modifiers: [.command])
      }
      .padding(.horizontal, WindowSpacingConfiguration.default.toolbarHPadding)
      .padding(.vertical, 12)
      // One effect container for the row, so the glass is evaluated in a single pass.
      .liquidGlassGroup(spacing: Spacing.sm)

      // Cloud upload progress bar (always present to avoid layout shift)
      ProgressView(value: cloudUploadProgress)
        .progressViewStyle(.linear)
        .frame(height: 3)
        .opacity(isCloudUploading ? 1 : 0)
    }
    .alert(L10n.AnnotateUI.cloudNotConfiguredTitle, isPresented: $showCloudNotConfiguredAlert) {
      Button(L10n.Common.ok, role: .cancel) {}
    } message: {
      Text(L10n.AnnotateUI.cloudNotConfiguredMessage)
    }
    .alert(L10n.AnnotateUI.overwriteCloudFileTitle, isPresented: $showOverwriteConfirmation) {
      Button(L10n.Common.overwrite) {
        handleCloudUpload(overwrite: true)
      }
      .keyboardShortcut(.defaultAction)
      Button(L10n.Common.cancel, role: .cancel) {}
    } message: {
      Text(L10n.AnnotateUI.overwriteCloudFileMessage)
    }
    .onReceive(NotificationCenter.default.publisher(for: .videoEditorCloudUpload)) { _ in
      // ⌘U keyboard shortcut triggers cloud upload
      guard shouldShowCloudButton && !isCloudUploading && !alreadyUploadedToCloud else { return }
      if state.cloudKey != nil {
        showOverwriteConfirmation = true
      } else {
        handleCloudUpload()
      }
    }
  }

  // MARK: - Cloud Upload Flow

  private func handleCloudUpload(overwrite: Bool = false) {
    guard cloudManager.isConfigured else {
      showCloudNotConfiguredAlert = true
      return
    }

    let sourceURL = state.sourceURL

    isCloudUploading = true
    cloudUploadProgress = 0
    let uploadStartTime = Date()
    let oldCloudKey = overwrite ? nil : state.cloudKey // If not overwriting, save old key for cleanup

    // Animate progress to 80% quickly to show activity
    withAnimation(.easeOut(duration: 0.4)) {
      cloudUploadProgress = 0.8
    }

    Task {
      do {
        let fileAccess = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
        defer { fileAccess.stop() }

        // Use old key if overwriting to replace the object, otherwise upload with fresh key
        let uploadKey = overwrite ? state.cloudKey : nil
        let result = try await cloudManager.upload(fileURL: sourceURL, existingKey: uploadKey)

        // Delete old cloud file if we generated a fresh one and had a previous one
        if let oldKey = oldCloudKey {
          Task.detached(priority: .utility) {
            do {
              try await CloudManager.shared.deleteByKey(key: oldKey)
            } catch {
              DiagnosticLogger.shared.logError(.cloud, error, "Video editor old cloud object cleanup failed")
            }
          }
        }

        // Store cloud URL and key on state
        state.cloudURL = result.publicURL
        state.cloudKey = result.key

        // Copy cloud link to pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.publicURL.absoluteString, forType: .string)

        // Ensure minimum visual duration (~600ms total)
        let elapsed = Date().timeIntervalSince(uploadStartTime)
        let remainingDelay = max(0, 0.6 - elapsed)

        withAnimation(.easeIn(duration: 0.15)) {
          cloudUploadProgress = 1.0
        }

        if remainingDelay > 0 {
          try? await Task.sleep(nanoseconds: UInt64(remainingDelay * 1_000_000_000))
        }

        isCloudUploading = false
        SoundManager.play("Pop")

        // Sync with Quick Access item if linked
        if let itemId = state.quickAccessItemId {
          QuickAccessManager.shared.setCloudURL(id: itemId, url: result.publicURL, key: result.key)
        }

        DiagnosticLogger.shared.log(
          .info,
          .cloud,
          "Video editor cloud upload completed",
          context: ["fileName": sourceURL.lastPathComponent]
        )

        // Auto-close window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          NSApp.keyWindow?.close()
        }
      } catch {
        isCloudUploading = false
        cloudUploadProgress = 0
        cloudUploadError = error.localizedDescription
        DiagnosticLogger.shared.logError(
          .cloud,
          error,
          "Video editor cloud upload failed",
          context: ["fileName": sourceURL.lastPathComponent]
        )
      }
    }
  }
}

// MARK: - Preview

#Preview {
  VideoEditorBottomBar(
    state: VideoEditorState(url: URL(fileURLWithPath: "/tmp/test-video.mp4")),
    onCancel: {},
    onConvert: {}
  )
  .frame(width: 600)
  .background(Color(NSColor.windowBackgroundColor))
}
