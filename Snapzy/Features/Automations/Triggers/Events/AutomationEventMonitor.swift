//
//  AutomationEventMonitor.swift
//  Snapzy
//
//  Owns the event triggers (milestone 7). Follows the store: a clipboard
//  watcher and one folder watcher per watched folder exist only while an
//  enabled automation needs them, so with no event trigger configured nothing
//  runs at all. Events become runs through `AutomationEventDispatcher`.
//  "Pause event triggers" (Settings → Automations → Advanced) stops them all.
//

import AppKit
import Combine
import Foundation
import ImageIO

@MainActor
final class AutomationEventMonitor {
  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  static let shared = AutomationEventMonitor()

  private struct FolderEntry {
    let watcher: AutomationFolderWatcher
    var automationIDs: Set<UUID>
  }

  private let store: AutomationStore
  private let folders: AutomationFolderAccessStore
  private let defaults: UserDefaults
  let dispatcher: AutomationEventDispatcher
  private let makeClipboardWatcher: (@escaping (Int) -> Void) -> AutomationClipboardWatcher
  /// Reads the image only while the clipboard still holds the checked change.
  private let readClipboardImage: @MainActor (Int) async -> AutomationClipboardImage?

  private var subscription: AnyCancellable?
  private var clipboardWatcher: AutomationClipboardWatcher?
  private var clipboardAutomationIDs = Set<UUID>()
  private var folderWatchers: [String: FolderEntry] = [:]
  /// What a breaker-paused automation looked like; an edit lifts the pause.
  private var pausedSnapshots: [UUID: Automation] = [:]
  /// Folders that failed to open, logged once until they change.
  private var unavailableFolders = Set<String>()

  init(
    store: AutomationStore = .shared,
    folders: AutomationFolderAccessStore = .shared,
    defaults: UserDefaults = .standard,
    dispatcher: AutomationEventDispatcher? = nil,
    makeClipboardWatcher: ((@escaping (Int) -> Void) -> AutomationClipboardWatcher)? = nil,
    readClipboardImage: (@MainActor (Int) async -> AutomationClipboardImage?)? = nil
  ) {
    self.store = store
    self.folders = folders
    self.defaults = defaults
    let dispatcher = dispatcher ?? AutomationEventDispatcher()
    self.dispatcher = dispatcher
    self.makeClipboardWatcher = makeClipboardWatcher ?? { AutomationClipboardWatcher(onImageCopied: $0) }
    self.readClipboardImage = readClipboardImage ?? { await AutomationClipboardImage.read(expectedChangeCount: $0) }
    dispatcher.onBurstPaused = { [weak self] id in self?.handleBurstPause(id) }
  }

