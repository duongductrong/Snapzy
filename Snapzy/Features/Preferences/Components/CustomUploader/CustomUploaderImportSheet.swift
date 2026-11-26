//
//  CustomUploaderImportSheet.swift
//  Snapzy
//
//  Review step after reading a ShareX .sxcu file: shows importer warnings and lets the
//  user move credential-looking values into the secret store before the uploader is added.
//

import SwiftUI

struct CustomUploaderImportSheet: View {
  /// Adds the reviewed uploader; a thrown error (e.g. the 20-uploader limit) is shown in the sheet.
  let onAdd: (CustomUploader) throws -> Void
  let onCancel: () -> Void

  private let warnings: [CustomUploaderImportWarning]
  private let candidates: [CustomUploaderSecretCandidate]

  @State private var uploader: CustomUploader
  @State private var secretNames: [String: String]
  @State private var storedReferences: [String: String] = [:]
  @State private var secretErrors: [String: String] = [:]
  @State private var addError: String?

  init(
    result: CustomUploaderImportResult,
    onAdd: @escaping (CustomUploader) throws -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.onAdd = onAdd
    self.onCancel = onCancel
    self.warnings = result.warnings
    self.candidates = result.secretCandidates
    _uploader = State(initialValue: result.uploader)
    _secretNames = State(
      initialValue: Dictionary(
        result.secretCandidates.map { ($0.id, $0.suggestedSecretName) },
        uniquingKeysWith: { first, _ in first }
      )
    )
  }

  /// Nil hides "Store as Secret" entirely (no secret store installed).
  private var secretProvider: CustomUploaderSecretResolving? {
    CustomUploaderSecrets.provider
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "square.and.arrow.down")
          .font(.system(size: 20))
          .foregroundColor(.accentColor)
        Text(L10n.CustomUploader.importedTitle(uploader.name))
          .font(.headline)
          .lineLimit(1)
        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 4)

      Form {
        Section {
          LabeledContent(L10n.Common.name) {
            Text(verbatim: uploader.name)
          }
          LabeledContent(L10n.CustomUploader.requestURL) {
            Text(verbatim: "\(uploader.method.rawValue) \(uploader.url)")
              .font(.system(size: 11, design: .monospaced))
              .lineLimit(2)
              .truncationMode(.middle)
              .textSelection(.enabled)
          }
        }

        if !warnings.isEmpty {
          Section(L10n.CustomUploader.importWarningsHeader) {
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
              Label {
                Text(warning.message)
                  .font(.system(size: 12))
                  .fixedSize(horizontal: false, vertical: true)
              } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundColor(.orange)
              }
            }
          }
        }

        if let secretProvider, !candidates.isEmpty {
          Section {
            ForEach(candidates) { candidate in
              candidateRow(candidate, provider: secretProvider)
            }
          } footer: {
            Text(L10n.CustomUploader.secretCandidatesHeader)
              .font(.system(size: 11))
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .formStyle(.grouped)

      Divider()

      HStack(spacing: 12) {
        if let addError {
          Label(addError, systemImage: "xmark.circle.fill")
            .font(.system(size: 11))
            .foregroundColor(.red)
            .lineLimit(2)
        }
        Spacer()
        Button(L10n.Common.cancel, action: onCancel)
          .keyboardShortcut(.escape, modifiers: [])
        Button(L10n.Common.importAction) {
          do {
            try onAdd(uploader)
          } catch {
            addError = error.localizedDescription
          }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: [])
      }
      .padding(16)
    }
    .frame(width: 520, height: 520)
  }

  @ViewBuilder
  private func candidateRow(_ candidate: CustomUploaderSecretCandidate, provider: CustomUploaderSecretResolving) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text(verbatim: candidate.fieldName)
          .font(.system(.body, design: .monospaced))
        Text(locationLabel(candidate.location))
          .font(.system(size: 11))
          .foregroundColor(.secondary)
        Spacer()
      }

      if let reference = storedReferences[candidate.id] {
        Label(L10n.CustomUploader.storedAsSecret(reference), systemImage: "checkmark.seal.fill")
          .font(.system(size: 11))
          .foregroundColor(.green)
      } else {
        HStack(spacing: 8) {
          TextField(L10n.CustomUploader.secretName, text: secretNameBinding(for: candidate))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
          Button(L10n.CustomUploader.storeAsSecret) {
            store(candidate, provider: provider)
          }
          .disabled(!CustomUploaderSecrets.isValidName(secretNames[candidate.id] ?? ""))
        }
        if let error = secretErrors[candidate.id] {
          Text(error)
            .font(.system(size: 11))
            .foregroundColor(.red)
        } else if !CustomUploaderSecrets.isValidName(secretNames[candidate.id] ?? "") {
          Text(L10n.CustomUploader.invalidSecretName)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
      }
    }
    .padding(.vertical, 2)
  }

  private func secretNameBinding(for candidate: CustomUploaderSecretCandidate) -> Binding<String> {
    Binding(
      get: { secretNames[candidate.id] ?? "" },
      set: { secretNames[candidate.id] = $0 }
    )
  }

  private func store(_ candidate: CustomUploaderSecretCandidate, provider: CustomUploaderSecretResolving) {
    let name = (secretNames[candidate.id] ?? "").trimmingCharacters(in: .whitespaces)
    guard CustomUploaderSecrets.isValidName(name) else { return }
    do {
      try CustomUploaderSXCUImporter.storeSecret(candidate, secretName: name, in: &uploader, provider: provider)
      storedReferences[candidate.id] = CustomUploaderSecrets.reference(to: name)
      secretErrors[candidate.id] = nil
    } catch {
      secretErrors[candidate.id] = error.localizedDescription
    }
  }

  private func locationLabel(_ location: CustomUploaderSecretCandidate.Location) -> String {
    switch location {
    case .header: return L10n.CustomUploader.locationHeader
    case .query: return L10n.CustomUploader.locationQuery
    case .bodyField: return L10n.CustomUploader.locationBodyField
    }
  }
}
