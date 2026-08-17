import Foundation
@_exported import PluginKitCore

/// Identity of the vocabulary Snapzy publishes.
///
/// Versioning discipline: `contractVersion` describes the extension-point
/// contract; `documentSchemaVersion` describes `SnapzyDocument`. The two move on
/// separate clocks — a document schema addition must not force a contract major
/// bump and vice versa.
public enum SnapzyVocabulary {
  /// The vocabulary every Snapzy extension point belongs to.
  public static let vocabularyID: VocabularyID = "com.snapzy.api"

  /// The contract version of the `SnapzyCommandPoint` surface.
  public static let contractVersion: SemanticVersion = "1.0.0"

  /// The `SnapzyDocument` projection schema version.
  public static let documentSchemaVersion = 1

  /// The Snapzy plugin bundle layout constants.
  public enum Bundle {
    /// Maximum manifest size, in bytes.
    public static let maxManifestBytes = 64 * 1024
  }
}
