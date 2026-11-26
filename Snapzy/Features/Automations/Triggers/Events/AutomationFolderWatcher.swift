//
//  AutomationFolderWatcher.swift
//  Snapzy
//
//  Watches one folder (top level only) for new image / video / GIF files.
//  A vnode dispatch source on the folder's descriptor wakes it on changes, so
//  an idle folder costs nothing (no polling). Changes are coalesced, the
//  folder is listed on a utility queue and diffed against what it already
//  held, and a new file fires only once its size stopped changing (downloads
//  and recordings are written over time). Files present when watching starts
//  never fire.
//

import Foundation

nonisolated final class AutomationFolderWatcher: @unchecked Sendable {
  struct Timing: Sendable {
    var coalesce: TimeInterval = AutomationEventLimits.folderCoalesceDelay
    var stability: TimeInterval = AutomationEventLimits.folderStabilityDelay
    var maxSettle: TimeInterval = AutomationEventLimits.folderMaxSettleTime
    /// An empty file (placeholder, failed download) is given up this much sooner.
    var maxEmpty: TimeInterval = AutomationEventLimits.folderMaxEmptyTime
    /// Rescans of files still settling slow down to this interval.
    var maxRescanInterval: TimeInterval = AutomationEventLimits.folderMaxRescanInterval
  }

  private struct Pending {
    var size: Int
    var sizeSince: Date
    let firstSeen: Date
  }

  let folder: URL
  private let timing: Timing
  private let queue: DispatchQueue
  private let now: @Sendable () -> Date
  private let isOwnFile: @Sendable (URL) -> Bool
  /// Called on the watcher's queue with the files that settled, in name order.
  private let onNewFiles: @Sendable ([URL]) -> Void
  /// The folder was deleted or moved; the watcher stopped.
  private let onFolderGone: @Sendable () -> Void

  // Touched only on `queue`.
  private var source: DispatchSourceFileSystemObject?
  private var known = Set<String>()
  private var pending: [String: Pending] = [:]
  private var scanScheduled = false
  private var isAccessingScope = false
  private var isResumed = false

  init(
    folder: URL,
    timing: Timing = Timing(),
    now: @escaping @Sendable () -> Date = { Date() },
    isOwnFile: @escaping @Sendable (URL) -> Bool = { AutomationFileOriginTracker.shared.wasWrittenBySnapzy($0) },
    onNewFiles: @escaping @Sendable ([URL]) -> Void,
    onFolderGone: @escaping @Sendable () -> Void = {}
  ) {
    self.folder = folder.standardizedFileURL.resolvingSymlinksInPath()
    self.timing = timing
    self.now = now
    self.isOwnFile = isOwnFile
    self.onNewFiles = onNewFiles
    self.onFolderGone = onFolderGone
    queue = DispatchQueue(label: "com.snapzy.automations.folder-watch", qos: .utility)
  }

  deinit {
    if let source, !isResumed { source.resume() }
    source?.cancel()
  }

  /// Opens the folder and starts listening; the baseline listing runs on the
  /// watcher's queue, never on the caller's thread. `false` when the folder
  /// can't be opened.
  @discardableResult
  func start() -> Bool {
    queue.sync { startOnQueue() }
  }

  /// Never waits: a scan of a large folder may be running on the queue.
  func stop() {
    queue.async { self.stopOnQueue() }
  }

  /// Lists the folder now (tests, and a nudge after the app wakes).
  func scanNow() {
    queue.sync { scan() }
  }

  // MARK: - Queue

  private func startOnQueue() -> Bool {
    guard source == nil else { return true }
    isResumed = false
    isAccessingScope = folder.startAccessingSecurityScopedResource()
    let descriptor = open(folder.path, O_EVTONLY)
    guard descriptor >= 0 else {
      if isAccessingScope { folder.stopAccessingSecurityScopedResource() }
      isAccessingScope = false
      return false
    }
    pending = [:]

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .delete, .rename, .revoke],
      queue: queue
    )
    source.setEventHandler { [weak self] in
      guard let self, let source = self.source else { return }
      let event = source.data
      if event.contains(.delete) || event.contains(.rename) || event.contains(.revoke) {
        self.stopOnQueue()
        self.onFolderGone()
        return
      }
      self.scheduleScan(after: self.timing.coalesce)
    }
    source.setCancelHandler {
      close(descriptor)
    }
    self.source = source
    // Serial queue: the baseline is taken before any event is handled.
    queue.async { [weak self] in
      // Stopped (or stopped and restarted) before the baseline: not ours to resume.
      guard let self, self.source === source, !self.isResumed else { return }
      self.known = Set(self.listFiles().map(\.name))
      self.isResumed = true
      source.resume()
    }
    return true
  }

  private func stopOnQueue() {
    // A source still waiting for its baseline was never resumed; cancelling a
    // suspended source never runs its cancel handler, so resume it first.
    if let source, !isResumed { source.resume() }
    source?.cancel()
    source = nil
    pending = [:]
    scanScheduled = false
    if isAccessingScope {
      folder.stopAccessingSecurityScopedResource()
      isAccessingScope = false
    }
  }

  private func scheduleScan(after delay: TimeInterval) {
    guard !scanScheduled else { return }
    scanScheduled = true
    queue.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self else { return }
      self.scanScheduled = false
      guard self.source != nil else { return }
      self.scan()
    }
  }

  private func scan() {
    let files = listFiles()
    let date = now()
    let present = Set(files.map(\.name))
    // Forget deleted files, so the same name added again fires again.
    known.formIntersection(present)
    pending = pending.filter { present.contains($0.key) }

    var ready: [URL] = []
    for file in files where !known.contains(file.name) {
      guard var entry = pending[file.name] else {
        pending[file.name] = Pending(size: file.size, sizeSince: date, firstSeen: date)
        continue
      }
      if entry.size != file.size {
        entry.size = file.size
        entry.sizeSince = date
        pending[file.name] = entry
      } else if file.size > 0, date.timeIntervalSince(entry.sizeSince) >= timing.stability {
        pending.removeValue(forKey: file.name)
        known.insert(file.name)
        if !isOwnFile(file.url) { ready.append(file.url) }
        continue
      }
      let age = date.timeIntervalSince(entry.firstSeen)
      if age > timing.maxSettle || (file.size == 0 && age > timing.maxEmpty) {
        // Never settled (stuck download, endless writer): give up on it.
        pending.removeValue(forKey: file.name)
        known.insert(file.name)
      }
    }

    if !pending.isEmpty, source != nil {
      // A file that takes long to settle (big download) is checked less often,
      // so a large folder isn't listed every half second for minutes.
      let oldest = pending.values.map { date.timeIntervalSince($0.firstSeen) }.min() ?? 0
      let delay = oldest < 10 ? timing.stability : min(timing.maxRescanInterval, max(timing.stability, oldest / 10))
      scheduleScan(after: delay)
    }
    if !ready.isEmpty {
      onNewFiles(ready.sorted { $0.lastPathComponent < $1.lastPathComponent })
    }
  }

  private struct Listed {
    let name: String
    let url: URL
    let size: Int
  }

  /// Supported, visible, regular files at the top level.
  private func listFiles() -> [Listed] {
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
    ) else { return [] }
    return urls.compactMap { url in
      guard AutomationFileKind.of(url) != nil,
            let values = try? url.resourceValues(forKeys: Set(keys)),
            values.isRegularFile == true
      else { return nil }
      return Listed(name: url.lastPathComponent, url: url, size: values.fileSize ?? 0)
    }
  }
}
