import SnapzyPluginAPI
import SwiftUI

/// ONE menu view, used verbatim by every surface (Annotate, Quick Access,
/// Video Editor, History). Adding a fifth surface later means importing this
/// view — nothing else. Building it performs no I/O and runs no plugin code:
/// the items come from manifest metadata.
struct PluginCommandMenu: View {
  let items: [PluginCommandItem]
  let onInvoke: (PluginCommandItem) -> Void

  var body: some View {
    if !items.isEmpty {
      Divider()
      ForEach(items) { item in
        Button {
          onInvoke(item)
        } label: {
          Label(item.title, systemImage: item.systemImage)
        }
        .disabled(item.disabledReason != nil)
        .help(item.disabledReason ?? "")
      }
    }
  }
}

/// A compact progress indicator for long-running plugin commands. Keyed by
/// the coordinator's global task store; overlays render only when something
/// is actually running, so it never collides with other UI.
struct PluginProgressOverlay: View {
  @ObservedObject private var store = PluginTaskStateStore.shared

  var body: some View {
    let tasks = Array(store.tasks.values)
    if !tasks.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(tasks, id: \.title) { task in
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text(task.message ?? task.title)
              .font(.caption)
              .foregroundStyle(.secondary)
            if let fraction = task.fraction {
              Text("\(Int(fraction * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .padding(10)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
  }
}

/// Builds a `PluginCommandCoordinator.InvocationContext` for a surface and
/// launches the command. Surfaces hand this their document info + patch hook.
@MainActor
struct PluginInvocationLauncher {
  let surface: SnapzySurface
  let documentKind: SnapzyDocumentKind
  let assetURL: URL
  let document: SnapzyDocument?
  let selection: [String]
  let options: JSONValue
  let applyPatch: ((@MainActor ([DocumentEdit]) -> DocumentPatchResult))?

  init(
    surface: SnapzySurface,
    documentKind: SnapzyDocumentKind,
    assetURL: URL,
    document: SnapzyDocument?,
    selection: [String],
    options: JSONValue,
    applyPatch: ((@MainActor ([DocumentEdit]) -> DocumentPatchResult))? = nil
  ) {
    self.surface = surface
    self.documentKind = documentKind
    self.assetURL = assetURL
    self.document = document
    self.selection = selection
    self.options = options
    self.applyPatch = applyPatch
  }

  func launch(_ item: PluginCommandItem) {
    let context = PluginCommandCoordinator.InvocationContext(
      surface: surface,
      documentKind: documentKind,
      assetURL: assetURL,
      document: document,
      selection: selection,
      options: options,
      applyPatch: applyPatch
    )
    Task { @MainActor in
      await PluginCommandCoordinator.shared.invoke(item, context: context)
    }
  }
}
