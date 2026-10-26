//
//  PreferencesCloudSettingsView.swift
//  Snapzy
//
//  Cloud storage configuration tab with password protection.
//  States: unconfigured (form), configured (masked summary), edit mode,
//  password initialization (existing users), password gate (edit verification).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum CloudProtectedAction {
  case editCredentials
  case importCredentials
  case exportCredentials

  var passwordPrompt: String {
    switch self {
    case .editCredentials:
      return L10n.CloudSettings.editCredentialsPasswordPrompt
    case .importCredentials:
      return L10n.CloudSettings.importCredentialsPasswordPrompt
    case .exportCredentials:
      return L10n.CloudSettings.exportCredentialsPasswordPrompt
    }
  }
}

private struct ImportArchiveSelection: Identifiable {
  let id = UUID()
  let fileURL: URL
}

/// Cloud settings tab in Preferences
struct CloudSettingsView: View {
  @ObservedObject private var cloudManager = CloudManager.shared
  @ObservedObject private var usageService = CloudUsageService.shared
  @AppStorage(PreferencesKeys.cloudUploadsFloatingPosition)
  private var uploadsWindowPosition: CloudUploadFloatingPosition = .defaultPosition

  @State private var isEditing = false
  @State private var showResetConfirmation = false
  @State private var showImportReplaceConfirmation = false

  @State private var showPasswordGate = false
  @State private var pendingProtectedAction: CloudProtectedAction?
  @State private var importArchiveSelection: ImportArchiveSelection?
  @State private var showExportSheet = false
  @State private var exportPayload: CloudCredentialTransferPayload?
  @State private var importedPayload: CloudCredentialTransferPayload?
  @State private var importNotice: String?
  @State private var transferAlertMessage: String?

  // Existing user password initialization
  @State private var showPasswordInit = false
  @State private var passwordInitCompleted = false

  var body: some View {
    Form {
      Section {
      } header: {
        PreferencesPageHero(tab: .cloud, subtitle: L10n.CloudSettings.heroSubtitle)
      }

      if showPasswordInit {
        CloudPasswordInitView(
          onComplete: {
            showPasswordInit = false
            passwordInitCompleted = true
          }
        )
      } else if showsConfiguredView {
        configuredView
      } else {
        CloudCredentialFormView(
          isEditing: isEditing,
          importedPayload: importedPayload,
          importNotice: importNotice,
          onImport: handleImportTapped,
          onSave: {
            clearImportedDraft()
            isEditing = false
          },
          onCancel: {
            clearImportedDraft()
            isEditing = false
          }
        )
      }

      uploadsWindowSection
    }
    .formStyle(.grouped)
    .toolbar {
      if showsConfiguredView {
        configuredToolbar
      }
    }
    .alert(L10n.CloudSettings.resetConfigurationTitle, isPresented: $showResetConfirmation) {
      Button(L10n.CloudSettings.reset, role: .destructive) {
        cloudManager.clearConfiguration()
        passwordInitCompleted = false
      }
      Button(L10n.Common.cancel, role: .cancel) {}
    } message: {
      Text(L10n.CloudSettings.resetConfigurationMessage)
    }
    .alert(L10n.CloudSettings.importCredentialsTitle, isPresented: $showImportReplaceConfirmation) {
      Button(L10n.Common.importAction, role: .destructive) {
        beginImportFlow()
      }
      Button(L10n.Common.cancel, role: .cancel) {}
    } message: {
      Text(L10n.CloudSettings.importCredentialsMessage)
    }
    .alert(L10n.CloudSettings.transferAlertTitle, isPresented: transferAlertBinding) {
      Button(L10n.Common.ok, role: .cancel) {
        transferAlertMessage = nil
      }
    } message: {
      Text(transferAlertMessage ?? "")
    }
    .sheet(isPresented: $showPasswordGate) {
      CloudPasswordGateView(
        purposeDescription: pendingProtectedAction?.passwordPrompt
          ?? CloudProtectedAction.editCredentials.passwordPrompt,
        onVerified: {
          showPasswordGate = false
          performPendingProtectedAction()
        },
        onReset: {
          showPasswordGate = false
          pendingProtectedAction = nil
          showResetConfirmation = true
        },
        onCancel: {
          showPasswordGate = false
          pendingProtectedAction = nil
        }
      )
    }
    .sheet(item: $importArchiveSelection) { selection in
      CloudCredentialImportSheet(
        fileURL: selection.fileURL,
        onImported: handleImportedPayload,
        onCancel: { importArchiveSelection = nil }
      )
    }
    .sheet(isPresented: $showExportSheet, onDismiss: {
      exportPayload = nil
    }) {
      if let exportPayload {
        CloudCredentialExportSheet(
          payload: exportPayload,
          onExported: { destinationURL in
            showExportSheet = false
            transferAlertMessage = L10n.CloudTransfer.archiveSaved(destinationURL.path)
          },
          onCancel: { showExportSheet = false }
        )
      }
    }
    .onAppear {
      cloudManager.refreshCloudSummaryForDisplay()
      usageService.hydrateCachedUsageIfAvailable()
    }
    .onChange(of: uploadsWindowPosition) { newValue in
      CloudUploadHistoryWindowController.shared.updatePosition(newValue)
    }
  }

