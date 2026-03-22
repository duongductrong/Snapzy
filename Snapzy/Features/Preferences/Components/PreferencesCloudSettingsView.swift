//
//  PreferencesCloudSettingsView.swift
//  Snapzy
//
//  Cloud storage configuration tab with three states:
//  unconfigured (form), configured (masked summary), edit mode (pre-filled form)
//

import SwiftUI

/// Cloud settings tab in Preferences
struct CloudSettingsView: View {
  @ObservedObject private var cloudManager = CloudManager.shared
  @ObservedObject private var historyStore = CloudUploadHistoryStore.shared

  @State private var isEditing = false
  @State private var showResetConfirmation = false

  var body: some View {
    Form {
      if cloudManager.isConfigured && !isEditing {
        configuredView
      } else {
        CloudCredentialFormView(
          isEditing: isEditing,
          onSave: { isEditing = false },
          onCancel: { isEditing = false }
        )
      }
    }
    .formStyle(.grouped)
    .alert("Reset Cloud Configuration?", isPresented: $showResetConfirmation) {
      Button("Reset", role: .destructive) {
        cloudManager.clearConfiguration()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will remove all cloud credentials and settings. This action cannot be undone.")
    }
  }

  // MARK: - Configured State

  private var configuredView: some View {
    Group {
      Section("Cloud Provider") {
        if let config = cloudManager.loadConfiguration() {
          SettingRow(
            icon: "cloud.fill",
            title: config.providerType.displayName,
            description: "Bucket: \(config.bucket)"
          ) {
            EmptyView()
          }

          SettingRow(
            icon: "key.fill",
            title: "Access Key",
            description: cloudManager.maskedAccessKey()
          ) {
            EmptyView()
          }

          if !config.region.isEmpty && config.providerType == .awsS3 {
            SettingRow(
              icon: "globe",
              title: "Region",
              description: config.region
            ) {
              EmptyView()
            }
          }

          if let endpoint = config.endpoint, !endpoint.isEmpty {
            SettingRow(
              icon: "server.rack",
              title: "Endpoint",
              description: endpoint
            ) {
              EmptyView()
            }
          }

          SettingRow(
            icon: "clock",
            title: "Expire Time",
            description: config.expireTime.displayName
          ) {
            EmptyView()
          }

          if let domain = config.customDomain, !domain.isEmpty {
            SettingRow(
              icon: "link",
              title: "Custom Domain",
              description: domain
            ) {
              EmptyView()
            }
          }
        }

        HStack(spacing: 12) {
          Button(action: { isEditing = true }) {
            Label("Edit", systemImage: "pencil")
          }

          Button(role: .destructive, action: { showResetConfirmation = true }) {
            Label("Reset", systemImage: "arrow.counterclockwise")
          }
          .foregroundColor(.red)
        }
        .padding(.top, 4)
      }

      // Recent uploads section
      if !historyStore.records.isEmpty {
        Section("Recent Uploads") {
          ForEach(historyStore.recentRecords(limit: 5)) { record in
            CloudUploadRecordRow(record: record)
          }

          if historyStore.records.count > 5 {
            Button("View All Uploads (\(historyStore.records.count))") {
              CloudUploadHistoryWindowController.shared.showWindow()
            }
            .font(.system(size: 12))
          }
        }
      }
    }
  }
}

// MARK: - Credential Form

/// Reusable form for creating or editing cloud credentials
private struct CloudCredentialFormView: View {
  let isEditing: Bool
  let onSave: () -> Void
  let onCancel: () -> Void

  @ObservedObject private var cloudManager = CloudManager.shared

  @State private var providerType: CloudProviderType = .awsS3
  @State private var accessKey = ""
  @State private var secretKey = ""
  @State private var bucket = ""
  @State private var region = "us-east-1"
  @State private var endpoint = ""
  @State private var customDomain = ""
  @State private var expireTime: CloudExpireTime = .day7
  @State private var showSecretKey = false

  @State private var isValidating = false
  @State private var validationError: String?
  @State private var validationSuccess = false

