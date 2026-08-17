import Foundation
import PluginKitCore

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))

let usage = """
pluginkit — PluginKit authoring tools

USAGE
  pluginkit describe --host <app-path> | --catalog <file>
      Print a host's extension points, capabilities, and topics.

  pluginkit validate --manifest <plugin.json> [--host <app-path> | --catalog <file>]
      Check a manifest. With a host or catalog, also cross-check contributions,
      contract versions, and capabilities against it.
      Exits non-zero on a problem, so it can gate a build.

  pluginkit init --id <plugin-id> [--point <extension-point-id>]
                 [--host <app-path> | --catalog <file>]
                 [--name <display-name>] [--out <path>] [--force]
      Write a starter plugin.json, with the metadata shape filled in from the
      host's own catalog.

  pluginkit version

NOTES
  This tool reads manifests and catalogs as data and never loads plugin code, so
  it is safe to run against a host you do not trust and fast enough for a
  pre-commit hook.

  It cannot see drift between a manifest and a plugin's *code* — that needs the
  plugin activated. Use PluginHarness.drift() from PluginKitTesting for that.
"""

do {
    switch arguments.command {
    case "describe":
        try Commands.describe(arguments)

    case "validate":
        exit(try Commands.validate(arguments))

    case "init":
        try Commands.scaffold(arguments)

    case "version":
        print(PluginKitVersion.current.description)

    case "help", "-h", "--help":
        print(usage)

    default:
        printError("Unknown command '\(arguments.command)'.\n")
        printError(usage)
        exit(64)  // EX_USAGE
    }
} catch let error as CLIError {
    printError("✗ \(error.description)")
    exit(1)
} catch {
    printError("✗ \(error.localizedDescription)")
    exit(1)
}
