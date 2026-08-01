//
//  PreferencesOCRModelListView.swift
//  Snapzy
//
//  OCR model picker list: built-in default, downloadable PP-OCR models, custom endpoints.
//

import SwiftUI

/// Content of the "OCR Model" section in Capture → OCR preferences.
struct PreferencesOCRModelListView: View {
  @StateObject private var viewModel = PreferencesOCRModelListViewModel()

  var body: some View {
    Section(L10n.PreferencesCapture.ocrModelSection) {
      VStack(spacing: 0) {
        builtInRow

        ForEach(OCRModelCatalog.all, id: \.id) { definition in
          Divider()
          downloadableRow(definition)
        }

        ForEach(viewModel.customModelStore.models) { model in
          Divider()
          customRow(model)
        }
      }

      HStack {
        Spacer()
        Button(L10n.PreferencesCapture.ocrModelAddCustom) {
          viewModel.sheetRequest = .init(editing: nil)
        }
        .controlSize(.small)
      }
    }
    .sheet(item: $viewModel.sheetRequest) { request in
      PreferencesCustomOCRModelSheet(
        store: viewModel.customModelStore,
        editing: request.editing,
        onDismiss: { viewModel.sheetRequest = nil }
      )
    }
    .alert(
      L10n.PreferencesCapture.ocrModelDownloadFailedTitle,
      isPresented: Binding(
        get: { viewModel.downloadFailure != nil },
        set: { if !$0 { viewModel.downloadFailure = nil } }
      )
    ) {
      Button(L10n.PreferencesCapture.ocrModelRetry) {
        if let failure = viewModel.downloadFailure {
          viewModel.download(modelID: failure.modelID)
        }
        viewModel.downloadFailure = nil
      }
      Button(L10n.Common.cancel, role: .cancel) {
        viewModel.downloadFailure = nil
      }
    } message: {
      Text(viewModel.downloadFailure?.reason ?? "")
    }
    .alert(
      L10n.PreferencesCapture.ocrModelRemoveDownloadTitle,
      isPresented: Binding(
        get: { viewModel.removeDownloadableCandidate != nil },
        set: { if !$0 { viewModel.removeDownloadableCandidate = nil } }
      )
    ) {
      Button(L10n.PreferencesCapture.ocrModelRemove, role: .destructive) {
        if let candidate = viewModel.removeDownloadableCandidate {
          viewModel.removeDownloadable(candidate)
        }
        viewModel.removeDownloadableCandidate = nil
      }
      Button(L10n.Common.cancel, role: .cancel) {
        viewModel.removeDownloadableCandidate = nil
      }
    } message: {
      Text(L10n.PreferencesCapture.ocrModelRemoveDownloadMessage(
        viewModel.removeDownloadableCandidate?.displayName ?? ""
      ))
    }
    .alert(
      L10n.PreferencesCapture.ocrModelRemoveCustomTitle,
      isPresented: Binding(
        get: { viewModel.removeCustomCandidate != nil },
        set: { if !$0 { viewModel.removeCustomCandidate = nil } }
      )
    ) {
      Button(L10n.PreferencesCapture.ocrModelRemove, role: .destructive) {
        if let candidate = viewModel.removeCustomCandidate {
          viewModel.removeCustom(candidate)
        }
        viewModel.removeCustomCandidate = nil
      }
      Button(L10n.Common.cancel, role: .cancel) {
        viewModel.removeCustomCandidate = nil
      }
    } message: {
      Text(L10n.PreferencesCapture.ocrModelRemoveCustomMessage(
        viewModel.removeCustomCandidate?.name ?? ""
      ))
    }
    .alert(
      viewModel.connectionTestResult?.title ?? "",
      isPresented: Binding(
        get: { viewModel.connectionTestResult != nil },
        set: { if !$0 { viewModel.connectionTestResult = nil } }
      )
    ) {
      Button(L10n.Common.ok, role: .cancel) {
        viewModel.connectionTestResult = nil
      }
    } message: {
      Text(viewModel.connectionTestResult?.message ?? "")
    }
  }

  // MARK: - Built-in Row