  /// Follows the store from now on. Call once at launch.
  func start() {
    guard subscription == nil else { return }
    subscription = store.$automations
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.reconcile() }
    reconcile()
  }

  var isPaused: Bool {
    defaults.bool(forKey: PreferencesKeys.automationsEventTriggersPaused)
  }

  // MARK: - Reconcile

  /// Starts and stops watchers to match the automations. Cheap; safe to call often.
  func reconcile() {
    let candidates = isPaused ? [] : eventAutomations()
    if isPaused { dispatcher.cancelPending() }
    liftPausesForEditedAutomations()
    let active = candidates.filter { !dispatcher.pausedAutomationIDs.contains($0.id) }

    // Clipboard and folder events never run script / Shortcut steps (the
    // launcher refuses them), so don't read the clipboard or watch for them.
    let foreignContentOK = active.filter { !reachesCodeSteps($0) }

    // Clipboard
    clipboardAutomationIDs = Set(foreignContentOK.filter(\.runsOnClipboardChange).map(\.id))
    if clipboardAutomationIDs.isEmpty {
      clipboardWatcher?.stop()
      clipboardWatcher = nil
    } else if clipboardWatcher == nil {
      let watcher = makeClipboardWatcher { [weak self] count in self?.handleClipboardChange(changeCount: count) }
      watcher.start()
      clipboardWatcher = watcher
      DiagnosticLogger.shared.log(.info, .action, "Automation clipboard trigger started")
    }

    // Folders
    var wanted: [String: (url: URL, ids: Set<UUID>)] = [:]
    for automation in foreignContentOK {
      guard let ref = automation.folderWatch?.folder, let url = folders.resolve(ref) else { continue }
      let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
      wanted[resolved.path, default: (resolved, [])].ids.insert(automation.id)
    }
    for (path, entry) in folderWatchers where wanted[path] == nil {
      entry.watcher.stop()
      folderWatchers[path] = nil
    }
    for (path, want) in wanted {
      if folderWatchers[path] != nil {
        folderWatchers[path]?.automationIDs = want.ids
        continue
      }
      let watcher = AutomationFolderWatcher(
        folder: want.url,
        onNewFiles: { files in
          Task { @MainActor [weak self] in self?.handleFolderFiles(files, path: path) }
        },
        onFolderGone: {
          Task { @MainActor [weak self] in self?.handleFolderGone(path) }
        }
      )
      guard watcher.start() else {
        if unavailableFolders.insert(path).inserted {
          DiagnosticLogger.shared.log(.warning, .action, "Automation folder trigger could not watch folder", context: ["folder": want.url.lastPathComponent])
        }
        continue
      }
      unavailableFolders.remove(path)
      folderWatchers[path] = FolderEntry(watcher: watcher, automationIDs: want.ids)
      DiagnosticLogger.shared.log(.info, .action, "Automation folder trigger started", context: ["folder": want.url.lastPathComponent])
    }

    // Queued runs of automations that lost their event triggers are dropped.
    let activeIDs = Set(active.map(\.id))
    for automation in store.automations where !activeIDs.contains(automation.id) {
      dispatcher.cancelPending(automation.id)
    }
  }

  /// Enabled, runnable automations with at least one event trigger.
  private func eventAutomations() -> [Automation] {
    store.automations.filter { $0.isEnabled && !$0.hasUnsupportedSource && !$0.needsReview && $0.hasEventTriggers }
  }

  private func reachesCodeSteps(_ automation: Automation) -> Bool {
    automation.reachableAutomations(lookup: { [store] in store.automation(id: $0) }).contains(where: \.containsCodeSteps)
  }

  private func liftPausesForEditedAutomations() {
    for id in dispatcher.pausedAutomationIDs {
      let current = store.automation(id: id)
      if current == nil || current != pausedSnapshots[id] {
        dispatcher.resume(id)
        pausedSnapshots[id] = nil
      }
    }
  }

  var activeFolderPaths: Set<String> { Set(folderWatchers.keys) }
  var isWatchingClipboard: Bool { clipboardWatcher != nil }

  // MARK: - Events

  /// A standard capture finished its default automation (`PostCaptureActionHandler`).
  func captureSaved(type: CaptureType, urls: [URL]) {
    guard !isPaused else { return }
    let kind = AutomationCaptureEventKind(type)
    let files = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !files.isEmpty else { return }
    for automation in eventAutomations() {
      guard let config = automation.captureEvent, config.kinds.contains(kind) else { continue }
      dispatch(automation, invocation: .captureSaved, files: files, isAlreadyInHistory: true)
    }
  }

  func handleFolderFiles(_ files: [URL], path: String) {
    guard !isPaused, let entry = folderWatchers[path] else { return }
    // Snapzy may have marked a file between the scan and now.
    let foreign = files.filter { !AutomationFileOriginTracker.shared.wasWrittenBySnapzy($0) }
    guard !foreign.isEmpty else { return }
    DiagnosticLogger.shared.log(.info, .action, "Automation folder trigger fired", context: ["files": "\(foreign.count)"])
    for id in entry.automationIDs {
      guard let automation = store.automation(id: id) else { continue }
      dispatch(automation, invocation: .folderWatch, files: foreign, isAlreadyInHistory: true)
    }
  }

  private func handleClipboardChange(changeCount: Int) {
    guard !isPaused, !clipboardAutomationIDs.isEmpty else { return }
    let ids = clipboardAutomationIDs
    Task { @MainActor [weak self] in
      guard let self, let image = await self.readClipboardImage(changeCount) else { return }
      // The original file when an image file was copied; else a new PNG in temp.
      if image.isNewFile { AutomationFileOriginTracker.shared.markWritten([image.url]) }
      DiagnosticLogger.shared.log(.info, .action, "Automation clipboard trigger fired")
      for id in ids {
        guard let automation = self.store.automation(id: id) else { continue }
        // Not added to History: copying in another app must not fill it.
        self.dispatch(automation, invocation: .clipboardChange, files: [image.url], isAlreadyInHistory: true)
      }
    }
  }

  private func handleFolderGone(_ path: String) {
    guard folderWatchers.removeValue(forKey: path) != nil else { return }
    DiagnosticLogger.shared.log(.warning, .action, "Automation folder trigger stopped; folder moved or deleted")
    // A folder replaced in place (sync clients, `mv` back) is picked up again.
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      self?.reconcile()
    }
  }

  /// Only the files a step can work on; nothing queued for an automation that
  /// can't take any of them (avoids a rejection per file in the log).
  private func dispatch(_ automation: Automation, invocation: AutomationInvocation, files: [URL], isAlreadyInHistory: Bool) {
    let accepted = files.filter { file in
      guard let kind = AutomationFileKind.of(file) else { return false }
      return automation.acceptsFile(of: kind)
    }
    guard !accepted.isEmpty else { return }
    dispatcher.enqueue(automation.id, invocation: invocation, files: accepted, isAlreadyInHistory: isAlreadyInHistory)
  }

  private func handleBurstPause(_ id: UUID) {
    pausedSnapshots[id] = store.automation(id: id)
    let name = store.automation(id: id)?.displayName ?? ""
    AppToastManager.shared.show(message: L10n.Automations.eventTriggersBurstPaused(name), style: .warning)
    reconcile()
  }
}

