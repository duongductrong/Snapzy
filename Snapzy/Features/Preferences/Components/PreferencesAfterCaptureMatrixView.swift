//
//  AfterCaptureMatrixView.swift
//  Snapzy
//
//  Grid component for configuring post-capture actions
//

import SwiftUI

struct AfterCaptureMatrixView: View {
  @ObservedObject private var manager = PreferencesManager.shared
  @ObservedObject private var cloudManager = CloudManager.shared
  @State private var showCloudNotConfiguredAlert = false

  var body: some View {
    VStack(spacing: 0) {
      // Column headers
      HStack(spacing: 12) {
        Spacer()
          .frame(width: 28)
        Spacer()
        HStack(spacing: 16) {
          Text(CaptureType.screenshot.displayName)
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(width: 70)
          Text(CaptureType.recording.displayName)
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(width: 70)
        }
      }
      .padding(.bottom, 4)

      ForEach(AfterCaptureAction.allCases, id: \.self) { action in
        actionRow(for: action)
      }
    }
    .alert(L10n.AfterCapture.cloudAlertTitle, isPresented: $showCloudNotConfiguredAlert) {
      Button(L10n.Common.ok, role: .cancel) {}
    } message: {
      Text(L10n.AfterCapture.cloudAlertMessage)
    }
  }

  @ViewBuilder
  private func actionRow(for action: AfterCaptureAction) -> some View {
    HStack(spacing: 12) {
      Image(systemName: iconName(for: action))
        .font(.title2)
        .foregroundColor(.secondary)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(action.displayName)
          .fontWeight(.medium)
        Text(description(for: action))
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      HStack(spacing: 16) {
        toggleColumn(captureType: .screenshot, action: action, type: .screenshot)
        toggleColumn(captureType: .recording, action: action, type: .recording)
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func toggleColumn(captureType: CaptureType, action: AfterCaptureAction, type: CaptureType) -> some View {
    let isDisabled = (action == .openAnnotate && type == .recording)
      || (action == .uploadToCloud && type == .recording)
    Toggle("", isOn: cloudAwareBinding(for: action, type: type))
      .labelsHidden()
      .accessibilityLabel(L10n.AfterCapture.accessibilityLabel(action.displayName, captureKind: captureType.displayName))
      .frame(width: 70)
      .disabled(isDisabled)
      .opacity(isDisabled ? 0.3 : 1)
  }

  private func iconName(for action: AfterCaptureAction) -> String {
    switch action {
    case .showQuickAccess:
      return "rectangle.on.rectangle.angled"
    case .copyFile:
      return "doc.on.clipboard"
    case .save:
      return "square.and.arrow.down"
    case .openAnnotate:
      return "pencil.and.outline"
    case .uploadToCloud:
      return "icloud.and.arrow.up"
    }
  }

  private func description(for action: AfterCaptureAction) -> String {
    switch action {
    case .showQuickAccess:
      return L10n.AfterCapture.showQuickAccessDescription
    case .copyFile:
      return L10n.AfterCapture.copyFileDescription
    case .save:
      return L10n.AfterCapture.saveDescription
    case .openAnnotate:
      return L10n.AfterCapture.openAnnotateDescription
    case .uploadToCloud:
      return L10n.AfterCapture.uploadToCloudDescription
    }
  }

  private func binding(for action: AfterCaptureAction, type: CaptureType) -> Binding<Bool> {
    Binding(
      get: { manager.isActionEnabled(action, for: type) },
      set: { manager.setAction(action, for: type, enabled: $0) }
    )
  }

  /// Cloud-aware binding that shows alert when enabling cloud without configuration
  private func cloudAwareBinding(for action: AfterCaptureAction, type: CaptureType) -> Binding<Bool> {
    Binding(
      get: { manager.isActionEnabled(action, for: type) },
      set: { newValue in
        if action == .uploadToCloud && newValue && !cloudManager.isConfigured {
          showCloudNotConfiguredAlert = true
          return
        }
        manager.setAction(action, for: type, enabled: newValue)
      }
    )
  }
}

#Preview {
  AfterCaptureMatrixView()
    .padding()
}
