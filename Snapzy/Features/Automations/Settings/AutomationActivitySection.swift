//
//  AutomationActivitySection.swift
//  Snapzy
//
//  Settings → Automations → Activity: the last runs with outcome, duration
//  and per-step timings. Rows expand to show steps and offer Reveal input,
//  Copy link and Run again on the same input.
//

import AppKit
import SwiftUI

struct AutomationActivitySection: View {
  @ObservedObject private var log = AutomationRunLog.shared
  @AppStorage(PreferencesKeys.automationsActivityLogEnabled) private var isEnabled = true
  @State private var expanded: Set<UUID> = []

  var body: some View {
    Section {
      Toggle(L10n.Automations.activityEnabled, isOn: $isEnabled)

      if log.records.isEmpty {
        Text(L10n.Automations.activityEmpty)
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 8)
      }

      ForEach(log.records) { record in
        DisclosureGroup(isExpanded: expansion(record.id)) {
          AutomationRunDetail(record: record)
        } label: {
          AutomationRunSummaryRow(record: record)
        }
      }
    } header: {
      VStack(alignment: .leading, spacing: 2) {
        Text(L10n.Automations.pageActivity)
        Text(L10n.Automations.activityDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    } footer: {
      if !log.records.isEmpty {
        Button(L10n.Automations.activityClear, role: .destructive) { log.clear() }
          .buttonStyle(.link)
      }
    }
  }

  private func expansion(_ id: UUID) -> Binding<Bool> {
    Binding(
      get: { expanded.contains(id) },
      set: { isOn in
        if isOn { expanded.insert(id) } else { expanded.remove(id) }
      }
    )
  }
}

private struct AutomationRunSummaryRow: View {
  let record: AutomationRunRecord

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: outcomeSymbol)
        .foregroundStyle(outcomeColor)
        .accessibilityLabel(outcomeLabel)
      VStack(alignment: .leading, spacing: 1) {
        Text(record.automationName).lineLimit(1)
        Text("\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(Self.invocationName(record.invocation))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(Self.duration(record.durationMs))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
  }

  static func invocationName(_ raw: String) -> String {
    AutomationInvocation(rawValue: raw)?.displayName ?? raw
  }

  static func duration(_ ms: Int) -> String {
    ms < 1000 ? "\(ms) ms" : String(format: "%.1f s", Double(ms) / 1000)
  }

  private var outcomeSymbol: String {
    switch record.outcome {
    case .succeeded: "checkmark.circle.fill"
    case .partial: "exclamationmark.circle.fill"
    case .failed: "xmark.circle.fill"
    case .cancelled: "slash.circle"
    }
  }

  private var outcomeColor: Color {
    switch record.outcome {
    case .succeeded: .green
    case .partial: .orange
    case .failed: .red
    case .cancelled: .secondary
    }
  }

  private var outcomeLabel: String {
    switch record.outcome {
    case .succeeded: L10n.Automations.outcomeSucceeded
    case .partial: L10n.Automations.outcomePartial
    case .failed: L10n.Automations.outcomeFailed
    case .cancelled: L10n.Automations.outcomeCancelled
    }
  }
}

private struct AutomationRunDetail: View {
  let record: AutomationRunRecord

  /// Steps with nested runs (Run Automation, Ask) flattened and indented.
  static func rows(
    _ steps: [AutomationRunRecord.StepRecord],
    depth: Int = 0
  ) -> [(step: AutomationRunRecord.StepRecord, depth: Int)] {
    steps.flatMap { step in
      [(step, depth)] + rows(step.children ?? [], depth: depth + 1)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(Self.rows(record.steps).enumerated()), id: \.offset) { _, row in
        let step = row.step
        HStack(spacing: 6) {
          Image(systemName: symbol(step.status))
            .foregroundStyle(step.status == .failed ? .red : .secondary)
            .frame(width: 14)
          Text(AutomationStepKind(rawValue: step.kind)?.displayName ?? step.kind)
          // Control steps say why ("Condition not met", the chosen automation).
          if let detail = step.detail {
            Text(detail).foregroundStyle(.secondary).lineLimit(1)
          }
          if let error = step.error {
            Text(error).foregroundStyle(.red).lineLimit(2)
          }
          Spacer()
          Text(AutomationRunSummaryRow.duration(step.durationMs))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.leading, CGFloat(row.depth) * 16)
      }
      ForEach(record.warnings, id: \.self) { warning in
        Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
      }
      if let text = record.text {
        Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
      }
      HStack(spacing: 12) {
        if !existingInputs.isEmpty {
          Button(L10n.Automations.activityRevealInput) { FileRevealer.reveal(existingInputs) }
          Button(L10n.Automations.activityRunAgain) { runAgain() }
        }
        if let link = record.link {
          Button(L10n.Automations.activityCopyLink) { ClipboardHelper.copyText(link) }
        }
        if let saved = record.savedPaths.first {
          Button(L10n.Automations.activityRevealSaved) { FileRevealer.reveal([URL(fileURLWithPath: saved)]) }
        }
      }
      .buttonStyle(.link)
      .font(.caption)
    }
    .padding(.leading, 4)
  }

  private var existingInputs: [URL] {
    record.inputFiles.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  private func runAgain() {
    let input = AutomationInput(files: existingInputs, isAlreadyInHistory: true)
    Task { @MainActor in
      let outcome = await AutomationLauncher.shared.launch(.id(record.automationID), invocation: .retry, input: input)
      if case .rejected(let rejection) = outcome {
        AppToastManager.shared.show(message: rejection.localizedMessage, style: .warning)
      }
    }
  }

  private func symbol(_ status: AutomationRunRecord.StepRecord.Status) -> String {
    switch status {
    case .succeeded: "checkmark"
    case .failed: "xmark"
    case .skipped: "arrow.turn.down.right"
    }
  }
}
