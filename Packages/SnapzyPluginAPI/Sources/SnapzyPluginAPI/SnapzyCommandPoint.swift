import Foundation
import PluginKitCore

/// The one v1 extension point: a user-invoked command.
///
/// A contribution's contract receives a ``SnapzyCommandRequest`` describing
/// the surface the user invoked from and the document they invoked on, and
/// answers with a ``SnapzyCommandResponse`` — most interestingly `.patch`, the
/// deep-integration channel that writes structured edits back into a live
/// editor as one undo step.
///
/// `RemotableExtensionPoint` is deliberate and permanent: everything crossing
/// to the sandboxed helper is `Codable & Sendable`. Nothing may carry reference
/// identity.
public enum SnapzyCommandPoint: RemotableExtensionPoint {
  public typealias Contract = any SnapzyCommand
  public typealias Request = SnapzyCommandRequest
  public typealias Response = SnapzyCommandResponse

  /// The declarative half of a command contribution, read from the manifest
  /// before any plugin code is loaded.
  public struct Metadata: Codable, Sendable {
    /// Shown in menus.
    public let title: String

    /// SF Symbol name for the menu item.
    public let systemImage: String

    /// Document kinds the command accepts. Empty means "all kinds".
    public var accepts: [SnapzyDocumentKind]

    /// Edit operations the command may emit, negotiated against host support.
    /// Declaring this is what lets the host hide a command whose ops are
    /// unsupported instead of failing it at runtime.
    public var emits: [DocumentEditKind]

    /// Long-running commands get progress UI and an extended deadline.
    public var isLongRunning: Bool

    public init(
      title: String,
      systemImage: String = "wand.and.stars",
      accepts: [SnapzyDocumentKind] = [],
      emits: [DocumentEditKind] = [],
      isLongRunning: Bool = false
    ) {
      self.title = title
      self.systemImage = systemImage
      self.accepts = accepts
      self.emits = emits
      self.isLongRunning = isLongRunning
    }
  }

  public static let extensionPointID: ExtensionPointID = "com.snapzy.command"
  public static let vocabulary: VocabularyID = SnapzyVocabulary.vocabularyID
  public static let contractVersion: SemanticVersion = SnapzyVocabulary.contractVersion
  public static let arity: ExtensionPointArity = .many(ordering: .priority)

  /// The uniform invocation shim every transport uses.
  public static func invoke(
    _ contract: Contract, with request: Request
  ) async throws -> Response {
    try await contract.handle(request)
  }
}

/// The recommended contract shape for a Snapzy command.
public protocol SnapzyCommand: RemotableContract
where Request == SnapzyCommandRequest, Response == SnapzyCommandResponse {}

/// Which surface the user invoked a command from.
public enum SnapzySurface: String, Codable, Sendable, CaseIterable {
  case annotate
  case quickAccess
  case videoEditor
  case history
}

/// The kind of document a command was invoked on.
public enum SnapzyDocumentKind: String, Codable, Sendable, CaseIterable {
  case screenshot
  case video
  case gif
  case annotateSession
}

/// Everything a command is told about its invocation.
///
/// The `invocationID` is the asset-read scope: `snapzy.asset.read` is only
/// valid for the invocation carrying this ID, and only while that invocation
/// is live. A plugin cannot read anything the user did not point it at.
public struct SnapzyCommandRequest: Codable, Sendable, Equatable {
  /// Scopes `asset.read` to this invocation, and this invocation only.
  public let invocationID: UUID

  public let surface: SnapzySurface
  public let documentKind: SnapzyDocumentKind

  /// The projected document, when the surface has one and the plugin declared
  /// `snapzy.asset.read` or `snapzy.document.write`. Geometry-only; image bytes
  /// are never embedded here — they travel through `asset.read`.
  public let document: SnapzyDocument?

  /// Selected item ids from the projected document; may be empty.
  public let selection: [String]

  /// The plugin's configuration values, decoded from its settings schema.
  public let options: JSONValue

  public init(
    invocationID: UUID,
    surface: SnapzySurface,
    documentKind: SnapzyDocumentKind,
    document: SnapzyDocument? = nil,
    selection: [String] = [],
    options: JSONValue = .object([:])
  ) {
    self.invocationID = invocationID
    self.surface = surface
    self.documentKind = documentKind
    self.document = document
    self.selection = selection
    self.options = options
  }
}

/// What a command produced.
public struct SnapzyCommandResponse: Codable, Sendable, Equatable {
  public enum Outcome: Codable, Sendable, Equatable {
    /// Finished with no result to surface.
    case completed
    /// The deep-integration channel: structured document edits the host
    /// validates and applies as one undo group.
    case patch([DocumentEdit])
    /// Plain text; shown in a result panel / copied to the clipboard.
    case text(String)
    /// A URL for the user (copied + notified).
    case url(URL)
    /// Bytes the host saves to a file and reveals to the user.
    case asset(SnapzyAssetRef)
    /// The command failed; `message` is attributed to the plugin and shown.
    case failed(message: String)
  }

  public let outcome: Outcome

  public init(outcome: Outcome) {
    self.outcome = outcome
  }
}

/// A file a command produced for the user. The host writes the bytes
/// atomically to a sensible location and reveals the file.
public struct SnapzyAssetRef: Codable, Sendable, Equatable {
  /// Suggested file name (no path separators).
  public let name: String
  /// E.g. "image/png", "text/plain", "application/srt".
  public let mimeType: String
  /// The bytes. Capped by the host (10 MB).
  public let data: Data

  public init(name: String, mimeType: String, data: Data) {
    self.name = name
    self.mimeType = mimeType
    self.data = data
  }
}
