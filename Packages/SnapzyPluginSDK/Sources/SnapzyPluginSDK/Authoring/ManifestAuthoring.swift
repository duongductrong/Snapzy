import Foundation
import PluginKitCore
import SnapzyPluginAPI

public struct SnapzyManifestBuilder {
  public var id: String
  public var version: String
  public var displayName: String
  public var summary: String?
  public var author: PluginAuthor?
  public var executable: String
  public var protocolVersion: String = "1.0.0"
  public var capabilities: [CapabilityRequest] = []
  public var commands: [SnapzyCommandPoint.Metadata] = []
  public var configurationSchema: ConfigurationSchema?

  public init(
    id: String,
    version: String,
    displayName: String,
    summary: String? = nil,
    author: PluginAuthor? = nil,
    executable: String
  ) {
    self.id = id
    self.version = version
    self.displayName = displayName
    self.summary = summary
    self.author = author
    self.executable = executable
  }

  public func build() throws -> PluginManifest {
    guard let semVer = SemanticVersion(string: version) else {
      throw SnapzyPluginError.invalidArgument("Invalid semantic version string: \(version)")
    }
    let pluginID = PluginID(id)

    let runtime = RuntimeRequirement.custom(
      RuntimeID("process"),
      options: [
        "executable": .string(executable),
        "protocolVersion": .string(protocolVersion)
      ]
    )

    let contracts = [
      ContractDependency(
        vocabulary: "com.snapzy.api",
        builtAgainst: SemanticVersion(1, 0, 0),
        compatibleWith: VersionRange(stringLiteral: ">=1.0.0 <2.0.0")
      )
    ]

    var contributions: [Contribution] = []
    for cmd in commands {
      let metaJSON = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(cmd))
      contributions.append(
        Contribution(
          extensionPoint: SnapzyCommandPoint.extensionPointID,
          name: cmd.title.lowercased().replacingOccurrences(of: " ", with: "-"),
          contractVersion: SemanticVersion(1, 0, 0),
          metadata: metaJSON
        )
      )
    }

    return PluginManifest(
      id: pluginID,
      version: semVer,
      displayName: displayName,
      summary: summary,
      author: author,
      sdkVersion: VersionRange(stringLiteral: ">=1.0.0 <2.0.0"),
      contracts: contracts,
      runtime: runtime,
      activation: .onDemand,
      capabilities: capabilities,
      contributions: contributions,
      configuration: configurationSchema
    )
  }

  public func emitJSON(pretty: Bool = true) throws -> Data {
    let manifest = try build()
    let encoder = JSONEncoder()
    if pretty {
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    return try encoder.encode(manifest)
  }
}
