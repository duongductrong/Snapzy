//
//  AfterCaptureMatrixView.swift
//  Snapzy
//
//  Grid component for configuring post-capture actions.
//  Milestone 6: the cells edit the default after-capture automations. A
//  capture type with a custom pipeline keeps only its Save cell here; its
//  steps are edited in the automation editor (`AfterCaptureCustomizeRow`).
//

import SwiftUI

struct AfterCaptureMatrixView: View {
  @ObservedObject private var manager = PreferencesManager.shared
  @ObservedObject private var automations = AutomationStore.shared

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
    let isCustom = action != .save && automations.defaultAutomation(for: type).isCustomizedSystemDefault
    let isDisabled = (action == .openAnnotate && type == .recording) || isCustom
    Toggle("", isOn: binding(for: action, type: type))
      .labelsHidden()
      .accessibilityLabel(L10n.AfterCapture.accessibilityLabel(action.displayName, captureKind: captureType.displayName))
      .frame(width: 70)
      .disabled(isDisabled)
      .opacity(isDisabled ? 0.3 : 1)
      .help(isCustom ? L10n.Automations.systemDefaultCustomSummary(type.displayName) : "")
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
    }
  }

  private func binding(for action: AfterCaptureAction, type: CaptureType) -> Binding<Bool> {
    Binding(
      get: { manager.isActionEnabled(action, for: type) },
      set: { manager.setAction(action, for: type, enabled: $0) }
    )
  }
}

#Preview {
  AfterCaptureMatrixView()
    .padding()
}