  private var builtInRow: some View {
    let isSelected = viewModel.isSelected(.builtIn)
    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(L10n.PreferencesCapture.ocrModelBuiltinTitle)
            .fontWeight(.medium)
          badge(L10n.PreferencesCapture.ocrModelDefaultBadge)
        }
        Text(L10n.PreferencesCapture.ocrModelBuiltinDescription)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      if isSelected {
        selectionCheckmark
      }
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .onTapGesture { viewModel.select(.builtIn) }
  }

  // MARK: - Downloadable Rows

  private func downloadableRow(_ definition: OCRModelDefinition) -> some View {
    let selection = OCRModelSelection.downloadable(definition.id)
    let state = viewModel.modelStore.state(for: definition.id)
    let isSelectable = viewModel.isSelectable(selection)

    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(definition.displayName)
            .fontWeight(.medium)
          Text(L10n.PreferencesCapture.ocrModelParams(definition.parameterCountLabel))
            .font(.caption)
            .foregroundColor(.secondary)
        }
        Text(L10n.PreferencesCapture.ocrModelSizes(definition.fp32SizeLabel, definition.int8SizeLabel))
          .font(.caption)
          .foregroundColor(.secondary)
        if let coverage = viewModel.coverage[definition.id] {
          charsetLines(coverage)
        }
      }
      .opacity(isSelectable || viewModel.isSelected(selection) ? 1 : 0.6)

      Spacer()

      downloadableTrailing(definition: definition, state: state, isSelected: viewModel.isSelected(selection))
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .onTapGesture {
      guard isSelectable else { return }
      viewModel.select(selection)
    }
    .task(id: state == .installed) {
      await viewModel.loadCoverage(for: definition.id)
    }
  }

  /// What the model's dictionary can spell. The warning line is the point of
  /// the whole section: a partly-covered script is not rejected at recognition
  /// time, it comes back with the missing characters silently swapped for their
  /// closest neighbour (PP-OCRv6 turns Vietnamese "Kết luận" into "Kêt luân").
  @ViewBuilder
  private func charsetLines(_ coverage: OCRScriptCoverageReport) -> some View {
    let supported = coverage.fullySupported
    let incomplete = coverage.partiallySupported

    if !supported.isEmpty {
      Text(L10n.PreferencesCapture.ocrModelCharset(Self.scriptList(supported)))
        .font(.caption)
        .foregroundColor(.secondary)
    }
    if !incomplete.isEmpty {
      Label(
        L10n.PreferencesCapture.ocrModelCharsetIncomplete(Self.scriptList(incomplete)),
        systemImage: "exclamationmark.triangle.fill"
      )
      .font(.caption)
      .foregroundColor(.orange)
    }
  }

  private static func scriptList(_ scripts: [OCRScript]) -> String {
    scripts.map(displayName).joined(separator: ", ")
  }

  private static func displayName(_ script: OCRScript) -> String {
    switch script {
    case .latin: return L10n.PreferencesCapture.ocrScriptLatin
    case .vietnamese: return L10n.PreferencesCapture.ocrScriptVietnamese
    case .chinese: return L10n.PreferencesCapture.ocrScriptChinese
    case .japanese: return L10n.PreferencesCapture.ocrScriptJapanese
    case .korean: return L10n.PreferencesCapture.ocrScriptKorean
    case .cyrillic: return L10n.PreferencesCapture.ocrScriptCyrillic
    case .arabic: return L10n.PreferencesCapture.ocrScriptArabic
    case .thai: return L10n.PreferencesCapture.ocrScriptThai
    case .devanagari: return L10n.PreferencesCapture.ocrScriptDevanagari
    }
  }

  @ViewBuilder
  private func downloadableTrailing(
    definition: OCRModelDefinition,
    state: OCRModelInstallState,
    isSelected: Bool
  ) -> some View {
    switch state {
    case .notInstalled:
      Button(L10n.PreferencesCapture.ocrModelDownload(Self.downloadSizeLabel(for: definition))) {
        viewModel.download(modelID: definition.id)
      }
      .controlSize(.small)

    case .downloading(let progress):
      HStack(spacing: 8) {
        ProgressView(value: progress)
          .frame(width: 80)
        Text(verbatim: "\(Int(progress * 100))%")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .monospacedDigit()
        Button {
          viewModel.cancelDownload(modelID: definition.id)
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(L10n.Common.cancel)
      }

    case .verifying:
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text(L10n.PreferencesCapture.ocrModelVerifying)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
      }

    case .installed:
      HStack(spacing: 10) {
        if isSelected {
          selectionCheckmark
        }
        Button {
          viewModel.removeDownloadableCandidate = definition
        } label: {
          Image(systemName: "trash")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(L10n.PreferencesCapture.ocrModelRemove)
      }

    case .failed(let reason):
      HStack(spacing: 8) {
        Text(reason)
          .font(.system(size: 11))
          .foregroundColor(.red)
          .lineLimit(2)
          .frame(maxWidth: 180, alignment: .trailing)
        Button(L10n.PreferencesCapture.ocrModelRetry) {
          viewModel.download(modelID: definition.id)
        }
        .controlSize(.small)
      }
    }
  }

  // MARK: - Custom Rows

  private func customRow(_ model: CustomOCRModel) -> some View {
    let selection = OCRModelSelection.custom(model.id)
    let isSelected = viewModel.isSelected(selection)

    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(model.name)
            .fontWeight(.medium)
          badge(L10n.PreferencesCapture.ocrModelCustomBadge)
        }
        Text(model.baseURL)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      HStack(spacing: 10) {
        if isSelected {
          selectionCheckmark
        }
        if viewModel.testingConnectionModelID == model.id {
          ProgressView()
            .controlSize(.small)
        }
        Menu {
          Button(L10n.PreferencesCapture.ocrModelEdit) {
            viewModel.sheetRequest = .init(editing: model)
          }
          Button(L10n.PreferencesCapture.ocrModelTestConnection) {
            viewModel.testConnection(for: model)
          }
          Divider()
          Button(L10n.PreferencesCapture.ocrModelRemove, role: .destructive) {
            viewModel.removeCustomCandidate = model
          }
        } label: {
          Image(systemName: "ellipsis.circle")
            .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
      }
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .onTapGesture { viewModel.select(selection) }
  }

  // MARK: - Shared Pieces

  private var selectionCheckmark: some View {
    Image(systemName: "checkmark")
      .font(.system(size: 12, weight: .semibold))
      .foregroundColor(.accentColor)
  }

  private func badge(_ title: String) -> some View {
    Text(title)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(.quaternary, in: Capsule())
  }

  private static func downloadSizeLabel(for definition: OCRModelDefinition) -> String {
    ByteCountFormatter.string(fromByteCount: definition.totalDownloadBytes, countStyle: .file)
  }
}

#Preview {
  Form {
    PreferencesOCRModelListView()
  }
  .formStyle(.grouped)
  .frame(width: 600)
}
