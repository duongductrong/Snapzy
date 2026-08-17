import Foundation

public enum InitCommand {
  public static func run(_ args: Arguments) throws {
    guard let id = args.positional.first ?? args.value("id") else {
      throw CLIError.missingArgument("plugin-id (e.g. com.example.myplugin)")
    }

    let rawName = args.value("name") ?? id.split(separator: ".").last.map(String.init) ?? "MyPlugin"
    let pluginName = rawName.prefix(1).uppercased() + rawName.dropFirst()

    let outPath = args.value("out") ?? FileManager.default.currentDirectoryPath
    let targetDir = URL(fileURLWithPath: outPath, isDirectory: true)

    let fm = FileManager.default
    try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

    let sourcesDir = targetDir.appendingPathComponent("Sources/\(pluginName)", isDirectory: true)
    let testsDir = targetDir.appendingPathComponent("Tests/\(pluginName)Tests", isDirectory: true)
    try fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: testsDir, withIntermediateDirectories: true)

    try Templates.packageSwift(pluginName: pluginName)
      .write(to: targetDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

    try Templates.pluginJson(id: id, name: pluginName, executable: pluginName)
      .write(to: targetDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)

    try Templates.sourceFile(pluginName: pluginName)
      .write(to: sourcesDir.appendingPathComponent("\(pluginName).swift"), atomically: true, encoding: .utf8)

    try Templates.testFile(pluginName: pluginName)
      .write(to: testsDir.appendingPathComponent("\(pluginName)Tests.swift"), atomically: true, encoding: .utf8)

    try Templates.gitIgnore()
      .write(to: targetDir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

    try Templates.readme(name: pluginName, id: id)
      .write(to: targetDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

    print("Created plugin \(id) in \(targetDir.path)")
    print("Next steps:")
    print("  cd \(targetDir.path)")
    print("  swift test")
    print("  snapzy-plugin dev")
  }
}
