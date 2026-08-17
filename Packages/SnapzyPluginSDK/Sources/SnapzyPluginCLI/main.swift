import Foundation
import SnapzyPluginCLICore

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))

let usage = """
snapzy-plugin — Snapzy Native Plugin CLI

USAGE
  snapzy-plugin init <id> [--name <name>] [--out <path>]
      Scaffold a new native Swift plugin project.

  snapzy-plugin build [--debug] [--universal] [--arch <arch>] [--out <path>]
      Compile the plugin executable and assemble the .snapzyplugin bundle.

  snapzy-plugin sign [--identity <id>] [--adhoc] [path]
      Apply minimal sandbox entitlements and codesign the bundle.

  snapzy-plugin validate [path]
      Validate a plugin.json manifest or an assembled plugin bundle.

  snapzy-plugin package [--identity <id>] [--out <dir>]
      Build, sign, zip, and generate a paste-ready index entry.

  snapzy-plugin dev
      Build, sign with adhoc sandbox entitlements, and install into Snapzy dev folder.

  snapzy-plugin doctor
      Check local developer environment, Swift compiler, and signing certificates.

  snapzy-plugin version
"""

do {
  switch arguments.command {
  case "init":
    try InitCommand.run(arguments)
  case "build":
    _ = try BuildCommand.run(arguments)
  case "sign":
    try SignCommand.run(arguments)
  case "validate":
    try ValidateCommand.run(arguments)
  case "package":
    try PackageCommand.run(arguments)
  case "dev":
    try DevCommand.run(arguments)
  case "doctor":
    try DoctorCommand.run(arguments)
  case "version":
    print("1.0.0")
  case "help", "-h", "--help":
    print(usage)
  default:
    printError("Unknown command '\(arguments.command)'.\n")
    printError(usage)
    exit(64)
  }
} catch let error as CLIError {
  printError("✗ \(error.description)")
  exit(1)
} catch {
  printError("✗ \(error.localizedDescription)")
  exit(1)
}
