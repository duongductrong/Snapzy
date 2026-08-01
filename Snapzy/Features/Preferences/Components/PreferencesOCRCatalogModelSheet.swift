//
//  PreferencesOCRCatalogModelSheet.swift
//  Snapzy
//
//  Add/edit form for user-defined downloadable PP-OCR models.
//

import SwiftUI

enum OCRCatalogArtifactSourceDraftType: String, CaseIterable, Identifiable {
  case directURL
  case huggingFace

  var id: String {
    rawValue
  }
}

struct OCRCatalogArtifactDraft: Equatable {
  var sourceType: OCRCatalogArtifactSourceDraftType = .directURL
  var url = ""
  var repository = ""
  var revision = "main"
  var file = ""
  var expectedBytes = ""
  var sha256 = ""

  init() {}

  init(manifest: OCRModelArtifactManifest?) {
    guard let manifest else { return }
    switch manifest.source.type {
    case .url:
      sourceType = .directURL
      url = manifest.source.url ?? ""
    case .huggingFace:
      sourceType = .huggingFace
      repository = manifest.source.repository ?? ""
      revision = manifest.source.revision ?? "main"
      file = manifest.source.file ?? ""
    }
    expectedBytes = manifest.expectedBytes.map(String.init) ?? ""
    sha256 = manifest.sha256 ?? ""
  }

  func manifest(role: OCRModelArtifactRole) throws -> OCRModelArtifactManifest {
    let trimmedBytes = expectedBytes.trimmingCharacters(in: .whitespacesAndNewlines)
    let bytes: Int64?
    if trimmedBytes.isEmpty {
      bytes = nil
    } else if let parsed = Int64(trimmedBytes), parsed > 0 {
      bytes = parsed
    } else {
      throw OCRModelManifestError.invalid(
        "\(role.rawValue).expected_bytes must be a positive whole number"
      )
    }

    let source = switch sourceType {
    case .directURL:
      OCRModelArtifactSourceManifest(
        type: .url,
        url: url.trimmingCharacters(in: .whitespacesAndNewlines),
        repository: nil,
        revision: nil,
        file: nil
      )
    case .huggingFace:
      OCRModelArtifactSourceManifest(
        type: .huggingFace,
        url: nil,
        repository: repository.trimmingCharacters(in: .whitespacesAndNewlines),
        revision: revision.trimmingCharacters(in: .whitespacesAndNewlines),
        file: file.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }

    let trimmedHash = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return OCRModelArtifactManifest(
      role: role,
      source: source,
      expectedBytes: bytes,
      sha256: trimmedHash.isEmpty ? nil : trimmedHash
    )
  }
}

struct OCRCatalogModelDraft: Equatable {
  var id = ""
  var displayName = ""
  var parameterCountLabel = ""
  var fp32SizeLabel = ""
  var int8SizeLabel = ""
  var detector = OCRCatalogArtifactDraft()
  var recognizer = OCRCatalogArtifactDraft()
  var dictionary = OCRCatalogArtifactDraft()

  init() {}

  init(manifest: OCRModelManifest?) {
    guard let manifest else { return }
    id = manifest.id
    displayName = manifest.displayName
    parameterCountLabel = manifest.parameterCountLabel
    fp32SizeLabel = manifest.fp32SizeLabel
    int8SizeLabel = manifest.int8SizeLabel
    detector = OCRCatalogArtifactDraft(
      manifest: manifest.artifacts.first { $0.role == .detector }
    )
    recognizer = OCRCatalogArtifactDraft(
      manifest: manifest.artifacts.first { $0.role == .recognizer }
    )
    dictionary = OCRCatalogArtifactDraft(
      manifest: manifest.artifacts.first { $0.role == .dictionary }
    )
  }

  var hasRequiredBasics: Bool {
    [id, displayName, parameterCountLabel, fp32SizeLabel, int8SizeLabel]
      .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  func manifest() throws -> OCRModelManifest {
    let model = try OCRModelManifest(
      id: id.trimmingCharacters(in: .whitespacesAndNewlines),
      displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
      parameterCountLabel: parameterCountLabel.trimmingCharacters(in: .whitespacesAndNewlines),
      fp32SizeLabel: fp32SizeLabel.trimmingCharacters(in: .whitespacesAndNewlines),
      int8SizeLabel: int8SizeLabel.trimmingCharacters(in: .whitespacesAndNewlines),
      adapter: .ppocrDBCTCV1,
      artifacts: [
        detector.manifest(role: .detector),
        recognizer.manifest(role: .recognizer),
        dictionary.manifest(role: .dictionary),
      ]
    )
    _ = try OCRCatalogManifestValidator.definition(from: model)
    return model
  }
}

struct PreferencesOCRCatalogModelSheet: View {
  let store: OCRUserCatalogStore
  let editing: OCRModelManifest?
  let onDismiss: () -> Void

  @State private var draft: OCRCatalogModelDraft
  @State private var saveError: String?

