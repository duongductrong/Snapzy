import AppKit
import Foundation
import SnapzyPluginAPI

/// Invokes a plugin command end to end: issues an invocation ID (the
/// asset-read scope), resolves the contract (loading the plugin on first
/// use), runs it with progress + cancel, and routes the outcome — `.patch`
/// into the live document as one undo group, `.text`/`.url`/`.asset` into the
/// UI, `.failed` into an attributed toast with the document untouched.
@MainActor
final class PluginCommandCoordinator {
  static let shared = PluginCommandCoordinator()

  /// The invocation context: what the user pointed the command at.
  struct InvocationContext {
    let surface: SnapzySurface
    let documentKind: SnapzyDocumentKind
    /// The asset on disk backing this document, for `snapzy.asset.read`.
    let assetURL: URL
    /// The projected document, when the surface has one.
    let document: SnapzyDocument?
    let selection: [String]
    /// The plugin's stored settings, decoded as the request options.
    let options: JSONValue
    /// Applies a patch to the live annotate document, when the surface is
    /// Annotate. nil elsewhere.
    var applyPatch: ((@MainActor ([DocumentEdit]) -> DocumentPatchResult))?
    /// Hooked into the current surface's progress overlay.
    var onProgress: ((@MainActor (Double?, String?) -> Void))?
  }

  private init() {}

  /// Runs the command. All errors surface through the provided handler; the
  /// document is only touched by the host's own patch application.
  func invoke(
    _ item: PluginCommandItem,
    context: InvocationContext
  ) async {
    let invocationID = await PluginHostController.shared.beginInvocation(
      kind: context.documentKind,
      assetURL: context.assetURL
    )
    defer {
      Task { @MainActor in
        await PluginHostController.shared.endInvocation(invocationID)
      }
    }

    PluginTaskStateStore.shared.begin(
      invocationID: invocationID,
      pluginID: item.pluginID,
      title: item.title
    )

    let request = SnapzyCommandRequest(
      invocationID: invocationID,
      surface: context.surface,
      documentKind: context.documentKind,
      document: context.document,
      selection: context.selection,
      options: context.options
    )

    do {
      let contract = try await PluginHostController.shared.resolveContract(
        for: item, invocationID: invocationID
      )
      let response = try await contract.handle(request)
      await route(response, item: item, context: context, invocationID: invocationID)
    } catch {
      let message = (error as? PluginCommandError)?.userMessage ?? "\(error)"
      DiagnosticLogger.shared.logError(.plugin, error, "Command “\(item.title)” failed.")
      AppToastManager.shared.show(
        message: "“\(item.pluginName)”: \(message)",
        style: .error
      )
    }

    PluginTaskStateStore.shared.finish(invocationID: invocationID)
  }

  /// Cancels a live invocation: the helper's in-flight promises reject, and
  /// no outcome is applied.
  func cancel(invocationID: UUID) {
    PluginTaskStateStore.shared.update(
      SnapzyPluginIPC.ProgressUpdate(invocationID: invocationID, message: "Cancelling…")
    )
    PluginHostController.shared.cancelInvocation(invocationID)
  }

  // MARK: - Outcome routing

  private func route(
    _ response: SnapzyCommandResponse,
    item: PluginCommandItem,
    context: InvocationContext,
    invocationID: UUID
  ) async {
    switch response.outcome {
    case .completed:
      break

    case .patch(let edits):
      guard let applyPatch = context.applyPatch else {
        AppToastManager.shared.show(
          message: "“\(item.pluginName)” produced document edits, but this surface cannot apply them.",
          style: .warning
        )
        return
      }
      // Capability negotiation: only declared + consented ops may apply.
      let usedOps = Array(Set(edits.map(\.kind)))
      let allowed = await PluginHostController.shared.gateDocumentWrite(
        pluginID: item.pluginID,
        ops: usedOps
      )
      let allowedSet = Set(allowed)
      let accepted = edits.filter { allowedSet.contains($0.kind) }
      let refused = edits.count - accepted.count
      let report = await applyPatch(accepted)
      if report.applied > 0 || !report.skipped.isEmpty {
        var note = "Applied \(report.applied) edit(s)."
        if !report.skipped.isEmpty {
          note += " Skipped \(report.skipped.count) invalid edit(s)."
        }
        if refused > 0 {
          note += " \(refused) edit(s) refused by capability negotiation."
        }
        AppToastManager.shared.show(message: note, style: .info)
      }

    case .text(let text):
      AppToastManager.shared.show(message: "\(item.title): \(text)", style: .info, duration: 6)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)

    case .url(let url):
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(url.absoluteString, forType: .string)
      _ = await SystemNotificationService.shared.post(
        title: item.title,
        body: url.absoluteString
      )

    case .asset(let asset):
      let destination = Self.destinationURL(for: asset)
      do {
        try asset.data.write(to: destination, options: .atomic)
        NSWorkspace.shared.activateFileViewerSelecting([destination])
        AppToastManager.shared.show(
          message: "Saved \(asset.name).",
          style: .success
        )
      } catch {
        AppToastManager.shared.show(
          message: "Could not save \(asset.name): \(error)",
          style: .error
        )
      }

    case .failed(let message):
      AppToastManager.shared.show(
        message: "“\(item.pluginName)”: \(message)",
        style: .error
      )
    }
  }

  private static func destinationURL(for asset: SnapzyAssetRef) -> URL {
    let name = asset.name
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: "..", with: "")
    let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    var candidate = base.appendingPathComponent(name, isDirectory: false)
    let stem = candidate.deletingPathExtension().lastPathComponent
    let ext = candidate.pathExtension
    var counter = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = base.appendingPathComponent("\(stem)-\(counter).\(ext)", isDirectory: false)
      counter += 1
    }
    return candidate
  }
}
