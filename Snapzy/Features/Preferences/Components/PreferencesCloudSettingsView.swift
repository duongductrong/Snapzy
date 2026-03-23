//
//  PreferencesCloudSettingsView.swift
//  Snapzy
//
//  Cloud storage configuration tab with password protection.
//  States: unconfigured (form), configured (masked summary), edit mode,
//  password initialization (existing users), password gate (edit verification).
//

import SwiftUI

/// Cloud settings tab in Preferences
struct CloudSettingsView: View {
  @ObservedObject private var cloudManager = CloudManager.shared
  @ObservedObject private var usageService = CloudUsageService.shared

  @State private var isEditing = false
  @State private var showResetConfirmation = false

  // Password gate states
  @State private var showPasswordGate = false
  @State private var passwordGateInput = ""
  @State private var passwordGateError: String?

  // Existing user password initialization
  @State private var showPasswordInit = false
  @State private var passwordInitCompleted = false

  var body: some View {
    Form {
      if showPasswordInit {
        CloudPasswordInitView(
          onComplete: {
            showPasswordInit = false
            passwordInitCompleted = true
          }
        )
      } else if cloudManager.isConfigured && !isEditing {
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
        passwordInitCompleted = false
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will remove all cloud credentials, protection password, and settings. This action cannot be undone.")
    }
    .sheet(isPresented: $showPasswordGate) {
      CloudPasswordGateView(
        onVerified: {
          showPasswordGate = false
          passwordGateInput = ""
          passwordGateError = nil
          isEditing = true
        },
        onReset: {
          showPasswordGate = false
          showResetConfirmation = true
        },
        onCancel: {
          showPasswordGate = false
          passwordGateInput = ""
          passwordGateError = nil
        }
      )
    }
    .onAppear {
      checkPasswordInitNeeded()
    }
  }

  // MARK: - Password Init Check

  private func checkPasswordInitNeeded() {
    guard cloudManager.isConfigured,
      !CloudPasswordService.shared.hasPassword,
      !UserDefaults.standard.bool(forKey: PreferencesKeys.cloudPasswordSkipped),
      !passwordInitCompleted
    else { return }
    showPasswordInit = true
  }

  // MARK: - Configured State

  private var configuredView: some View {
    Group {
      // Cloud stats at the very top
      cloudStatsSection

      Section("Cloud Provider") {
        if let config = cloudManager.cachedConfiguration {
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
            description: cloudManager.cachedMaskedAccessKey
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
              description: cloudManager.maskedEndpoint()
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
          Button(action: handleEditTapped) {
            Label("Edit", systemImage: "pencil")
          }

          Button(role: .destructive, action: { showResetConfirmation = true }) {
            Label("Reset", systemImage: "arrow.counterclockwise")
          }
          .foregroundColor(.red)
        }
        .padding(.top, 4)
      }
    }
  }

  private func handleEditTapped() {
    if CloudPasswordService.shared.hasPassword {
      showPasswordGate = true
    } else {
      isEditing = true
    }
  }

  // MARK: - Cloud Stats Section

  private var cloudStatsSection: some View {
    Section {
      if usageService.isLoading && usageService.usageInfo == nil {
        HStack {
          Spacer()
          ProgressView()
            .scaleEffect(0.8)
          Text("Loading stats...")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
          Spacer()
        }
        .padding(.vertical, 8)
      } else if let error = usageService.error, usageService.usageInfo == nil {
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.orange)
            .font(.system(size: 12))
          Text(error)
            .font(.system(size: 11))
            .foregroundColor(.orange)
        }
        .padding(.vertical, 4)
      } else {
        let info = usageService.usageInfo

        // 2×2 stats grid
        LazyVGrid(
          columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
          ],
          spacing: 8
        ) {
          CloudStatCard(
            icon: "externaldrive",
            label: "Storage",
            value: info?.formattedStorage ?? "—"
          )
          CloudStatCard(
            icon: "doc.on.doc",
            label: "Objects",
            value: info.map { "\($0.objectCount)" } ?? "—"
          )
          CloudStatCard(
            icon: "clock.arrow.circlepath",
            label: "Lifecycle",
            value: lifecycleShortLabel(info?.lifecycleRuleDays)
          )
          CloudStatCard(
            icon: "dollarsign.circle",
            label: "Est. Cost/mo",
            value: usageService.estimatedMonthlyCost
          )
        }

        // Footer: last updated + refresh
        HStack(spacing: 6) {
          if let fetchedAt = info?.fetchedAt {
            Text("Updated \(fetchedAt, style: .relative) ago")
              .font(.system(size: 10))
              .foregroundColor(.secondary)
          }

          Spacer()

          Button(action: {
            Task { await usageService.fetchUsage() }
          }) {
            HStack(spacing: 4) {
              if usageService.isLoading {
                ProgressView()
                  .scaleEffect(0.5)
                  .frame(width: 10, height: 10)
              } else {
                Image(systemName: "arrow.clockwise")
                  .font(.system(size: 10))
              }
              Text("Refresh")
                .font(.system(size: 10))
            }
            .foregroundColor(.secondary)
          }
          .buttonStyle(.plain)
          .disabled(usageService.isLoading)
        }
      }
    } header: {
      Text("Cloud Status")
    }
    .onAppear {
      if cloudManager.isConfigured && usageService.usageInfo == nil {
        Task { await usageService.fetchUsage() }
      }
    }
  }

  private func lifecycleShortLabel(_ days: Int?) -> String {
    guard let days = days else { return "None" }
    return "\(days)d expire"
  }
}

