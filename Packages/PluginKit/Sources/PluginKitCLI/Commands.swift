import Foundation
import PluginKitCore

// The authoring loop, as three commands. Depends on PluginKitCore only: it reads
// manifests and catalogs as data and never loads plugin code, which keeps it fast
// and keeps the host machinery out of an author's toolchain.

enum Commands {
    // MARK: - describe

    /// Prints a host's published vocabulary.
    ///
    /// Reads the catalog out of an **installed** app, so an author who has
    /// `/Applications/Acme.app` and no source access can still enumerate the
    /// sockets, their contract versions, their metadata shapes, and which of them
    /// are in-process only. Without this, "the host owns the vocabulary" would mean
    /// "ask the host's developer".
    static func describe(_ arguments: Arguments) throws {
        let catalog = try loadCatalog(arguments)

        print("\(catalog.appIdentifier) \(catalog.appVersion)  ·  PluginKit \(catalog.pluginKitVersion)")
        print("")

        if !catalog.vocabularies.isEmpty {
            print("VOCABULARIES")
            for vocabulary in catalog.vocabularies {
                print("  \(vocabulary.id)  \(vocabulary.version)   accepts \(vocabulary.accepts)")
            }
            print("")
        }

        print("EXTENSION POINTS")
        if catalog.extensionPoints.isEmpty {
            print("  (none — this host publishes no extension points)")
        }
        for point in catalog.extensionPoints {
            let locality: String
            switch point.locality {
            case .remotable: locality = "remotable"
            case .local: locality = "LOCAL-ONLY"
            }
            let arity: String
            switch point.arity {
            case .single: arity = "single"
            case .many(let ordering): arity = "many(\(ordering.rawValue))"
            }

            print("  \(point.id)")
            print("      contract \(point.contractVersion)   accepts \(point.accepts)   \(locality)   \(arity)")
            if let summary = point.summary { print("      \(summary)") }
            if case .local(let reason) = point.locality {
                print("      ⚠ in-process only — \(reason)")
            }
            if !point.metadataShape.isEmpty {
                let fields = point.metadataShape
                    .map { "\($0.name): \($0.type)\($0.required ? "" : "?")" }
                    .joined(separator: ", ")
                print("      metadata: \(fields)")
            }
            for deprecation in point.deprecations {
                print(
                    "      ⚠ contract \(deprecation.major).x deprecated since "
                        + "\(deprecation.since), removed in \(deprecation.removedIn)"
                )
                print("        \(deprecation.guidance)")
            }
        }

        if !catalog.capabilities.isEmpty {
            print("")
            print("CAPABILITIES")
            for capability in catalog.capabilities {
                print("  \(capability.id)  [\(capability.sensitivity)]")
                if let summary = capability.summary { print("      \(summary)") }
                if let example = capability.scopeExample { print("      scope e.g. \(example)") }
            }
        }

        if !catalog.topics.isEmpty {
            print("")
            print("EVENT TOPICS")
            for topic in catalog.topics {
                let direction = topic.pluginMayPublish ? "publish + subscribe" : "subscribe only"
                print("  \(topic.id)  (\(direction))")
            }
        }
    }

    // MARK: - validate

    /// Checks a manifest, and — when a catalog is available — checks it against the
    /// host it targets.
    ///
    /// Two levels on purpose. Structural validation needs nothing but the file, so
    /// it always runs. Cross-checking contributions against a real host catches the
    /// mistakes that otherwise surface as a plugin silently missing from a menu.
    static func validate(_ arguments: Arguments) throws -> Int32 {
        let manifestPath = try arguments.requiredValue("manifest")
        let url = URL(fileURLWithPath: manifestPath)
        let manifest = try PluginManifest.load(from: url)

        var problems: [String] = []
        var warnings: [String] = []

        do {
            try manifest.validateStructure()
        } catch {
            problems.append(error.localizedDescription)
        }

        if !manifest.sdkVersion.contains(PluginKitVersion.current) {
            warnings.append(
                "sdkVersion \(manifest.sdkVersion) excludes this PluginKit "
                    + "(\(PluginKitVersion.current)); a host on this version will refuse the plugin."
            )
        }

        if let catalog = try? loadCatalog(arguments) {
            for contract in manifest.contracts {
                guard let vocabulary = catalog.vocabulary(contract.vocabulary) else {
                    warnings.append(
                        "The host does not publish vocabulary '\(contract.vocabulary)'."
                    )
                    continue
                }
                if !contract.compatibleWith.contains(vocabulary.version) {
                    problems.append(
                        "compatibleWith \(contract.compatibleWith) for "
                            + "'\(contract.vocabulary)' excludes the host's \(vocabulary.version)."
                    )
                }
                if !vocabulary.accepts.contains(contract.builtAgainst) {
                    problems.append(
                        "Built against '\(contract.vocabulary)' \(contract.builtAgainst), but the "
                            + "host accepts \(vocabulary.accepts)."
                    )
                }
            }

            for contribution in manifest.contributions {
                guard let point = catalog.extensionPoint(contribution.extensionPoint) else {
                    problems.append(
                        "The host has no extension point '\(contribution.extensionPoint)'."
                    )
                    continue
                }
                if !point.accepts.contains(contribution.contractVersion) {
                    problems.append(
                        "'\(contribution.extensionPoint)' contribution '\(contribution.name)' is "
                            + "built against contract \(contribution.contractVersion); the host "
                            + "accepts \(point.accepts)."
                    )
                }
                for deprecation in point.deprecations
                where deprecation.major == contribution.contractVersion.major {
                    warnings.append(
                        "'\(contribution.extensionPoint)' contract "
                            + "\(deprecation.major).x is deprecated since \(deprecation.since) and "
                            + "will be removed in \(deprecation.removedIn). \(deprecation.guidance)"
                    )
                }
                if case .local(let reason) = point.locality {
                    warnings.append(
                        "'\(contribution.extensionPoint)' is in-process only (\(reason)). A host "
                            + "that does not trust this plugin for in-process hosting will report "
                            + "it unsatisfied."
                    )
                }
            }

            for request in manifest.capabilities where catalog.capability(request.id) == nil {
                let severity = request.required ? "problems" : "warnings"
                let message = "The host does not provide capability '\(request.id)'"
                    + (request.required ? " and the plugin marks it required." : ".")
                if severity == "problems" { problems.append(message) } else { warnings.append(message) }
            }
        } else if arguments.has("host") || arguments.has("catalog") {
            warnings.append("No catalog found; only structural checks were run.")
        }

        // Drift between the manifest and the *code* needs the plugin activated in a
        // harness — see `PluginHarness.drift()`. This command deliberately stops at
        // what can be checked from data alone, so it stays usable in a pre-commit
        // hook and on a machine that cannot build the plugin.
        for problem in problems { printError("✗ \(problem)") }
        for warning in warnings { printError("⚠ \(warning)") }

        if problems.isEmpty {
            print("\(manifest.id) \(manifest.version) — \(warnings.isEmpty ? "ok" : "ok, with warnings")")
            return 0
        }
        printError("")
        printError("\(problems.count) problem(s) in \(manifestPath).")
        return 1
    }

