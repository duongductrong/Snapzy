//
//  PreferencesCloudCredentialExportSheet.swift
//  Snapzy
//
//  Passphrase prompt for exporting an encrypted cloud credential archive.
//

import AppKit
import SwiftUI

struct CloudCredentialExportSheet: View {
  let payload: CloudCredentialTransferPayload
  let onExported: (URL) -> Void
  let onCancel: () -> Void

  @State private var passphrase = ""
  @State private var confirmPassphrase = ""
  @State private var errorMessage: String?
  @State private var isExporting = false

  var body: some View {
    VStack(spacing: 20) {
      VStack(spacing: 8) {
        Image(systemName: "square.and.arrow.up.fill")
          .font(.system(size: 30))
          .foregroundColor(.accentColor)
        Text(L10n.CloudTransfer.exportTitle)
          .font(.headline)
        Text(L10n.CloudTransfer.exportDescription)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }

      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.CloudTransfer.archiveContents)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
          Text(
            L10n.CloudTransfer.archiveContentsSummary(
              payload.providerDisplayName,
              bucket: payload.configuration.bucket
            )
          )
            .font(.system(size: 12))
        }

        VStack(alignment: .leading, spacing: 6) {
          Text(L10n.CloudTransfer.archivePassphrase)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
          SecureField(
            L10n.CloudTransfer.minimumPassphrase(
              CloudCredentialTransferService.minimumPassphraseLength
            ),
            text: $passphrase
          )
          .textFieldStyle(.roundedBorder)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text(L10n.CloudTransfer.confirmPassphrase)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
          SecureField(L10n.CloudTransfer.reenterPassphrase, text: $confirmPassphrase)
            .textFieldStyle(.roundedBorder)
            .onSubmit { exportArchive() }
        }

        if let errorMessage {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 12))
              .foregroundColor(.red)
            Text(errorMessage)
              .font(.system(size: 11))
              .foregroundColor(.red)
          }
        }
      }

      HStack(spacing: 12) {
        Button(L10n.Common.cancel) {
          onCancel()
        }
        .keyboardShortcut(.escape, modifiers: [])

        Button(action: exportArchive) {
          if isExporting {
            ProgressView()
              .controlSize(.small)
          } else {
            Text(L10n.CloudTransfer.chooseDestination)
          }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(isExporting)
      }
    }
    .padding(24)
    .frame(width: 400)
  }

  private func exportArchive() {
    errorMessage = nil

    guard passphrase.count >= CloudCredentialTransferService.minimumPassphraseLength else {
      errorMessage = L10n.CloudTransfer.passphraseTooShort(
        CloudCredentialTransferService.minimumPassphraseLength
      )
      return
    }
    guard passphrase == confirmPassphrase else {
      errorMessage = L10n.CloudTransfer.passphrasesDoNotMatch
      return
    }
    guard let destinationURL = chooseExportDestinationURL() else { return }

    isExporting = true
    defer {
      isExporting = false
    }

    do {
      try CloudCredentialTransferService.exportArchive(
        payload: payload,
        to: destinationURL,
        passphrase: passphrase
      )
      onExported(destinationURL)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func chooseExportDestinationURL() -> URL? {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.allowedContentTypes = [CloudCredentialTransferService.archiveContentType]
    panel.nameFieldStringValue = CloudCredentialTransferService.suggestedArchiveFileName(for: payload)
    panel.title = L10n.CloudTransfer.exportTitle
    panel.message = L10n.CloudTransfer.savePanelMessage
    return panel.runModal() == .OK ? panel.url : nil
  }
}
