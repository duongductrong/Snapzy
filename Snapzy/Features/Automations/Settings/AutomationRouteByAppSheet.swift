//
//  AutomationRouteByAppSheet.swift
//  Snapzy
//
//  "Route by App…" helper (milestone 5): pick apps and the steps to run for
//  them; the editor inserts `condition(app is …, else skip n) · steps · stop`
//  so designers get per-app routing without counting skips.
//

import SwiftUI

struct AutomationRouteByAppSheet: View {
  /// How many routed steps still fit (the block adds a condition and a stop).
  let maxSteps: Int
  let onInsert: (_ bundleIDs: [String], _ kinds: [AutomationStepKind]) -> Void
  let onCancel: () -> Void

  @State private var bundleIDs: [String] = []
  @State private var kinds: [AutomationStepKind] = [.saveToFolder]

  private static let offeredKinds: [AutomationStepKind] =
    AutomationStepGroup.transform.kinds + AutomationStepGroup.deliver.kinds + AutomationStepGroup.integrations.kinds

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Form {
        Section {
          ForEach(bundleIDs, id: \.self) { bundleID in
            HStack(spacing: 6) {
              if let icon = AppListEditor.icon(for: bundleID) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
              }
              Text(AutomationConditionText.appName(for: bundleID))
              Spacer()
              Button {
                bundleIDs.removeAll { $0 == bundleID }
              } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
              }
              .buttonStyle(.borderless)
              .accessibilityLabel(L10n.Common.delete)
            }
          }
          AppPickerMenu(title: L10n.Automations.conditionAddApp) { bundleID in
            if !bundleIDs.contains(bundleID) { bundleIDs.append(bundleID) }
          }
        } header: {
          Text(L10n.Automations.routeAppsHeader)
        }

        Section {
          ForEach(Self.offeredKinds) { kind in
            Toggle(isOn: Binding(
              get: { kinds.contains(kind) },
              set: { isOn in
                if isOn {
                  kinds = Self.offeredKinds.filter { kinds.contains($0) || $0 == kind }
                } else {
                  kinds.removeAll { $0 == kind }
                }
              }
            )) {
              Label(kind.displayName, systemImage: kind.symbol)
            }
            .disabled(!kinds.contains(kind) && kinds.count >= maxSteps)
          }
        } header: {
          Text(L10n.Automations.routeStepsHeader)
        } footer: {
          Text(L10n.Automations.routeFooter)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .formStyle(.grouped)

      Divider()
      HStack {
        Spacer()
        Button(L10n.Common.cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(L10n.Automations.routeInsert) {
          onInsert(bundleIDs, kinds)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(bundleIDs.isEmpty || kinds.isEmpty)
      }
      .padding(12)
    }
    .frame(width: 420, height: 520)
    .navigationTitle(L10n.Automations.routeByApp)
  }
}
