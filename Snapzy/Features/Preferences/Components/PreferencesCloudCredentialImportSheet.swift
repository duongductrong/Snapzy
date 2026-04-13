//
//  PreferencesCloudCredentialImportSheet.swift
//  Snapzy
//
//  Passphrase prompt for importing an encrypted cloud credential archive.
//

import SwiftUI

struct CloudCredentialImportSheet: View {
  let fileURL: URL
  let onImported: (CloudCredentialTransferPayload) -> Void
  let onCancel: () -> Void

  @State private var passphrase = ""
  @State private var errorMessage: String?
  @State private var isImporting = false

  var body: some View {
    VStack(spacing: 20) {
      VStack(spacing: 8) {
        Image(systemName: "square.and.arrow.down.fill")
          .font(.system(size: 30))
          .foregroundColor(.accentColor)
        Text(L10n.CloudTransfer.importTitle)
          .font(.headline)
        Text(L10n.CloudTransfer.importDescription)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }

      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.CloudTransfer.selectedArchive)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
          Text(fileURL.lastPathComponent)
            .font(.system(size: 12))
            .lineLimit(2)
            .textSelection(.enabled)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text(L10n.CloudTransfer.archivePassphrase)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
          SecureField(L10n.CloudTransfer.enterArchivePassphrase, text: $passphrase)
            .textFieldStyle(.roundedBorder)
            .onSubmit { importArchive() }
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

        Button(action: importArchive) {
          if isImporting {
            ProgressView()
              .controlSize(.small)
          } else {
            Text(L10n.Common.importAction)
          }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(passphrase.isEmpty || isImporting)
      }
    }
    .padding(24)
    .frame(width: 380)
  }

  private func importArchive() {
    guard !passphrase.isEmpty else { return }
    errorMessage = nil
    isImporting = true

    defer {
      isImporting = false
    }

    do {
      let payload = try CloudCredentialTransferService.importArchive(
        from: fileURL,
        passphrase: passphrase
      )
      onImported(payload)
    } catch {
      errorMessage = error.localizedDescription
      passphrase = ""
    }
  }
}
