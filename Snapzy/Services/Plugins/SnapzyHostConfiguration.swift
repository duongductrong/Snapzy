import AppKit
import Foundation
import PluginKitHost
import PluginKitInProcess
import SnapzyPluginAPI

/// The composition root: everything PluginKit needs, assembled from Snapzy's
/// services. Returns the pieces the host controller also needs directly (the
/// broker and storage factory), built from the *same* registry, policy, and
/// consent so host-side checks and the manager can never disagree.
enum SnapzyHostConfiguration {
  struct World {
    let configuration: HostConfiguration
    let broker: PolicyCapabilityBroker
    let storageFactory: any PluginStorageFactory
  }

  static func make(runtimes: [any PluginRuntime]) -> World {
    let appName = "Snapzy"

    var registry = CapabilityRegistry()
    registerCapabilities(&registry)
    let policy = CapabilityPolicy.promptForSensitive
    let consent = PluginConsentPresenter.shared
    let broker = PolicyCapabilityBroker(registry: registry, policy: policy, consent: consent)
    let storageFactory = FileSystemStorageFactory(root: PluginDirectory.pluginDataDirectory)

    var configuration = HostConfiguration(
      appIdentifier: "com.trongduong.snapzy",
      appName: appName,
      appVersion: "1.31.0",
      extensionPoints: ExtensionPointCatalog(),
      vocabularies: [
        VocabularyDescriptor(
          id: SnapzyVocabulary.vocabularyID,
          version: SnapzyVocabulary.contractVersion
        ),
      ],
      sources: sources(appName: appName),
      runtimes: runtimes,
      runtimeSelector: SnapzyRuntimeSelector(),
      trustPolicy: LocationTrustPolicy(developmentTrust: .sandboxedOnly),
      capabilities: registry,
      capabilityPolicy: policy,
      consent: consent,
      configurationStores: FileConfigurationStoreFactory(root: PluginDirectory.pluginDataDirectory),
      storage: storageFactory,
      enablement: UserDefaultsEnablementStore(),
      log: CallbackPluginLog { level, plugin, message in
        let category: DiagnosticLogLevel = switch level {
        case .debug: .debug
        case .info: .info
        case .notice: .info
        case .error: .error
        }
        DiagnosticLogger.shared.log(
          category, .plugin, message,
          context: plugin.map { ["plugin": $0.rawValue] }
        )
      },
      safeMode: ProcessInfo.processInfo.environment["SNAPZY_PLUGINS_SAFE_MODE"] == "1"
    )

    configuration.extensionPoints.register(
      SnapzyCommandPoint.self,
      summary: "A user-invoked command, e.g. Translate on an open screenshot."
    )

    return World(
      configuration: configuration,
      broker: broker,
      storageFactory: storageFactory
    )
  }

  private static func sources(appName: String) -> [any PluginSource] {
    // First-party native plugins: compiled in, never dlopen'd. None ship in
    // v1; the source exists so `loadsBundles: false` is a settled fact rather
    // than an option to re-open later.
    let registered = RegisteredPluginSource(
      sourceID: .registered,
      trustHint: .firstParty,
      manifests: []
    )
    // User-installed plugin folders.
    let user = DirectoryPluginSource.user(appName: appName)
    // "Load Plugin from Folder…" staging. A separate source rather than a
    // subdirectory of `Plugins/`: `DirectoryPluginSource` scans one level for
    // `.plugin` bundles, so a nested directory would never be discovered — and
    // the separate source is what carries the `development` trust hint, which
    // is what drives the dev banner and per-session consent.
    let development = DirectoryPluginSource(
      sourceID: .development,
      trustHint: .development,
      directory: PluginDirectory.developmentPluginsDirectory
    )
    return [registered, user, development]
  }

  private static func registerCapabilities(_ registry: inout CapabilityRegistry) {
    registry.register(SnapzyNetworkAccess.self, summary: "HTTP fetch, scoped to declared hosts.") { scope, _ in
      SnapzyNetworkAccess { request in
        let service = PluginNetworkService()
        guard let response = try await service.fetch(request, allowedHosts: scope.hosts) else {
          throw PluginServiceError(code: "network", message: "The request could not be completed.")
        }
        return response
      }
    }
    registry.register(SnapzyAssetRead.self, summary: "Bytes of the invocation's asset.") { _, _ in
      SnapzyAssetRead {
        throw PluginServiceError(code: "unavailable", message: "Asset read requires an invocation; only script plugins can read invocation assets.")
      }
    }
    registry.register(SnapzyDocumentWrite.self, summary: "Patch the open document.") { _, _ in
      SnapzyDocumentWrite { _ in
        throw PluginServiceError(code: "unavailable", message: "Document writes are applied by the host, not through a capability handle.")
      }
    }
    registry.register(SnapzyClipboardWrite.self, summary: "Write (never read) the clipboard.") { _, _ in
      SnapzyClipboardWrite { text in
        await MainActor.run {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        }
      } writeImage: { data in
        await MainActor.run {
          if let image = NSImage(data: data) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
          }
        }
      }
    }
    registry.register(SnapzySecretsAccess.self, summary: "One Keychain item per plugin.") { _, identity in
      let store = PluginSecretsStore()
      return SnapzySecretsAccess { name in
        try await store.get(name: name, pluginID: identity.id.rawValue)
      } set: { name, value in
        try await store.set(name: name, value: value, pluginID: identity.id.rawValue)
      }
    }
    registry.register(SnapzyOCR.self, summary: "Local Vision OCR with boxes.") { _, _ in
      SnapzyOCR { request in
        try await PluginOCRService().recognize(request)
      }
    }
    registry.register(SnapzyImage.self, summary: "Host-side image decode/resize/crop/encode.") { _, _ in
      SnapzyImage { operation in
        try await PluginImageService().run(operation)
      }
    }
    registry.register(SnapzyMedia.self, summary: "Media inspection/extraction.") { _, _ in
      SnapzyMedia { _ in
        throw PluginServiceError(code: "unavailable", message: "Media operations require an invocation asset.")
      }
    }
    registry.register(SnapzyNotify.self, summary: "Post a notification.") { _, _ in
      SnapzyNotify { title, body in
        _ = await SystemNotificationService.shared.post(title: title, body: body)
      }
    }
    registry.register(SnapzyUI.self, summary: "Declarative host-rendered UI.") { _, _ in
      SnapzyUI { request in
        try await PluginUIService().run(request)
      }
    }
    registry.register(SnapzyStorage.self, summary: "The plugin's own container.") { _, _ in
      SnapzyStorage { _ in
        throw PluginServiceError(code: "unavailable", message: "Storage is provided per plugin through the broker.")
      } set: { _, _ in
        throw PluginServiceError(code: "unavailable", message: "Storage is provided per plugin through the broker.")
      }
    }
  }
}