  // MARK: - Password Init Check

  private func checkPasswordInitNeeded() {
    // Intentionally disabled to avoid passive keychain reads when the Cloud tab opens.
  }

  // MARK: - Configured State

  private var configuredView: some View {
    Group {
      if let config = cloudManager.cachedConfiguration {
        Section(L10n.CloudSettings.providerSection) {
          CloudProviderSummaryRow(config: config)

          if config.providerType == .googleDrive {
            LabeledContent(L10n.CloudSettings.googleFolderName) {
              Text(verbatim: config.bucket.isEmpty ? "Snapzy" : config.bucket)
            }
            LabeledContent(L10n.CloudSettings.credentialsSection) {
              Text(L10n.CloudSettings.storedSecurelyInKeychain)
            }
          } else {
            LabeledContent(L10n.CloudSettings.accessKey) {
              Text(verbatim: cloudManager.cachedMaskedAccessKey)
                .font(.system(.body, design: .monospaced))
            }

            if !config.region.isEmpty && config.providerType == .awsS3 {
              LabeledContent(L10n.CloudSettings.region) {
                Text(verbatim: config.region)
              }
            }

            if let endpoint = config.endpoint, !endpoint.isEmpty {
              LabeledContent(L10n.CloudSettings.endpoint) {
                Text(verbatim: cloudManager.maskedEndpoint())
                  .lineLimit(1)
                  .truncationMode(.middle)
              }
            }

            if let domain = config.customDomain, !domain.isEmpty {
              LabeledContent(L10n.CloudSettings.customDomain) {
                Text(verbatim: domain)
                  .lineLimit(1)
                  .truncationMode(.middle)
              }
            }

            LabeledContent(L10n.CloudSettings.expireTime) {
              Text(config.expireTime.displayName)
            }
          }
        }

        if config.providerType != .googleDrive {
          cloudStatsSection
        }
      }
    }
  }

  /// Header actions for a saved configuration, mirroring the Shortcuts tab's toolbar:
  /// quiet icon buttons for the secondary actions, a labelled Edit as the primary one.
  @ToolbarContentBuilder
  private var configuredToolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      Menu {
        Button(action: handleImportTapped) {
          Label(L10n.Common.importAction, systemImage: "square.and.arrow.down")
        }
        Button(action: handleExportTapped) {
          Label(L10n.Common.exportAction, systemImage: "square.and.arrow.up")
        }
      } label: {
        Label(L10n.CloudSettings.transferSection, systemImage: "arrow.up.arrow.down")
      }
      .menuIndicator(.hidden)
      .help(L10n.CloudSettings.transferSection)

      Button(role: .destructive) {
        showResetConfirmation = true
      } label: {
        Label(L10n.CloudSettings.reset, systemImage: "arrow.counterclockwise")
      }
      .help(L10n.CloudSettings.resetConfigurationTitle)

