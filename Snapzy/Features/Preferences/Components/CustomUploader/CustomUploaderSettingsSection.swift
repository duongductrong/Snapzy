//
//  CustomUploaderSettingsSection.swift
//  Snapzy
//
//  Settings > Cloud section for custom HTTP uploaders: pick the active uploader,
//  create / edit / duplicate / delete, and import ShareX .sxcu files.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CustomUploaderSettingsSection: View {
  /// The uploader Cloud uploads use. Writes go wherever the caller decides
  /// (a form draft, or `CloudManager.saveCustomUploaderConfiguration`).
  @Binding var selectedID: UUID?

  @ObservedObject private var store = CustomUploaderStore.shared

  @State private var editorTarget: EditorTarget?
  @State private var importTarget: ImportTarget?
  @State private var pendingDelete: CustomUploader?
  @State private var errorMessage: String?

  private struct EditorTarget: Identifiable {
    let uploader: CustomUploader
    let isNew: Bool
    var id: UUID { uploader.id }
  }

  private struct ImportTarget: Identifiable {
    let id = UUID()
    let result: CustomUploaderImportResult
  }

  private var selectedUploader: CustomUploader? {
    selectedID.flatMap(store.uploader(id:))
  }

  var body: some View {
    Section {
      if store.uploaders.isEmpty {
        Text(L10n.CustomUploader.emptyState)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Picker(L10n.CustomUploader.activeUploader, selection: $selectedID) {
          if selectedUploader == nil {
            Text(L10n.CustomUploader.noUploaderSelected).tag(UUID?.none)
          }
          ForEach(store.uploaders) { uploader in
            Text(verbatim: uploader.name).tag(UUID?.some(uploader.id))
          }
        }
        .pickerStyle(.menu)
      }

      HStack(spacing: 8) {
        Button(action: createUploader) {
          Label(L10n.CustomUploader.newUploader, systemImage: "plus")
        }
        .disabled(!store.canAdd)

        Button(L10n.Common.edit) {
          if let selectedUploader {
            editorTarget = EditorTarget(uploader: selectedUploader, isNew: false)
          }
        }
        .disabled(selectedUploader == nil)

        Button(L10n.CustomUploader.duplicate, action: duplicateSelected)
          .disabled(selectedUploader == nil || !store.canAdd)

        Button(L10n.Common.delete, role: .destructive) {
          pendingDelete = selectedUploader
        }
        .disabled(selectedUploader == nil)

        Spacer()

        Button(action: importSXCU) {
          Label(L10n.CustomUploader.importSXCU, systemImage: "square.and.arrow.down")
        }
        .disabled(!store.canAdd)
      }
      .controlSize(.regular)

      if let errorMessage {
        Label(errorMessage, systemImage: "xmark.circle.fill")
          .font(.system(size: 11))
          .foregroundColor(.red)
          .fixedSize(horizontal: false, vertical: true)
      } else if !store.canAdd {
        Text(L10n.CustomUploader.errorLimitReached(CustomUploaderStore.maxUploaders))
          .font(.system(size: 11))
          .foregroundColor(.secondary)
      }
    } header: {
      Text(L10n.CustomUploader.sectionTitle)
    } footer: {
      Text(L10n.CustomUploader.sectionDescription)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .sheet(item: $editorTarget) { target in
      CustomUploaderEditorSheet(
        uploader: target.uploader,
        isNew: target.isNew,
        onSave: { uploader in
          try save(uploader, isNew: target.isNew)
          editorTarget = nil
        },
        onCancel: { editorTarget = nil }
      )
    }
    .sheet(item: $importTarget) { target in
      CustomUploaderImportSheet(
        result: target.result,
        onAdd: { uploader in
          let added = try store.add(uploader)
          if selectedUploader == nil { selectedID = added.id }
          importTarget = nil
        },
        onCancel: { importTarget = nil }
      )
    }
    .alert(
      L10n.CustomUploader.deleteConfirmTitle(pendingDelete?.name ?? ""),
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      )
    ) {
      Button(L10n.Common.delete, role: .destructive) {
        if let pendingDelete {
          store.delete(id: pendingDelete.id)
        }
        pendingDelete = nil
      }
      Button(L10n.Common.cancel, role: .cancel) { pendingDelete = nil }
    } message: {
      Text(L10n.CustomUploader.deleteConfirmMessage)
    }
  }

  // MARK: - Actions

  private func createUploader() {
    errorMessage = nil
    editorTarget = EditorTarget(uploader: CustomUploader(name: "", url: ""), isNew: true)
  }

  private func duplicateSelected() {
    guard let selectedID else { return }
    do {
      if let copy = try store.duplicate(id: selectedID) {
        self.selectedID = copy.id
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func save(_ uploader: CustomUploader, isNew: Bool) throws {
    if isNew {
      let added = try store.add(uploader)
      if selectedUploader == nil { selectedID = added.id }
    } else {
      store.update(uploader)
    }
    errorMessage = nil
  }

  private func importSXCU() {
    errorMessage = nil
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    var types: [UTType] = [.json]
    if let sxcu = UTType(filenameExtension: CustomUploaderSXCUImporter.fileExtension) {
      types.insert(sxcu, at: 0)
    }
    panel.allowedContentTypes = types
    panel.title = L10n.CustomUploader.importPanelTitle
    panel.message = L10n.CustomUploader.importPanelMessage
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      let data = try Data(contentsOf: url)
      let result = try CustomUploaderSXCUImporter.importUploader(
        from: data,
        fallbackName: url.deletingPathExtension().lastPathComponent
      )
      importTarget = ImportTarget(result: result)
    } catch let error as CustomUploaderError {
      errorMessage = error.localizedDescription
    } catch {
      errorMessage = CustomUploaderError.invalidImportFile.localizedDescription
    }
  }
}
