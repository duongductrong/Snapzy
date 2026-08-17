import Foundation

public enum DoctorCommand {
  public static func run(_ args: Arguments) throws {
    print("Snapzy Plugin Doctor\n====================")

    // Swift version
    if let swiftPath = ProcessRunner.which("swift") {
      let swiftVer = (try? ProcessRunner.run("/usr/bin/swift", arguments: ["--version"]))?.stdout.components(separatedBy: "\n").first ?? "unknown"
      print("✓ Swift compiler: \(swiftPath) (\(swiftVer))")
    } else {
      print("✗ Swift compiler not found. Please install Xcode Command Line Tools.")
    }

    // codesign
    if let codesignPath = ProcessRunner.which("codesign") {
      print("✓ Code signing tool: \(codesignPath)")
    } else {
      print("✗ codesign utility not found.")
    }

    // Developer ID certificates
    let certsOutput = (try? ProcessRunner.run("/usr/bin/security", arguments: ["find-identity", "-v", "-p", "codesigning"]))?.stdout ?? ""
    let devIDLines = certsOutput.components(separatedBy: "\n").filter { $0.contains("Developer ID Application:") }
    if !devIDLines.isEmpty {
      print("✓ Available Developer ID Certificates:")
      for line in devIDLines {
        print("    \(line.trimmingCharacters(in: .whitespaces))")
      }
    } else {
      print("ℹ No Developer ID Application certificates found (adhoc signing available for development).")
    }

    print("\nEnvironment check complete.")
  }
}