// MARK: - Clipboard image

/// The image a clipboard event runs on.
struct AutomationClipboardImage: Sendable {
  let url: URL
  /// `true`: a PNG Snapzy just wrote from pixel data; `false`: the copied file itself.
  let isNewFile: Bool

  /// Reads the general pasteboard on the main actor; encoding and writing the
  /// PNG happen off the main thread so a large copy never stalls the UI.
  @MainActor
  static func read(from pasteboard: NSPasteboard = .general, expectedChangeCount: Int) async -> AutomationClipboardImage? {
    // Changed since it was checked (password-manager markers etc.): skip it.
    guard pasteboard.changeCount == expectedChangeCount else { return nil }
    let files = pasteboard.fileURLs().filter {
      let kind = AutomationFileKind.of($0)
      return kind == .image || kind == .gif
    }
    if let file = files.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
      return AutomationClipboardImage(url: file, isNewFile: false)
    }
    let preferred: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), NSPasteboard.PasteboardType("public.heic")]
    guard let type = pasteboard.availableType(from: preferred), let data = pasteboard.data(forType: type) else {
      return nil
    }
    let directory = TempCaptureManager.shared.tempCaptureDirectory
    let isPNG = type == .png
    let url: URL? = await Task.detached(priority: .utility) {
      Self.writePNG(data, alreadyPNG: isPNG, into: directory)
    }.value
    return url.map { AutomationClipboardImage(url: $0, isNewFile: true) }
  }

  private nonisolated static func writePNG(_ data: Data, alreadyPNG: Bool, into directory: URL) -> URL? {
    let png: Data
    if alreadyPNG {
      png = data
    } else {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else { return nil }
      let output = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else { return nil }
      png = output as Data
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent("Snapzy_Clipboard_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(6)).png")
      try png.write(to: url, options: .atomic)
      return url
    } catch {
      return nil
    }
  }
}