// MARK: - Stat Card

/// Compact stat card for the cloud stats grid
private struct CloudStatCard: View {
  let icon: String
  let label: String
  let value: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundColor(.secondary)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 1) {
        Text(label)
          .font(.system(size: 10))
          .foregroundColor(.secondary)
          .lineLimit(1)
        Text(value)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
  }
}

// MARK: - Password Gate Sheet

/// Modal sheet requiring password verification before allowing edit access
private struct CloudPasswordGateView: View {
  let onVerified: () -> Void
  let onReset: () -> Void
  let onCancel: () -> Void

  @State private var password = ""
  @State private var errorMessage: String?
  @State private var attempts = 0

  var body: some View {
    VStack(spacing: 20) {
      // Header
      VStack(spacing: 8) {
        Image(systemName: "lock.shield.fill")
          .font(.system(size: 32))
          .foregroundColor(.accentColor)
        Text("Password Required")
          .font(.headline)
        Text("Enter your protection password to edit cloud credentials.")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }

      // Password field
      VStack(alignment: .leading, spacing: 6) {
        SecureField("Protection Password", text: $password)
          .textFieldStyle(.roundedBorder)
          .onSubmit { verify() }

        if let error = errorMessage {
          Text(error)
            .font(.system(size: 11))
            .foregroundColor(.red)
        }
      }

      // Actions
      VStack(spacing: 10) {
        HStack(spacing: 12) {
          Button("Cancel") { onCancel() }
            .keyboardShortcut(.escape, modifiers: [])

          Button("Verify") { verify() }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(password.isEmpty)
            .buttonStyle(.borderedProminent)
        }

        Button(action: { onReset() }) {
          Text("Forgot Password? Reset Configuration")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(24)
    .frame(width: 360)
  }

  private func verify() {
    guard !password.isEmpty else { return }
    if CloudPasswordService.shared.verifyPassword(password) {
      onVerified()
    } else {
      attempts += 1
      errorMessage = "Incorrect password. Please try again. (\(attempts) attempt\(attempts > 1 ? "s" : ""))"
      password = ""
    }
  }
}

// MARK: - Password Initialization View (Existing Users)

/// Shown once for existing cloud users who haven't set a protection password
private struct CloudPasswordInitView: View {
  let onComplete: () -> Void

  @State private var password = ""
  @State private var confirmPassword = ""
  @State private var errorMessage: String?
  @State private var showSkipWarning = false

  var body: some View {
    Section {
      VStack(spacing: 16) {
        // Header
        VStack(spacing: 8) {
          Image(systemName: "lock.shield.fill")
            .font(.system(size: 28))
            .foregroundColor(.accentColor)
          Text("Protect Your Cloud Credentials")
            .font(.headline)
          Text("Set a password to prevent unauthorized access to your cloud configuration. This password will be required to view or edit your credentials.")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)

        // Password fields
        VStack(alignment: .leading, spacing: 8) {
          SettingRow(icon: "lock", title: "Protection Password", description: nil) {
            SecureField("", text: $password)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }

          SettingRow(icon: "lock.rotation", title: "Confirm Password", description: nil) {
            SecureField("", text: $confirmPassword)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }
        }

        if let error = errorMessage {
          HStack(spacing: 6) {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.red)
              .font(.system(size: 12))
            Text(error)
              .font(.system(size: 11))
              .foregroundColor(.red)
          }
        }

        // Actions
        HStack(spacing: 12) {
          Button("Set Password") {
            savePassword()
          }
          .disabled(password.isEmpty || confirmPassword.isEmpty)
          .buttonStyle(.borderedProminent)

          Button("Skip for Now") {
            showSkipWarning = true
          }
        }

        // Info note
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "info.circle")
            .foregroundColor(.secondary)
            .font(.system(size: 12))
            .padding(.top, 1)
          Text("If you forget this password, you will need to reset your cloud configuration and re-enter all credentials.")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
      }
      .padding(.vertical, 8)
    }
    .alert("Skip Password Protection?", isPresented: $showSkipWarning) {
      Button("Skip", role: .destructive) {
        UserDefaults.standard.set(true, forKey: PreferencesKeys.cloudPasswordSkipped)
        onComplete()
      }
      Button("Set Password", role: .cancel) {}
    } message: {
      Text("Without a password, anyone with access to your Mac can view and modify your cloud credentials. We strongly recommend setting a password.")
    }
  }

  private func savePassword() {
    guard password == confirmPassword else {
      errorMessage = "Passwords do not match."
      return
    }
    guard password.count >= 4 else {
      errorMessage = "Password must be at least 4 characters."
      return
    }
    do {
      try CloudPasswordService.shared.savePassword(password)
      onComplete()
    } catch {
      errorMessage = "Failed to save password: \(error.localizedDescription)"
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

  // Password fields
  @State private var protectionPassword = ""
  @State private var confirmProtectionPassword = ""

  @State private var isValidating = false
  @State private var validationError: String?
  @State private var validationSuccess = false
  @State private var showSkipPasswordWarning = false

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

      // Protection password section
      if !isEditing || !CloudPasswordService.shared.hasPassword {
        Section("Protection Password") {
          SettingRow(
            icon: "lock.shield",
            title: "Password",
            description: nil,
            tooltip: "Optional password to protect credentials from unauthorized access"
          ) {
            SecureField("Optional", text: $protectionPassword)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }

          if !protectionPassword.isEmpty {
            SettingRow(
              icon: "lock.rotation",
              title: "Confirm Password",
              description: nil,
              tooltip: "Re-enter the protection password"
            ) {
              SecureField("", text: $confirmProtectionPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            }
          }

          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "shield.checkered")
              .foregroundColor(.accentColor)
              .font(.system(size: 12))
              .padding(.top, 1)
            Text(
              "We recommend setting a password to protect your cloud credentials from unauthorized access. This password will be required to view or edit your configuration."
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
          Button(action: handleSave) {
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
    .alert("Proceed Without Password?", isPresented: $showSkipPasswordWarning) {
      Button("Skip", role: .destructive) {
        UserDefaults.standard.set(true, forKey: PreferencesKeys.cloudPasswordSkipped)
        saveAndTest()
      }
      Button("Set Password", role: .cancel) {}
    } message: {
      Text("Without a password, anyone with access to your Mac can view and modify your cloud credentials. We strongly recommend setting a password to protect your configuration.")
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

  private var isPasswordValid: Bool {
    // No password entered = valid (optional)
    if protectionPassword.isEmpty { return true }
    // If entered, must match and be >= 4 chars
    return protectionPassword == confirmProtectionPassword && protectionPassword.count >= 4
  }

  private func handleSave() {
    // Validate password fields first
    if !protectionPassword.isEmpty {
      guard protectionPassword == confirmProtectionPassword else {
        validationError = "Protection passwords do not match."
        return
      }
      guard protectionPassword.count >= 4 else {
        validationError = "Protection password must be at least 4 characters."
        return
      }
    }

    // If no password and no existing password, warn about skipping
    if protectionPassword.isEmpty && !CloudPasswordService.shared.hasPassword
      && !UserDefaults.standard.bool(forKey: PreferencesKeys.cloudPasswordSkipped)
    {
      showSkipPasswordWarning = true
      return
    }

    saveAndTest()
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

        // Apply lifecycle rule — treat failure as a save failure
        do {
          try await cloudManager.applyLifecycleRule()
        } catch {
          validationError = "Configuration saved, but lifecycle rule failed: \(error.localizedDescription). Ensure your credentials have lifecycle management permissions."
          isValidating = false
          // Don't set validationSuccess — form stays open for user to review
          return
        }

        // Save protection password if provided
        if !protectionPassword.isEmpty {
          do {
            try CloudPasswordService.shared.savePassword(protectionPassword)
            // Clear the skip flag since they set a password
            UserDefaults.standard.removeObject(forKey: PreferencesKeys.cloudPasswordSkipped)
          } catch {
            validationError = "Configuration saved, but password setup failed: \(error.localizedDescription)"
            isValidating = false
            return
          }
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


#Preview {
  CloudSettingsView()
    .frame(width: 600, height: 550)
}