    // MARK: - init

    /// Writes a starter `plugin.json` for a chosen extension point.
    ///
    /// Turns discovery into a compiling starting point. The metadata skeleton comes
    /// from the host's own declared shape, so the first thing an author writes is
    /// already the right shape rather than a guess they will find out about later.
    static func scaffold(_ arguments: Arguments) throws {
        let id = try arguments.requiredValue("id")
        let outputPath = arguments.value("out") ?? PluginBundleLayout.manifestName
        let displayName = arguments.value("name")
            ?? id.split(separator: ".").last.map(String.init)?.capitalized
            ?? id

        var contributions: [Contribution] = []
        var contracts: [ContractDependency] = []

        if let pointID = arguments.value("point") {
            let catalog = try loadCatalog(arguments)
            guard let point = catalog.extensionPoint(ExtensionPointID(pointID)) else {
                throw CLIError.notFound("extension point '\(pointID)' in the host's catalog")
            }

            var metadata: [String: JSONValue] = [:]
            for field in point.metadataShape where field.required {
                metadata[field.name] = Self.placeholder(for: field.type)
            }

            contributions.append(
                Contribution(
                    extensionPoint: point.id,
                    name: "main",
                    contractVersion: point.contractVersion,
                    metadata: .object(metadata)
                )
            )
            contracts.append(
                ContractDependency(
                    vocabulary: point.vocabulary,
                    builtAgainst: catalog.vocabulary(point.vocabulary)?.version
                        ?? point.contractVersion
                )
            )
        }

        let manifest = PluginManifest(
            id: PluginID(id),
            version: "0.1.0",
            displayName: displayName,
            summary: "What this plugin does, in one sentence.",
            sdkVersion: .compatible(with: PluginKitVersion.current),
            contracts: contracts,
            runtime: .inProcess(entryPoint: nil),
            activation: .onDemand,
            contributions: contributions
        )

        let url = URL(fileURLWithPath: outputPath)
        guard !FileManager.default.fileExists(atPath: url.path) || arguments.has("force") else {
            throw CLIError.failed("\(outputPath) already exists. Pass --force to overwrite.")
        }
        try manifest.encoded().write(to: url, options: .atomic)

        print("Wrote \(outputPath)")
        print("")
        print("Next:")
        print("  1. Add PluginKitSDK and the host's contract package to Package.swift.")
        print("  2. Implement `Plugin`, registering a factory for each contribution above.")
        print("  3. Subclass `PluginPrincipal` and set NSPrincipalClass in Info.plist.")
        print("  4. Run `pluginkit validate --manifest \(outputPath)` in your build.")
    }

    private static func placeholder(for type: String) -> JSONValue {
        switch type.lowercased() {
        case "bool", "boolean": return .bool(false)
        case "int", "integer": return .int(0)
        case "double", "float": return .double(0)
        case let value where value.hasPrefix("["): return .array([])
        default: return .string("TODO")
        }
    }

    // MARK: - Catalog lookup

    /// Finds a catalog from `--catalog`, or inside an app bundle from `--host`.
    static func loadCatalog(_ arguments: Arguments) throws -> CatalogDocument {
        if let path = arguments.value("catalog") {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CLIError.notFound(path)
            }
            return try CatalogDocument.load(from: url)
        }

        guard let hostPath = arguments.value("host") else {
            throw CLIError.missingOption("--host or --catalog")
        }

        let directory = URL(fileURLWithPath: hostPath)
            .appendingPathComponent(PluginBundleLayout.catalogResourcePath, isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []

        guard let catalogURL = contents
            .filter({ $0.lastPathComponent.hasSuffix(".catalog.json") })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .first
        else {
            throw CLIError.notFound(
                "a *.catalog.json in \(hostPath)/\(PluginBundleLayout.catalogResourcePath). "
                    + "The host may not emit one — ask its developer, or pass --catalog."
            )
        }
        return try CatalogDocument.load(from: catalogURL)
    }
}