      Button(action: handleEditTapped) {
        Label(L10n.CloudSettings.edit, systemImage: "pencil")
          .labelStyle(.titleAndIcon)
          .padding(.horizontal, 4)
      }
      .help(L10n.CloudSettings.editCredentialsPasswordPrompt)
    }
  }

  private var showsConfiguredView: Bool {
    !showPasswordInit && cloudManager.isConfigured && !isEditing
  }

  private var uploadsWindowSection: some View {
    Section(L10n.CloudSettings.uploadsWindowSection) {
      SettingRow(
        title: L10n.CloudSettings.uploadsWindowPositionTitle,
        description: L10n.CloudSettings.uploadsWindowPositionDescription
      ) {
        Picker("", selection: $uploadsWindowPosition) {
          ForEach(CloudUploadFloatingPosition.allCases) { position in
            Text(position.displayName).tag(position)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .frame(width: 140, alignment: .trailing)
      }
    }
  }

  private func handleEditTapped() {
    beginProtectedAction(.editCredentials)
  }

  private func handleImportTapped() {
    if cloudManager.isConfigured {
      beginProtectedAction(.importCredentials)
    } else {
      beginImportFlow()
    }
  }

  private func handleExportTapped() {
    beginProtectedAction(.exportCredentials)
  }

  private func beginProtectedAction(_ action: CloudProtectedAction) {
    pendingProtectedAction = action
    if CloudPasswordService.shared.shouldRequirePasswordForEdit() {
      showPasswordGate = true
    } else {
      performProtectedAction(action)
    }
  }

  private func performPendingProtectedAction() {
    guard let pendingProtectedAction else { return }
    performProtectedAction(pendingProtectedAction)
  }

  private func performProtectedAction(_ action: CloudProtectedAction) {
    pendingProtectedAction = nil

    switch action {
    case .editCredentials:
      clearImportedDraft()
      isEditing = true
    case .importCredentials:
      showImportReplaceConfirmation = true
    case .exportCredentials:
      do {
        exportPayload = try cloudManager.exportTransferPayload()
        showExportSheet = true
      } catch {
        transferAlertMessage = error.localizedDescription
      }
    }
  }

  private func beginImportFlow() {
    guard importArchiveSelection == nil else { return }
    guard let selectedURL = selectImportArchiveURL() else { return }
    importArchiveSelection = ImportArchiveSelection(fileURL: selectedURL)
  }

  private func handleImportedPayload(_ payload: CloudCredentialTransferPayload) {
    importArchiveSelection = nil
    importedPayload = payload
    importNotice = L10n.CloudTransfer.importedCredentialsLoaded

    if cloudManager.isConfigured {
      isEditing = true
    }
  }

  private func clearImportedDraft() {
    importedPayload = nil
    importNotice = nil
  }

  private func selectImportArchiveURL() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [CloudCredentialTransferService.archiveContentType]
    panel.title = L10n.CloudTransfer.importTitle
    panel.message = L10n.CloudTransfer.chooserMessage
    return panel.runModal() == .OK ? panel.url : nil
  }

  private var transferAlertBinding: Binding<Bool> {
    Binding(
      get: { transferAlertMessage != nil },
      set: { isPresented in
        if !isPresented {
          transferAlertMessage = nil
        }
      }
    )
  }

  // MARK: - Cloud Stats Section

  private var cloudStatsSection: some View {
    Section {
      if usageService.isLoading && usageService.usageInfo == nil {
        HStack {
          Spacer()
          ProgressView()
            .scaleEffect(0.8)
          Text(L10n.CloudUsage.loadingStats)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
          Spacer()
        }
        .padding(.vertical, 8)
      } else if let error = usageService.error, usageService.usageInfo == nil {
        // If cloud is configured but usage fetch failed, show error with config context
        if cloudManager.isConfigured {
          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))
              Text(error)
                .font(.system(size: 11))
                .foregroundColor(.orange)
            }
            // Still show stats grid with placeholder values
            LazyVGrid(
              columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
              ],
              spacing: 8
            ) {
              CloudStatCard(
                icon: "externaldrive",
                label: L10n.CloudUsage.storage,
                value: "—"
              )
              CloudStatCard(
                icon: "doc.on.doc",
                label: L10n.CloudUsage.objects,
                value: "—"
              )
              CloudStatCard(
                icon: "clock.arrow.circlepath",
                label: L10n.CloudUsage.lifecycle,
                value: lifecycleShortLabel(nil)
              )
              CloudStatCard(
                icon: "dollarsign.circle",
                label: L10n.CloudUsage.estimatedCostPerMonth,
                value: "—"
              )
            }
          }
        } else {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundColor(.orange)
              .font(.system(size: 12))
            Text(error)
              .font(.system(size: 11))
              .foregroundColor(.orange)
          }
          .padding(.vertical, 4)
        }
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
            label: L10n.CloudUsage.storage,
            value: info?.formattedStorage ?? "—"
          )
          CloudStatCard(
            icon: "doc.on.doc",
            label: L10n.CloudUsage.objects,
            value: info.map { "\($0.objectCount)" } ?? "—"
          )
          CloudStatCard(
            icon: "clock.arrow.circlepath",
            label: L10n.CloudUsage.lifecycle,
            value: lifecycleShortLabel(info?.lifecycleRuleDays)
          )
          CloudStatCard(
            icon: "dollarsign.circle",
            label: L10n.CloudUsage.estimatedCostPerMonth,
            value: usageService.estimatedMonthlyCost
          )
        }

        if let refreshError = usageService.error, usageService.usageInfo != nil {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundColor(.orange)
              .font(.system(size: 11))
            Text(refreshError)
              .font(.system(size: 10))
              .foregroundColor(.orange)
          }
          .padding(.top, 2)
        }
      }
    } header: {
      HStack {
        Text(L10n.CloudUsage.cloudStatus)
        Spacer()
        Button {
          Task { await usageService.fetchUsage(forceRefresh: true) }
        } label: {
          if usageService.isLoading {
            ProgressView()
              .controlSize(.mini)
          } else {
            Text(L10n.Common.refresh)
          }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .textCase(nil)
        .disabled(usageService.isLoading)
      }
    } footer: {
      if let fetchedAt = usageService.usageInfo?.fetchedAt {
        (
          Text("\(L10n.CloudUsage.updatedPrefix) ")
          + Text(fetchedAt, style: .relative)
          + Text(" \(L10n.CloudUsage.agoSuffix)")
        )
          .font(.caption)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }

  private func lifecycleShortLabel(_ days: Int?) -> String {
    guard let days = days else { return L10n.CloudUsage.none }
    return L10n.CloudUsage.daysExpire(days)
  }
}

// MARK: - Provider Summary

/// Lead row of the provider card: provider tile, name, bucket, and connection status.
private struct CloudProviderSummaryRow: View {
  let config: CloudConfiguration

  var body: some View {
    HStack(spacing: 12) {
      PreferencesSymbolTile(symbol: symbol, size: 30, tint: PreferencesTab.cloud.iconTint, duotone: true)

      VStack(alignment: .leading, spacing: 2) {
        Text(config.providerType.displayName)
          .font(.system(size: 13, weight: .medium))
        Text(verbatim: subtitle)
          .font(.system(size: 11))
          .foregroundStyle(Color.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer(minLength: 8)

      Label {
        Text(config.providerType == .googleDrive ? L10n.CloudSettings.googleAuthorized : L10n.CloudSettings.connected)
      } icon: {
        Circle()
          .fill(Color.green)
          .frame(width: 7, height: 7)
      }
      .font(.system(size: 11))
      .foregroundStyle(Color.secondary)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  private var symbol: String {
    switch config.providerType {
    case .awsS3: return "externaldrive.fill"
    case .cloudflareR2: return "cloud.fill"
    case .googleDrive: return "folder.fill"
    }
  }

  private var subtitle: String {
    if config.providerType == .googleDrive {
      return config.bucket.isEmpty ? "Snapzy" : config.bucket
    }
    return config.bucket
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
  let purposeDescription: String
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
        Text(L10n.CloudSettings.passwordRequiredTitle)
          .font(.headline)
        Text(purposeDescription)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }

      // Password field
      VStack(alignment: .leading, spacing: 6) {
        SecureField(L10n.CloudSettings.protectionPassword, text: $password)
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
          Button(L10n.Common.cancel) { onCancel() }
            .keyboardShortcut(.escape, modifiers: [])

          Button(L10n.CloudSettings.verify) { verify() }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(password.isEmpty)
            .buttonStyle(.borderedProminent)
        }

        Button(action: { onReset() }) {
          Text(L10n.CloudSettings.forgotPasswordResetConfiguration)
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
    switch CloudPasswordService.shared.verifyPassword(password) {
    case .verified:
      onVerified()
    case .incorrectPassword:
      attempts += 1
      errorMessage = L10n.CloudSettings.incorrectPasswordAttempts(attempts)
      password = ""
    case .unavailable(let message):
      errorMessage = message
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
          Text(L10n.CloudSettings.protectCredentialsTitle)
            .font(.headline)
          Text(L10n.CloudSettings.protectCredentialsDescription)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)

        // Password fields
        VStack(alignment: .leading, spacing: 8) {
          SettingRow(title: L10n.CloudSettings.protectionPassword, description: nil) {
            SecureField("", text: $password)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }

          SettingRow(title: L10n.CloudSettings.confirmPassword, description: nil) {
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
          Button(L10n.CloudSettings.setPassword) {
            savePassword()
          }
          .disabled(password.isEmpty || confirmPassword.isEmpty)
          .buttonStyle(.borderedProminent)

          Button(L10n.CloudSettings.skipForNow) {
            showSkipWarning = true
          }
        }

        // Info note
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "info.circle")
            .foregroundColor(.secondary)
            .font(.system(size: 12))
            .padding(.top, 1)
          Text(L10n.CloudSettings.forgotPasswordInfo)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
      }
      .padding(.vertical, 8)
    }
    .alert(L10n.CloudSettings.skipPasswordProtectionTitle, isPresented: $showSkipWarning) {
      Button(L10n.CloudSettings.skip, role: .destructive) {
        UserDefaults.standard.set(true, forKey: PreferencesKeys.cloudPasswordSkipped)
        onComplete()
      }
      Button(L10n.CloudSettings.setPassword, role: .cancel) {}
    } message: {
      Text(L10n.CloudSettings.skipPasswordProtectionMessage)
    }
  }

  private func savePassword() {
    guard password == confirmPassword else {
      errorMessage = L10n.CloudSettings.passwordsDoNotMatch
      return
    }
    guard password.count >= 4 else {
      errorMessage = L10n.CloudSettings.passwordMinimumLength(4)
      return
    }
    do {
      try CloudPasswordService.shared.savePassword(password)
      onComplete()
    } catch {
      errorMessage = L10n.CloudSettings.failedToSavePassword(error.localizedDescription)
    }
  }
}

// MARK: - Credential Form

/// Reusable form for creating or editing cloud credentials
private struct CloudCredentialFormView: View {
  let isEditing: Bool
  let importedPayload: CloudCredentialTransferPayload?
  let importNotice: String?
  let onImport: (() -> Void)?
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

  // Google Drive specific fields
  @State private var googleClientId = ""
  @State private var googleClientSecret = ""
  @State private var googleFolderName = "Snapzy"
  @State private var isAuthorizing = false
  @State private var authorizationSuccess = false
  @State private var googleRefreshToken = ""
  @State private var googleUserEmail = ""

  // Password fields
  @State private var protectionPassword = ""
  @State private var confirmProtectionPassword = ""

  @State private var isValidating = false
  @State private var validationError: String?
  @State private var validationSuccess = false
  @State private var showSkipPasswordWarning = false
  @State private var hasExistingPassword = false
  @State private var showLimitedPermissionWarning = false

  var body: some View {
    Group {
      if let importNotice {
        Section {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle.fill")
              .foregroundColor(.accentColor)
              .font(.system(size: 12))
              .padding(.top, 1)
            Text(importNotice)
              .font(.system(size: 11))
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.vertical, 4)
        }
      }

      if !isEditing, let onImport {
        Section(L10n.CloudSettings.transferSection) {
          Button(action: onImport) {
            Label(L10n.CloudSettings.importEncryptedArchive, systemImage: "square.and.arrow.down")
          }
          .controlSize(.regular)

          Text(L10n.CloudSettings.importEncryptedArchiveDescription)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
      }

      Section(L10n.CloudSettings.providerSection) {
        SettingRow(
          title: L10n.CloudSettings.provider,
          description: nil,
          tooltip: L10n.CloudSettings.providerTooltip
        ) {
          Picker("", selection: $providerType) {
            ForEach(CloudProviderType.allCases, id: \.self) { type in
              Text(type.displayName).tag(type)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      }

      if providerType == .googleDrive {
        Section(L10n.CloudSettings.googleCredentialsSection) {
          SettingRow(
            title: L10n.CloudSettings.googleClientId,
            description: nil,
            tooltip: nil
          ) {
            TextField("", text: $googleClientId)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }

          SettingRow(
            title: L10n.CloudSettings.googleClientSecret,
            description: nil,
            tooltip: nil
          ) {
            HStack(spacing: 6) {
              if showSecretKey {
                TextField("", text: $googleClientSecret)
                  .textFieldStyle(.roundedBorder)
                  .frame(width: 210)
              } else {
                SecureField("", text: $googleClientSecret)
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

          Text(L10n.CloudSettings.googleSetupGuide)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
        }

        Section(L10n.CloudSettings.googleAuthSection) {
          HStack(spacing: 12) {
            Button(action: startGoogleAuthorization) {
              HStack(spacing: 6) {
                if isAuthorizing {
                  ProgressView().controlSize(.small)
                } else if authorizationSuccess {
                  Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
                Text(isAuthorizing ? L10n.CloudSettings.googleAuthorizing : (authorizationSuccess ? L10n.CloudSettings.googleAuthorized : L10n.CloudSettings.googleAuthorize))
              }
            }
            .controlSize(.regular)
            .disabled(googleClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAuthorizing)

            if !googleUserEmail.isEmpty {
              Text(L10n.CloudSettings.googleConnectedAs(googleUserEmail))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
          }
        }

        Section(L10n.CloudSettings.googleFolderSection) {
          SettingRow(
            title: L10n.CloudSettings.googleFolderName,
            description: nil,
            tooltip: nil
          ) {
            TextField("Snapzy", text: $googleFolderName)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }

          Text(L10n.CloudSettings.googleFolderDescription)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
        }
      } else {
        Section(L10n.CloudSettings.credentialsSection) {
          SettingRow(
            title: L10n.CloudSettings.accessKeyID,
            description: nil,
            tooltip: L10n.CloudSettings.accessKeyTooltip
          ) {
            TextField("", text: $accessKey)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }

          SettingRow(
            title: L10n.CloudSettings.secretAccessKey,
            description: nil,
            tooltip: L10n.CloudSettings.secretKeyTooltip
          ) {
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

        Section(L10n.CloudSettings.storageSection) {
          SettingRow(
            title: L10n.CloudSettings.bucketName,
            description: nil,
            tooltip: L10n.CloudSettings.bucketTooltip
          ) {
            TextField("", text: $bucket)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }

          if providerType == .awsS3 {
            SettingRow(
              title: L10n.CloudSettings.region,
              description: nil,
              tooltip: L10n.CloudSettings.regionTooltip
            ) {
              TextField("", text: $region)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            }

            SettingRow(
              title: L10n.CloudSettings.endpoint,
              description: nil,
              tooltip: L10n.CloudSettings.endpointTooltipS3
            ) {
              TextField("", text: $endpoint)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            }
          }

          if providerType == .cloudflareR2 {
            SettingRow(
              title: L10n.CloudSettings.endpoint,
              description: nil,
              tooltip: L10n.CloudSettings.endpointTooltipR2
            ) {
              TextField("", text: $endpoint)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            }
          }

          SettingRow(
            title: L10n.CloudSettings.customDomain,
            description: nil,
            tooltip: L10n.CloudSettings.customDomainTooltip
          ) {
            TextField("", text: $customDomain)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }
        }

        Section(L10n.CloudSettings.fileExpirationSection) {
          Picker(L10n.CloudSettings.expireTime, selection: $expireTime) {
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
              Text(L10n.CloudSettings.noLifecycleRuleWarning)
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
              Text(L10n.CloudSettings.lifecycleRuleInfo)
              .font(.system(size: 11))
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
          }
        }
      }

      // Protection password section
      if !isEditing || !hasExistingPassword {
        Section(L10n.CloudSettings.protectionPasswordSection) {
          SettingRow(
            title: L10n.CloudSettings.password,
            description: nil,
            tooltip: L10n.CloudSettings.passwordTooltip
          ) {
            SecureField(L10n.CloudSettings.optional, text: $protectionPassword)
              .textFieldStyle(.roundedBorder)
              .frame(width: 240)
          }

          if !protectionPassword.isEmpty {
            SettingRow(
              title: L10n.CloudSettings.confirmPassword,
              description: nil,
              tooltip: L10n.CloudSettings.confirmPasswordTooltip
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
            Text(L10n.CloudSettings.protectionRecommendation)
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
            Text(L10n.CloudSettings.connectionVerifiedSuccessfully)
              .font(.system(size: 11))
              .foregroundColor(.green)
          }
        }

        if showLimitedPermissionWarning {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundColor(.orange)
              .font(.system(size: 12))
              .padding(.top, 1)
            Text(L10n.CloudSettings.limitedPermissionsWarning)
              .font(.system(size: 11))
              .foregroundColor(.orange)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.vertical, 4)
        }

        HStack(spacing: 12) {
          Button(action: handleSave) {
            if isValidating {
              ProgressView()
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)
              Text(L10n.CloudSettings.testing)
            } else {
              Text(L10n.CloudSettings.saveAndTest)
            }
          }
          .disabled(!isFormValid || isValidating)

          if isEditing {
            Button(L10n.Common.cancel) {
              onCancel()
            }
          }
        }
        .controlSize(.regular)
        .padding(.top, 4)
      }
    }
    .onAppear {
      refreshPasswordState()
      applyInitialFormState()
    }
    .onChange(of: importedPayload) { newValue in
      guard let newValue else { return }
      applyImportedPayload(newValue)
    }
    .alert(L10n.CloudSettings.proceedWithoutPasswordTitle, isPresented: $showSkipPasswordWarning) {
      Button(L10n.CloudSettings.skip, role: .destructive) {
        UserDefaults.standard.set(true, forKey: PreferencesKeys.cloudPasswordSkipped)
        saveAndTest()
      }
      Button(L10n.CloudSettings.setPassword, role: .cancel) {}
    } message: {
      Text(L10n.CloudSettings.proceedWithoutPasswordMessage)
    }
  }

  // MARK: - Validation

  private var isFormValid: Bool {
    if providerType == .googleDrive {
      return !googleClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && authorizationSuccess
    }
    return !accessKey.trimmingCharacters(in: .whitespaces).isEmpty
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

  private func startGoogleAuthorization() {
    validationError = nil
    isAuthorizing = true
    authorizationSuccess = false

    Task {
      do {
        let tokens = try await GoogleDriveOAuthService.shared.startAuthorization(
          clientId: googleClientId.trimmingCharacters(in: .whitespacesAndNewlines),
          clientSecret: googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        googleRefreshToken = tokens.refreshToken
        googleUserEmail = try await GoogleDriveOAuthService.shared.fetchUserEmail(accessToken: tokens.accessToken)
        authorizationSuccess = true
      } catch {
        validationError = error.localizedDescription
      }
      isAuthorizing = false
    }
  }

  private func handleSave() {
    // Validate password fields first
    if !protectionPassword.isEmpty {
      guard protectionPassword == confirmProtectionPassword else {
        validationError = L10n.CloudSettings.protectionPasswordsDoNotMatch
        return
      }
      guard protectionPassword.count >= 4 else {
        validationError = L10n.CloudSettings.protectionPasswordMinimumLength(4)
        return
      }
    }

    // If no password and no existing password, warn about skipping
    if protectionPassword.isEmpty && !hasExistingPassword
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
    showLimitedPermissionWarning = false
    isValidating = true

    let isGoogle = providerType == .googleDrive

    let config = CloudConfiguration(
      providerType: providerType,
      bucket: isGoogle ? googleFolderName.trimmingCharacters(in: .whitespaces) : bucket.trimmingCharacters(in: .whitespaces),
      region: isGoogle ? "" : region.trimmingCharacters(in: .whitespaces),
      endpoint: isGoogle ? nil : (endpoint.trimmingCharacters(in: .whitespaces).isEmpty ? nil : endpoint.trimmingCharacters(in: .whitespaces)),
      customDomain: isGoogle ? nil : (customDomain.trimmingCharacters(in: .whitespaces).isEmpty ? nil : customDomain.trimmingCharacters(in: .whitespaces)),
      expireTime: isGoogle ? .permanent : expireTime
    )

    Task {
      let trimmedAccessKey = isGoogle ? googleClientId.trimmingCharacters(in: .whitespacesAndNewlines) : accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
      let trimmedSecretKey = isGoogle ? googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines) : secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
      let refreshToken = isGoogle ? googleRefreshToken : nil

      do {
        try await cloudManager.validateCredentials(
          config: config,
          accessKey: trimmedAccessKey,
          secretKey: trimmedSecretKey,
          googleRefreshToken: refreshToken
        )

        if !isGoogle {
          do {
            try await cloudManager.applyLifecycleRule(
              config: config,
              accessKey: trimmedAccessKey,
              secretKey: trimmedSecretKey
            )
          } catch {
            showLimitedPermissionWarning = true
            DiagnosticLogger.shared.log(
              .warning,
              .cloud,
              "Cloud lifecycle rule update failed during setup; continuing without it",
              context: ["error": error.localizedDescription]
            )
          }
        }

        try cloudManager.saveConfiguration(
          config,
          accessKey: trimmedAccessKey,
          secretKey: trimmedSecretKey,
          googleRefreshToken: refreshToken
        )

        if !protectionPassword.isEmpty {
          do {
            try CloudPasswordService.shared.savePassword(protectionPassword)
            hasExistingPassword = true
            // Clear the skip flag since they set a password
            UserDefaults.standard.removeObject(forKey: PreferencesKeys.cloudPasswordSkipped)
          } catch {
            validationError = L10n.CloudSettings.configurationSavedButPasswordSetupFailed(
              error.localizedDescription
            )
            isValidating = false
            return
          }
        }

        validationSuccess = true
        isValidating = false
        Task { await CloudUsageService.shared.fetchUsage(forceRefresh: true) }

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

    if config.providerType == .googleDrive {
      googleClientId = accessKey
      googleClientSecret = secretKey
      googleFolderName = bucket
      if let token = cloudManager.loadGoogleRefreshToken(), !token.isEmpty {
        googleRefreshToken = token
        authorizationSuccess = true
      }
    }
  }

  private func refreshPasswordState() {
    hasExistingPassword = CloudPasswordService.shared.hasPasswordConfigured
  }

  private func applyInitialFormState() {
    if let importedPayload {
      applyImportedPayload(importedPayload)
    } else if isEditing {
      loadExistingConfig()
    }
  }

  private func applyImportedPayload(_ payload: CloudCredentialTransferPayload) {
    providerType = payload.configuration.providerType
    bucket = payload.configuration.bucket
    region = payload.configuration.region
    endpoint = payload.configuration.endpoint ?? ""
    customDomain = payload.configuration.customDomain ?? ""
    expireTime = payload.configuration.expireTime
    accessKey = payload.accessKey
    secretKey = payload.secretKey

    if payload.configuration.providerType == .googleDrive {
      googleClientId = payload.googleClientId ?? payload.accessKey
      googleClientSecret = payload.googleClientSecret ?? payload.secretKey
      googleFolderName = payload.configuration.bucket
      googleRefreshToken = payload.googleRefreshToken ?? ""
      authorizationSuccess = !googleRefreshToken.isEmpty
    }

    validationError = nil
    validationSuccess = false
  }
}


#Preview {
  CloudSettingsView()
    .frame(width: 600, height: 550)
}
