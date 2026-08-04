//
//  PreferencesOCRModelListView.swift
//  Snapzy
//
//  OCR provider picker: built-in Vision and custom endpoints.
//

import SwiftUI

/// Content of the "OCR Model" section in Capture → OCR preferences.
struct PreferencesOCRModelListView: View {
  @StateObject private var viewModel = PreferencesOCRModelListViewModel()

  var body: some View {
    Section(L10n.PreferencesCapture.ocrModelSection) {
      VStack(spacing: 0) {
        builtInRow

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

  // MARK: - Built-in row

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

  // MARK: - Custom rows

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

  // MARK: - Shared pieces

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
}

#Preview {
  Form {
    PreferencesOCRModelListView()
  }
  .formStyle(.grouped)
  .frame(width: 600)
}