  init(
    store: OCRUserCatalogStore,
    editing: OCRModelManifest?,
    onDismiss: @escaping () -> Void
  ) {
    self.store = store
    self.editing = editing
    self.onDismiss = onDismiss
    _draft = State(initialValue: OCRCatalogModelDraft(manifest: editing))
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 7) {
        Image(systemName: "shippingbox.and.arrow.backward")
          .font(.system(size: 28))
          .foregroundStyle(.tint)
        Text(editing == nil
          ? L10n.PreferencesCapture.ocrCatalogSheetAddTitle
          : L10n.PreferencesCapture.ocrCatalogSheetEditTitle)
          .font(.headline)
        Text(L10n.PreferencesCapture.ocrCatalogSheetDescription)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, 24)
      .padding(.top, 22)
      .padding(.bottom, 16)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          modelMetadata
          artifactEditor(
            role: .detector,
            draft: Binding(get: { draft.detector }, set: { draft.detector = $0 })
          )
          artifactEditor(
            role: .recognizer,
            draft: Binding(get: { draft.recognizer }, set: { draft.recognizer = $0 })
          )
          artifactEditor(
            role: .dictionary,
            draft: Binding(get: { draft.dictionary }, set: { draft.dictionary = $0 })
          )

          if let saveError {
            Label(saveError, systemImage: "xmark.circle.fill")
              .font(.system(size: 11))
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(20)
      }

      Divider()

      HStack {
        Text(L10n.PreferencesCapture.ocrCatalogAdapterHint)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button(L10n.Common.cancel) { onDismiss() }
          .keyboardShortcut(.escape, modifiers: [])
        Button(L10n.Common.save) { save() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.return, modifiers: [])
          .disabled(!draft.hasRequiredBasics)
      }
      .padding(16)
    }
    .frame(width: 560, height: 720)
  }

  private var modelMetadata: some View {
    GroupBox(L10n.PreferencesCapture.ocrCatalogMetadataSection) {
      VStack(alignment: .leading, spacing: 11) {
        labeledField(L10n.PreferencesCapture.ocrCatalogModelID, text: $draft.id)
          .disabled(editing != nil)
        labeledField(L10n.PreferencesCapture.ocrCatalogDisplayName, text: $draft.displayName)
        HStack(alignment: .top, spacing: 10) {
          labeledField(
            L10n.PreferencesCapture.ocrCatalogParameterCount,
            text: $draft.parameterCountLabel,
            prompt: "1.5M"
          )
          labeledField(
            L10n.PreferencesCapture.ocrCatalogFP32Size,
            text: $draft.fp32SizeLabel,
            prompt: "6–8 MB"
          )
          labeledField(
            L10n.PreferencesCapture.ocrCatalogINT8Size,
            text: $draft.int8SizeLabel,
            prompt: "2–4 MB"
          )
        }
        HStack {
          Text(L10n.PreferencesCapture.ocrCatalogAdapter)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
          Spacer()
          Text(verbatim: OCRModelAdapterID.ppocrDBCTCV1.rawValue)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        }
      }
      .padding(.top, 5)
    }
  }

  private func artifactEditor(
    role: OCRModelArtifactRole,
    draft: Binding<OCRCatalogArtifactDraft>
  ) -> some View {
    GroupBox(artifactTitle(role)) {
      VStack(alignment: .leading, spacing: 11) {
        Picker(L10n.PreferencesCapture.ocrCatalogSource, selection: draft.sourceType) {
          Text(L10n.PreferencesCapture.ocrCatalogDirectURL)
            .tag(OCRCatalogArtifactSourceDraftType.directURL)
          Text(L10n.PreferencesCapture.ocrCatalogHuggingFace)
            .tag(OCRCatalogArtifactSourceDraftType.huggingFace)
        }
        .pickerStyle(.segmented)

        if draft.wrappedValue.sourceType == .directURL {
          labeledField(
            L10n.PreferencesCapture.ocrCatalogURL,
            text: draft.url,
            prompt: "https://…"
          )
        } else {
          HStack(alignment: .top, spacing: 10) {
            labeledField(
              L10n.PreferencesCapture.ocrCatalogRepository,
              text: draft.repository,
              prompt: "owner/model"
            )
            labeledField(
              L10n.PreferencesCapture.ocrCatalogRevision,
              text: draft.revision,
              prompt: "main"
            )
          }
          labeledField(
            L10n.PreferencesCapture.ocrCatalogFile,
            text: draft.file,
            prompt: role.fileName
          )
        }

        HStack(alignment: .top, spacing: 10) {
          labeledField(
            role == .dictionary
              ? L10n.PreferencesCapture.ocrCatalogExpectedBytesOptional
              : L10n.PreferencesCapture.ocrCatalogExpectedBytes,
            text: draft.expectedBytes,
            prompt: "12345678"
          )
          labeledField(
            role == .dictionary
              ? L10n.PreferencesCapture.ocrCatalogSHA256Optional
              : L10n.PreferencesCapture.ocrCatalogSHA256,
            text: draft.sha256,
            prompt: String(repeating: "a", count: 64)
          )
        }
      }
      .padding(.top, 5)
    }
  }

  private func labeledField(
    _ label: String,
    text: Binding<String>,
    prompt: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
      TextField("", text: text, prompt: prompt.map { Text(verbatim: $0) })
        .textFieldStyle(.roundedBorder)
    }
  }

  private func artifactTitle(_ role: OCRModelArtifactRole) -> String {
    switch role {
    case .detector: L10n.PreferencesCapture.ocrCatalogDetector
    case .recognizer: L10n.PreferencesCapture.ocrCatalogRecognizer
    case .dictionary: L10n.PreferencesCapture.ocrCatalogDictionary
    }
  }

  private func save() {
    saveError = nil
    do {
      let model = try draft.manifest()
      if editing == nil {
        try store.add(model)
      } else {
        try store.update(model)
      }
      onDismiss()
    } catch {
      saveError = error.localizedDescription
    }
  }
}

#Preview {
  PreferencesOCRCatalogModelSheet(store: .shared, editing: nil) {}
}
