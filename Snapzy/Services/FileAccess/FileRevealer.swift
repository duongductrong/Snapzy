//
//  FileRevealer.swift
//  Snapzy
//
//  Shows files in Finder with scoped access. One entry point for History,
//  Quick Access and automation "Reveal" steps.
//

import AppKit
import Foundation

@MainActor
enum FileRevealer {
  static func reveal(_ urls: [URL]) {
    let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !existing.isEmpty else {
      DiagnosticLogger.shared.log(.warning, .action, "Reveal in Finder skipped; file missing")
      return
    }
    let accesses = existing.map { SandboxFileAccessManager.shared.beginAccessingURL($0) }
    defer { accesses.forEach { $0.stop() } }
    NSWorkspace.shared.activateFileViewerSelecting(existing)
  }
}