  var body: some View {
    Group {
      Section("Cloud Provider") {
        SettingRow(icon: "cloud", title: "Provider", description: nil, tooltip: "Select your cloud storage provider") {
          Picker("", selection: $providerType) {
            ForEach(CloudProviderType.allCases, id: \.self) { type in
              Text(type.displayName).tag(type)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      }

      Section("Credentials") {
        SettingRow(icon: "key", title: "Access Key ID", description: nil, tooltip: "Your cloud provider access key") {
          TextField("", text: $accessKey)
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }

        SettingRow(icon: "lock", title: "Secret Access Key", description: nil, tooltip: "Your cloud provider secret key") {
          HStack(spacing: 6) {
            if showSecretKey {
              TextField("", text: $secretKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
            } else {
              SecureField("", text: $secretKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
            }
            Button(action: { showSecretKey.toggle() }) {
              Image(systemName: showSecretKey ? "eye.slash" : "eye")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
          }
        }
      }

      Section("Storage") {
        SettingRow(icon: "externaldrive", title: "Bucket Name", description: nil, tooltip: "S3 or R2 bucket name") {
          TextField("", text: $bucket)
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }

        if providerType == .awsS3 {
          SettingRow(icon: "globe", title: "Region", description: nil, tooltip: "AWS region (e.g. us-east-1)") {
            TextField("", text: $region)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }

          SettingRow(
            icon: "server.rack",
            title: "Endpoint",
            description: nil,
            tooltip: "Optional custom S3 endpoint for LocalStack or other S3-compatible storage"
          ) {
            TextField("", text: $endpoint)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }
        }

        if providerType == .cloudflareR2 {
          SettingRow(icon: "server.rack", title: "Endpoint", description: nil, tooltip: "R2 account endpoint URL") {
            TextField("", text: $endpoint)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }
        }

        SettingRow(icon: "link", title: "Custom Domain", description: nil, tooltip: "Public access domain (optional)") {
          TextField("", text: $customDomain)
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }
      }

      Section("File Expiration") {
        Picker("Expire Time", selection: $expireTime) {
          ForEach(CloudExpireTime.allCases, id: \.self) { time in
            Text(time.displayName).tag(time)
          }
        }

        if expireTime.isPermanent {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundColor(.orange)
              .font(.system(size: 12))
              .padding(.top, 1)
            Text(
              "No lifecycle rule will be set. Files will remain permanently unless manually deleted."
            )
            .font(.system(size: 11))
            .foregroundColor(.orange)
            .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.vertical, 4)
        } else {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
              .foregroundColor(.secondary)
              .font(.system(size: 12))
              .padding(.top, 1)
            Text(
              "A lifecycle rule will be configured on your bucket to auto-delete files after the selected period. Deletion may take up to 24 hours after expiration."
            )
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.vertical, 4)
        }
      }

      // Validation feedback
      Section {
        if let error = validationError {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.red)
              .font(.system(size: 12))
            Text(error)
              .font(.system(size: 11))
              .foregroundColor(.red)
          }
        }

        if validationSuccess {
          HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
              .font(.system(size: 12))
            Text("Connection verified successfully!")
              .font(.system(size: 11))
              .foregroundColor(.green)
          }
        }

        HStack(spacing: 12) {
          Button(action: saveAndTest) {
            if isValidating {
              ProgressView()
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)
              Text("Testing...")
            } else {
              Text("Save & Test")
            }
          }
          .disabled(!isFormValid || isValidating)

          if isEditing {
            Button("Cancel") {
              onCancel()
            }
          }
        }
      }
    }
    .onAppear {
      if isEditing {
        loadExistingConfig()
      }
    }
  }

  // MARK: - Validation

  private var isFormValid: Bool {
    !accessKey.trimmingCharacters(in: .whitespaces).isEmpty
      && !secretKey.trimmingCharacters(in: .whitespaces).isEmpty
      && !bucket.trimmingCharacters(in: .whitespaces).isEmpty
      && (providerType == .awsS3
        ? !region.trimmingCharacters(in: .whitespaces).isEmpty
        : !endpoint.trimmingCharacters(in: .whitespaces).isEmpty)
  }

  private func saveAndTest() {
    validationError = nil
    validationSuccess = false
    isValidating = true

    let config = CloudConfiguration(
      providerType: providerType,
      bucket: bucket.trimmingCharacters(in: .whitespaces),
      region: region.trimmingCharacters(in: .whitespaces),
      endpoint: endpoint.trimmingCharacters(in: .whitespaces).isEmpty
        ? nil : endpoint.trimmingCharacters(in: .whitespaces),
      customDomain: customDomain.trimmingCharacters(in: .whitespaces).isEmpty
        ? nil : customDomain.trimmingCharacters(in: .whitespaces),
      expireTime: expireTime
    )

    Task {
      do {
        try cloudManager.saveConfiguration(
          config,
          accessKey: accessKey.trimmingCharacters(in: .whitespaces),
          secretKey: secretKey.trimmingCharacters(in: .whitespaces)
        )
        try await cloudManager.validateCredentials()

        // Apply lifecycle rule (non-blocking — permission errors show as warning)
        do {
          try await cloudManager.applyLifecycleRule()
        } catch {
          // Lifecycle rule failed (likely missing permissions) — save still succeeds
          validationError = "Configuration saved, but lifecycle rule failed: \(error.localizedDescription). Ensure your credentials have lifecycle management permissions."
        }

        validationSuccess = true
        isValidating = false

        // Delay then close form
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        onSave()
      } catch {
        validationError = error.localizedDescription
        isValidating = false
      }
    }
  }

  private func loadExistingConfig() {
    guard let config = cloudManager.loadConfiguration() else { return }
    providerType = config.providerType
    bucket = config.bucket
    region = config.region
    endpoint = config.endpoint ?? ""
    customDomain = config.customDomain ?? ""
    expireTime = config.expireTime
    accessKey = cloudManager.loadAccessKey()
    secretKey = cloudManager.loadSecretKey()
  }
}

// MARK: - Upload Record Row

struct CloudUploadRecordRow: View {
  let record: CloudUploadRecord

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "doc.fill")
        .font(.system(size: 16))
        .foregroundColor(.secondary)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(record.fileName)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
        HStack(spacing: 8) {
          Text(record.formattedDate)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
          Text(record.formattedFileSize)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
          if record.isExpired {
            Text("Expired")
              .font(.system(size: 10, weight: .medium))
              .foregroundColor(.orange)
          }
        }
      }

      Spacer()

      Button(action: {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.publicURL.absoluteString, forType: .string)
      }) {
        Image(systemName: "doc.on.doc")
          .font(.system(size: 11))
      }
      .buttonStyle(.plain)
      .help("Copy link")
    }
    .padding(.vertical, 2)
  }
}

#Preview {
  CloudSettingsView()
    .frame(width: 600, height: 550)
}
