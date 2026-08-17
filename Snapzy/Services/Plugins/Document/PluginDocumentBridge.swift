import AVFoundation
import Foundation
import SnapzyPluginAPI

/// The host-side orchestration of the deep-integration channel: project the
/// open Annotate document, validate a patch, apply the accepted set as one
/// undo group, and report what was skipped and why.
@MainActor
final class PluginDocumentBridge {
  static let shared = PluginDocumentBridge()

  /// Projects the active annotate document. Omits image bytes by design —
  /// pixels travel only through `snapzy.asset.read`, for the invocation.
  func project(state: AnnotateState) -> AnnotateDocument {
    AnnotateDocumentProjector.project(state: state)
  }

  /// Projects the active annotate session as a full `SnapzyDocument`.
  func projectDocument(state: AnnotateState) -> SnapzyDocument {
    .annotate(project(state: state))
  }

  /// Validates and applies a patch to a live document. Returns the report.
  @discardableResult
  func apply(_ edits: [DocumentEdit], to state: AnnotateState) -> DocumentPatchResult {
    let projection = project(state: state)
    let context = DocumentEditValidator.Context(
      canvasSize: projection.size,
      existingIDs: Set(projection.items.map(\.id))
    )
    let (accepted, skipped) = DocumentEditValidator.validate(edits, context: context)
    guard !accepted.isEmpty else {
      return DocumentPatchResult(applied: 0, skipped: skipped)
    }
    let applied = AnnotateEditApplier.apply(accepted, to: state)
    return DocumentPatchResult(applied: applied, skipped: skipped)
  }

  /// Reads a media document projection for the current invocation asset
  /// (video/GIF). Read-only in v1.
  func projectMedia(assetURL: URL) async -> MediaDocument {
    var media = MediaDocument(schema: SnapzyVocabulary.documentSchemaVersion)
    let asset = AVURLAsset(url: assetURL)
    if #available(macOS 13.0, *) {
      media = MediaDocument(
        schema: media.schema,
        duration: (try? await asset.load(.duration).seconds) ?? media.duration,
        size: media.size,
        fps: media.fps,
        segments: media.segments
      )
    }
    return media
  }
}

/// Op-level capability negotiation: the host publishes the ops it supports;
/// the manifest declares the ops a command emits. When the intersection is
/// empty on a surface, the command is hidden there and the plugin row says
/// why — a plugin written for a newer host degrades to a readable warning
/// instead of failing at runtime.
enum PluginDocumentCapabilityNegotiator {
  /// Ops this host supports (v1: the Annotate patch ops).
  static let hostSupportedOps: Set<DocumentEditKind> = [.addItem, .updateItem, .removeItem, .setCrop]

  /// Whether the host supports every op the metadata declares.
  static func supports(_ emits: [DocumentEditKind]) -> Bool {
    emits.allSatisfy { hostSupportedOps.contains($0) }
  }

  /// A readable explanation when unsupported ops are declared.
  static func explanation(for emits: [DocumentEditKind]) -> String? {
    let unsupported = emits.filter { !hostSupportedOps.contains($0) }
    guard !unsupported.isEmpty else { return nil }
    return "This plugin emits edits this version of Snapzy does not support yet (\(unsupported.map(\.rawValue).joined(separator: ", ")))."
  }
}
