//
//  LicenseDebugSettingsView.swift
//  Snapzy
//
//  DEBUG-only tab showing comprehensive license debug information
//

#if DEBUG

import SwiftUI

struct LicenseDebugSettingsView: View {
  @ObservedObject private var licenseManager = LicenseManager.shared

  @State private var sandboxStatus: String = "Not tested"
  @State private var isTesting = false
  @State private var copiedToClipboard = false

  private let cache = LicenseCache()
  private let debugger = LicenseDebugger.shared
  private let telemetry = LicenseTelemetry.shared
  private let fingerprint = DeviceFingerprint.shared

  private let monoFont = Font.system(size: 11, design: .monospaced)
  private let labelFont = Font.system(size: 11, weight: .medium)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        // Header
        HStack {
          Image(systemName: "ant.fill")
            .font(.system(size: 16))
            .foregroundColor(.orange)
          Text("License Debug")
            .font(.system(size: 16, weight: .bold))
          Spacer()
          buildBadge
        }
        .padding(.bottom, Spacing.xs)

        // Sections
        stateSection
        configSection
        cacheSection
        deviceSection
        telemetrySection
        actionsSection
      }
      .padding(Spacing.lg)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Build Badge

  private var buildBadge: some View {
    Text("DEBUG")
      .font(.system(size: 10, weight: .bold, design: .monospaced))
      .foregroundColor(.orange)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(Color.orange.opacity(0.15))
      .clipShape(Capsule())
  }

  // MARK: - License State

  private var stateSection: some View {
    debugSection("License State", icon: "checkmark.shield") {
      debugRow("State", value: licenseManager.state.description)
      debugRow("Status", value: licenseManager.state.statusDescription)
      debugRow("Is Licensed", value: licenseManager.isLicensed ? "✅ Yes" : "❌ No")
      debugRow("Is Valid", value: licenseManager.state.isValid ? "✅ Yes" : "❌ No")


      if let days = licenseManager.state.daysRemaining {
        debugRow("Days Remaining", value: "\(days)")
      }

      if let license = licenseManager.state.license {
        Divider().padding(.vertical, 2)
        debugRow("License ID", value: license.id.uuidString)
        debugRow("Customer ID", value: license.customerId.uuidString)
        debugRow("Key", value: license.key)
        debugRow("Display Key", value: license.displayKey)
        debugRow("Status", value: license.status.rawValue)
        debugRow("Usage", value: "\(license.usage)")
        debugRow("Limit Activations", value: license.limitActivations.map { "\($0)" } ?? "Unlimited")
        debugRow("Remaining", value: license.remainingActivations.map { "\($0)" } ?? "N/A")
        debugRow("Validations", value: "\(license.validations)")
        debugRow("Is Expired", value: license.isExpired ? "⚠️ Yes" : "No")
        debugRow("Expires At", value: license.expiresAt.map { formatDate($0) } ?? "Never")
        debugRow("Last Validated", value: license.lastValidatedAt.map { formatDate($0) } ?? "Never")
        debugRow("Created At", value: formatDate(license.createdAt))

        if let activation = license.activation {
          Divider().padding(.vertical, 2)
          Text("Activation")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
          debugRow("Activation ID", value: activation.id.uuidString)
          debugRow("License Key ID", value: activation.licenseKeyId.uuidString)
          debugRow("Label", value: activation.label)
          debugRow("Created At", value: formatDate(activation.createdAt))
          if !activation.meta.isEmpty {
            debugRow("Meta", value: activation.meta.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
          }
        }
      }
    }
  }

  // MARK: - Configuration

  private var configSection: some View {
    debugSection("Configuration", icon: "gearshape") {
      debugRow("Organization ID", value: licenseManager.getOrganizationId()?.uuidString ?? "NOT SET ⚠️")
      debugRow("Device Limit", value: "\(licenseManager.getDeviceLimit())")
      debugRow("API Mode", value: PolarLicenseProvider.isSandbox ? "🧪 Sandbox" : "🚀 Production")

    }
  }

  // MARK: - Cached Data

  private var cacheSection: some View {
    debugSection("Cache", icon: "cylinder.split.1x2") {
      debugRow("Activation ID", value: cache.getActivationId()?.uuidString ?? "None")
      debugRow("License Key", value: cache.getLicenseKey() ?? "None")


      if let entry = cache.load() {
        Divider().padding(.vertical, 2)
        Text("Cached Entry")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)
        debugRow("Cached At", value: formatDate(entry.cachedAt))
        debugRow("Fingerprint", value: entry.deviceFingerprint)
        debugRow("License Key", value: entry.license.key)
        debugRow("Display Key", value: entry.license.displayKey)
        debugRow("Status", value: entry.license.status.rawValue)
      } else {
        debugRow("Cached Entry", value: "None")
      }
    }
  }

  // MARK: - Device Info

  private var deviceSection: some View {
    debugSection("Device", icon: "desktopcomputer") {
      debugRow("Fingerprint", value: fingerprint.generate())
      debugRow("Device Name", value: fingerprint.generateDeviceName())
    }
  }

  // MARK: - Telemetry

  private var telemetrySection: some View {
    debugSection("Telemetry", icon: "chart.bar") {
      let events: [(String, LicenseEvent)] = [
        ("App Launches", .appLaunched),

        ("Activations", .licenseActivated),
        ("Activation Attempts", .activationAttempted),
        ("Validations", .licenseValidated),
        ("Revocations", .licenseRevoked),
        ("Expirations", .licenseExpired),
        ("Failures", .validationFailed),
        ("Device Limit Exceeded", .deviceLimitExceeded),
        ("Deactivation Attempts", .deactivationAttempted),
      ]

      ForEach(events, id: \.0) { name, event in
        let count = telemetry.getEventCount(for: event.rawValue)
        debugRow(name, value: "\(count)")
      }

      Divider().padding(.vertical, 2)

      Text("Recent Events (last 20)")
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.secondary)

      let recentEvents = telemetry.getRecentEvents(limit: 20)
      if recentEvents.isEmpty {
        Text("No events recorded")
          .font(monoFont)
          .foregroundColor(.secondary)
      } else {
        ForEach(recentEvents, id: \.id) { entry in
          HStack(alignment: .top, spacing: 6) {
            Text(formatDate(entry.timestamp))
              .font(.system(size: 9, design: .monospaced))
              .foregroundColor(.secondary)
              .frame(width: 130, alignment: .leading)
            Text(entry.event)
              .font(.system(size: 10, weight: .medium, design: .monospaced))
              .foregroundColor(.primary)
            if !entry.metadata.isEmpty {
              Text(entry.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            Spacer()
          }
          .padding(.vertical, 1)
        }
      }
    }
  }

  // MARK: - Actions

  private var actionsSection: some View {
    debugSection("Actions", icon: "hammer") {
      HStack(spacing: Spacing.sm) {
        // Clear Cache
        Button(role: .destructive) {
          Task {
            try? await licenseManager.clearLicense()
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "trash")
              .font(.system(size: 11))
            Text("Clear Cache")
          }
          .font(.system(size: 12))
        }
        .controlSize(.small)

        // Print to Console
        Button {
          licenseManager.printDebugInfo()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "terminal")
              .font(.system(size: 11))
            Text("Print to Console")
          }
          .font(.system(size: 12))
        }
        .controlSize(.small)

        // Copy All to Clipboard
        Button {
          copyAllToClipboard()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
              .font(.system(size: 11))
            Text(copiedToClipboard ? "Copied!" : "Copy All")
          }
          .font(.system(size: 12))
        }
        .controlSize(.small)

        // Test Sandbox
        Button {
          testSandbox()
        } label: {
          HStack(spacing: 4) {
            if isTesting {
              ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
            }
            Image(systemName: "network")
              .font(.system(size: 11))
            Text("Test Sandbox")
          }
          .font(.system(size: 12))
        }
        .controlSize(.small)
        .disabled(isTesting)
      }

      if sandboxStatus != "Not tested" {
        debugRow("Sandbox Result", value: sandboxStatus)
      }

      Divider().padding(.vertical, 2)

      // Clear Telemetry
      Button(role: .destructive) {
        telemetry.clearEvents()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "xmark.bin")
            .font(.system(size: 11))
          Text("Clear Telemetry Events")
        }
        .font(.system(size: 12))
      }
      .controlSize(.small)
    }
  }

  // MARK: - Helpers

  private func debugSection<Content: View>(
    _ title: String,
    icon: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 12))
          .foregroundColor(.accentColor)
        Text(title)
          .font(.system(size: 13, weight: .semibold))
      }

      VStack(alignment: .leading, spacing: 4) {
        content()
      }
      .padding(Spacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.primary.opacity(0.03))
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }

  private func debugRow(_ label: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(label)
        .font(labelFont)
        .foregroundColor(.secondary)
        .frame(width: 140, alignment: .trailing)

      Text(value)
        .font(monoFont)
        .foregroundColor(.primary)
        .textSelection(.enabled)

      Spacer()
    }
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
  }

  private func copyAllToClipboard() {
    var text = debugger.getDebugInfo()
    text += "\n\n"
    text += licenseManager.generateDebugReport()
    text += "\n\nDevice Fingerprint: \(fingerprint.generate())"
    text += "\nDevice Name: \(fingerprint.generateDeviceName())"

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)

    copiedToClipboard = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      copiedToClipboard = false
    }
  }

  private func testSandbox() {
    isTesting = true
    debugger.testSandboxConnection { success, message in
      sandboxStatus = success ? "✅ \(message)" : "❌ \(message)"
      isTesting = false
    }
  }
}

#Preview {
  LicenseDebugSettingsView()
    .frame(width: 700, height: 550)
}

#endif
