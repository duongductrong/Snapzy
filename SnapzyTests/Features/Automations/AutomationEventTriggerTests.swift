//
//  AutomationEventTriggerTests.swift
//  SnapzyTests
//
//  Event triggers (milestone 7): model round trip and normalization, the
//  dispatcher's queueing / concurrency / breaker, the folder watcher's
//  baseline, stability and loop guard, the clipboard watcher's filtering, the
//  launcher gate for foreign content, the monitor's watcher lifecycle and the
//  recipe / TOML handling.
//

import AppKit
import XCTest
@testable import Snapzy

// MARK: - Model

@MainActor
final class AutomationEventTriggerModelTests: XCTestCase {
  private func roundTrip(_ automation: Automation) throws -> Automation {
    try JSONDecoder().decode(Automation.self, from: JSONEncoder().encode(automation))
  }

  func testEventTriggersRoundTrip() throws {
    let folderID = UUID()
    var automation = Automation(name: "Events", source: .input, steps: [AutomationStep(.copyImage)])
    automation.captureEvent = AutomationCaptureEventConfig(kinds: [.screenshot, .recording])
    automation.runsOnClipboardChange = true
    automation.folderWatch = AutomationFolderWatchConfig(folder: .bookmark(folderID), folderPath: "/tmp/x")

    let decoded = try roundTrip(automation)
    XCTAssertEqual(decoded.captureEvent?.kinds, [.screenshot, .recording])
    XCTAssertTrue(decoded.runsOnClipboardChange)
    XCTAssertEqual(decoded.folderWatch?.folder, .bookmark(folderID))
    XCTAssertEqual(decoded.folderWatch?.folderPath, "/tmp/x")
    XCTAssertTrue(decoded.hasEventTriggers)
  }

  func testStoredJSONShape() throws {
    let data = try JSONEncoder().encode(AutomationTrigger.captureSaved(AutomationCaptureEventConfig(kinds: [.recording])))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(object["kind"] as? String, "captureSaved")
    XCTAssertEqual((object["config"] as? [String: Any])?["kinds"] as? [String], ["recording"])
  }

  func testUnknownCaptureKindIsDroppedNotFatal() throws {
    let json = #"{"kind":"captureSaved","config":{"kinds":["screenshot","hologram"]}}"#
    let trigger = try JSONDecoder().decode(AutomationTrigger.self, from: Data(json.utf8))
    XCTAssertEqual(trigger, .captureSaved(AutomationCaptureEventConfig(kinds: [.screenshot])))
  }

  func testNormalizationKeepsOneOfEachAndDropsEmptyCaptureEvent() {
    var automation = Automation(name: "N", source: .input, steps: [AutomationStep(.copyImage)])
    automation.triggers = [
      .clipboardChange, .clipboardChange,
      .captureSaved(AutomationCaptureEventConfig(kinds: [])),
      .folderWatch(AutomationFolderWatchConfig(folderPath: "/a")),
      .folderWatch(AutomationFolderWatchConfig(folderPath: "/b")),
    ]
    let normalized = automation.normalized()
    XCTAssertEqual(normalized.triggers.filter { $0 == .clipboardChange }.count, 1)
    XCTAssertNil(normalized.captureEvent, "An empty capture event never fires")
    XCTAssertEqual(normalized.folderWatch?.folderPath, "/a")
    XCTAssertEqual(normalized.triggers.count, 2)
  }

  func testInputSourceKeepsEventTriggers() {
    // Events hand files in, so a "Run on a File" automation can use them.
    var automation = Automation(name: "Input", source: .input, steps: [AutomationStep(.copyImage)])
    automation.runsOnClipboardChange = true
    automation.captureEvent = AutomationCaptureEventConfig()
    XCTAssertTrue(automation.normalized().runsOnClipboardChange)
    XCTAssertNotNil(automation.normalized().captureEvent)
  }

  func testSettersReplaceInPlace() {
    var automation = Automation(name: "S", source: .input, steps: [AutomationStep(.copyImage)])
    automation.captureEvent = AutomationCaptureEventConfig(kinds: [.screenshot])
    automation.captureEvent = AutomationCaptureEventConfig(kinds: [.recording])
    XCTAssertEqual(automation.triggers, [.captureSaved(AutomationCaptureEventConfig(kinds: [.recording]))])
    automation.captureEvent = nil
    XCTAssertTrue(automation.triggers.isEmpty)
  }

  func testInvocationFlags() {
    XCTAssertTrue(AutomationInvocation.folderWatch.isEvent)
    XCTAssertTrue(AutomationInvocation.clipboardChange.handsInForeignContent)
    XCTAssertFalse(AutomationInvocation.captureSaved.handsInForeignContent)
    XCTAssertFalse(AutomationInvocation.captureSaved.isExternal)
    XCTAssertEqual(AutomationLaunchRejection.eventCodeNotAllowed.code, "event_code_not_allowed")
  }

  func testRecipeStripsEventTriggers() {
    var automation = Automation(name: "Shared", source: .input, steps: [AutomationStep(.copyImage)])
    automation.runsOnClipboardChange = true
    automation.showsInQuickAccess = true
    automation.folderWatch = AutomationFolderWatchConfig(folder: .bookmark(UUID()), folderPath: "/x")
    let exported = AutomationRecipeCodec.stripped(automation, folderPath: { _ in "/x" })
    XCTAssertFalse(exported.hasEventTriggers)
    XCTAssertTrue(exported.showsInQuickAccess)

    let imported = AutomationRecipeCodec.prepareForImport([automation])
    XCTAssertFalse(imported[0].hasEventTriggers, "A crafted recipe must not start running by itself")
  }

  func testTOMLCaptureEventTokens() {
    for kinds: Set<AutomationCaptureEventKind> in [[.screenshot], [.recording], [.screenshot, .recording]] {
      let token = SnapzyConfigurationAutomationsCodec.captureEventToken(AutomationCaptureEventConfig(kinds: kinds))
      XCTAssertEqual(SnapzyConfigurationAutomationsCodec.captureEventConfig(token)?.kinds, kinds)
    }
    XCTAssertEqual(SnapzyConfigurationAutomationsCodec.captureEventToken(nil), "off")
    XCTAssertEqual(SnapzyConfigurationAutomationsCodec.captureEventConfig("off")?.kinds, [])
    XCTAssertNil(SnapzyConfigurationAutomationsCodec.captureEventConfig("sometimes"))
  }
}

// MARK: - Dispatcher

@MainActor
final class AutomationEventDispatcherTests: XCTestCase {
  private var launches: [(UUID, AutomationInvocation, URL)] = []
  private var gates: [CheckedContinuation<Void, Never>] = []
  private var holdRuns = false
  private var nextOutcome: AutomationLaunchOutcome = .cancelled
  private var clock = Date(timeIntervalSince1970: 1000)

  private func makeDispatcher(maxConcurrent: Int = 2, maxPending: Int = 20, burstLimit: Int = 100) -> AutomationEventDispatcher {
    AutomationEventDispatcher(
      launch: { [unowned self] id, invocation, input in
        launches.append((id, invocation, input.files[0]))
        if holdRuns {
          await withCheckedContinuation { gates.append($0) }
        }
        return nextOutcome
      },
      now: { [unowned self] in clock },
      maxConcurrent: maxConcurrent,
      maxPending: maxPending,
      burstLimit: burstLimit,
      burstWindow: 60
    )
  }

  private func files(_ count: Int) -> [URL] {
    (0 ..< count).map { URL(fileURLWithPath: "/tmp/event-\($0).png") }
  }

  /// Lets queued `Task`s run.
  private func settle() async {
    for _ in 0 ..< 20 { await Task.yield() }
  }

  private func releaseOne() async {
    guard !gates.isEmpty else { return }
    gates.removeFirst().resume()
    await settle()
  }

  func testOneRunAtATimePerAutomationInOrder() async {
    holdRuns = true
    let dispatcher = makeDispatcher()
    let id = UUID()
    dispatcher.enqueue(id, invocation: .folderWatch, files: files(3), isAlreadyInHistory: true)
    await settle()
    XCTAssertEqual(launches.count, 1)
    XCTAssertEqual(dispatcher.pendingCount(for: id), 2)

    await releaseOne()
    await releaseOne()
    await releaseOne()
    XCTAssertEqual(launches.map(\.2.lastPathComponent), ["event-0.png", "event-1.png", "event-2.png"])
    XCTAssertTrue(dispatcher.isIdle)
  }

  func testGlobalConcurrencyCap() async {
    holdRuns = true
    let dispatcher = makeDispatcher(maxConcurrent: 2)
    let ids = [UUID(), UUID(), UUID()]
    for id in ids {
      dispatcher.enqueue(id, invocation: .clipboardChange, files: files(1), isAlreadyInHistory: false)
    }
    await settle()
    XCTAssertEqual(dispatcher.runningCount, 2)
    XCTAssertEqual(launches.count, 2)
    await releaseOne()
    XCTAssertEqual(launches.count, 3, "The waiting automation starts when a slot frees")
    await releaseOne()
    await releaseOne()
  }

  func testQueueCapAndDuplicates() async {
    holdRuns = true
    let dispatcher = makeDispatcher(maxConcurrent: 1, maxPending: 3)
    let id = UUID()
    dispatcher.enqueue(id, invocation: .folderWatch, files: files(1), isAlreadyInHistory: true)
    await settle()
    // The first is running; three more fit, duplicates collapse, the rest drop.
    dispatcher.enqueue(id, invocation: .folderWatch, files: files(6) + files(2), isAlreadyInHistory: true)
    XCTAssertEqual(dispatcher.pendingCount(for: id), 3)
    while !gates.isEmpty { await releaseOne() }
  }

  func testBreakerPausesFastAutomationAndResumeLiftsIt() async {
    var pausedIDs: [UUID] = []
    let dispatcher = makeDispatcher(burstLimit: 3)
    dispatcher.onBurstPaused = { pausedIDs.append($0) }
    let id = UUID()
    dispatcher.enqueue(id, invocation: .folderWatch, files: files(5), isAlreadyInHistory: true)
    await settle()
    XCTAssertEqual(launches.count, 3)
    XCTAssertEqual(pausedIDs, [id])
    XCTAssertTrue(dispatcher.pausedAutomationIDs.contains(id))
    XCTAssertEqual(dispatcher.pendingCount(for: id), 0)

    dispatcher.enqueue(id, invocation: .folderWatch, files: files(1), isAlreadyInHistory: true)
    await settle()
    XCTAssertEqual(launches.count, 3, "Paused automations ignore new events")

    dispatcher.resume(id)
    dispatcher.enqueue(id, invocation: .folderWatch, files: files(1), isAlreadyInHistory: true)
    await settle()
    XCTAssertEqual(launches.count, 4)
  }

  func testBreakerWindowSlides() async {
    let dispatcher = makeDispatcher(burstLimit: 2)
    let id = UUID()
    dispatcher.enqueue(id, invocation: .clipboardChange, files: files(2), isAlreadyInHistory: false)
    await settle()
    clock = clock.addingTimeInterval(61)
    dispatcher.enqueue(id, invocation: .clipboardChange, files: [URL(fileURLWithPath: "/tmp/later.png")], isAlreadyInHistory: false)
    await settle()
    XCTAssertEqual(launches.count, 3)
    XCTAssertTrue(dispatcher.pausedAutomationIDs.isEmpty)
  }

  func testAutomationLevelRejectionDropsTheQueue() async {
    nextOutcome = .rejected(.eventCodeNotAllowed)
    let dispatcher = makeDispatcher(maxConcurrent: 1)
    let id = UUID()
    dispatcher.enqueue(id, invocation: .folderWatch, files: files(4), isAlreadyInHistory: true)
    await settle()
    XCTAssertEqual(launches.count, 1, "Nothing else can run, so the rest is dropped")
    XCTAssertTrue(dispatcher.isIdle)
  }

  func testPerFileRejectionKeepsGoing() async {
    nextOutcome = .rejected(.fileMissing("x.png"))
    let dispatcher = makeDispatcher(maxConcurrent: 1)
    dispatcher.enqueue(UUID(), invocation: .folderWatch, files: files(3), isAlreadyInHistory: true)
    await settle()
    XCTAssertEqual(launches.count, 3)
  }
}

// MARK: - Folder watcher

nonisolated final class AutomationFolderWatcherTests: XCTestCase, @unchecked Sendable {
  private var folder: URL!
  private let lock = NSLock()
  private var fired: [[URL]] = []
  private var clock = Date(timeIntervalSince1970: 1000)

  override func setUpWithError() throws {
    try super.setUpWithError()
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("FolderWatcherTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
    try super.tearDownWithError()
  }

  private func makeWatcher(ownFiles: Set<String> = []) -> AutomationFolderWatcher {
    AutomationFolderWatcher(
      folder: folder,
      // Long coalesce: the dispatch source never scans on its own during a test.
      timing: .init(coalesce: 3600, stability: 0.5, maxSettle: 10),
      now: { [unowned self] in lock.withLock { clock } },
      isOwnFile: { ownFiles.contains($0.lastPathComponent) },
      onNewFiles: { [unowned self] urls in lock.withLock { fired.append(urls) } }
    )
  }

  private func advance(_ seconds: TimeInterval) {
    lock.withLock { clock = clock.addingTimeInterval(seconds) }
  }

  private var firedNames: [String] {
    lock.withLock { fired.flatMap { $0.map(\.lastPathComponent) } }
  }

  private func write(_ name: String, bytes: Int = 4) throws {
    try Data(repeating: 1, count: bytes).write(to: folder.appendingPathComponent(name))
  }

  func testExistingFilesNeverFireNewOnesFireOnceSettled() throws {
    try write("old.png")
    let watcher = makeWatcher()
    XCTAssertTrue(watcher.start())
    defer { watcher.stop() }
    watcher.scanNow() // waits for the baseline, which runs on the watcher queue

    try write("new.png")
    watcher.scanNow()
    XCTAssertEqual(firedNames, [], "First sighting only records the size")
    advance(0.2)
    watcher.scanNow()
    XCTAssertEqual(firedNames, [], "Not stable for long enough yet")
    advance(0.5)
    watcher.scanNow()
    XCTAssertEqual(firedNames, ["new.png"])
    advance(5)
    watcher.scanNow()
    XCTAssertEqual(firedNames, ["new.png"], "Fires once")
  }

  func testGrowingFileWaitsUntilItStops() throws {
    let watcher = makeWatcher()
    XCTAssertTrue(watcher.start())
    defer { watcher.stop() }
    watcher.scanNow() // waits for the baseline, which runs on the watcher queue

    try write("download.mov", bytes: 10)
    watcher.scanNow()
    advance(1)
    try write("download.mov", bytes: 20)
    watcher.scanNow()
    XCTAssertEqual(firedNames, [], "Size changed: wait again")
    advance(1)
    watcher.scanNow()
    XCTAssertEqual(firedNames, ["download.mov"])
  }

  func testSkipsHiddenUnsupportedEmptyAndOwnFiles() throws {
    let watcher = makeWatcher(ownFiles: ["mine.png"])
    XCTAssertTrue(watcher.start())
    defer { watcher.stop() }
    watcher.scanNow() // waits for the baseline, which runs on the watcher queue

    try write(".hidden.png")
    try write("notes.txt")
    try write("mine.png")
    try write("empty.png", bytes: 0)
    try write("theirs.gif")
    watcher.scanNow()
    advance(1)
    watcher.scanNow()
    XCTAssertEqual(firedNames, ["theirs.gif"])
  }

  func testDeletedAndReaddedFileFiresAgain() throws {
    let watcher = makeWatcher()
    XCTAssertTrue(watcher.start())
    defer { watcher.stop() }
    watcher.scanNow() // waits for the baseline, which runs on the watcher queue

    try write("a.png")
    watcher.scanNow(); advance(1); watcher.scanNow()
    try FileManager.default.removeItem(at: folder.appendingPathComponent("a.png"))
    watcher.scanNow()
    try write("a.png")
    watcher.scanNow(); advance(1); watcher.scanNow()
    XCTAssertEqual(firedNames, ["a.png", "a.png"])
  }

  func testFileThatNeverSettlesIsGivenUp() throws {
    let watcher = makeWatcher()
    XCTAssertTrue(watcher.start())
    defer { watcher.stop() }
    watcher.scanNow() // waits for the baseline, which runs on the watcher queue

    for size in 1 ... 12 {
      try write("stuck.mp4", bytes: size)
      watcher.scanNow()
      advance(1)
    }
    watcher.scanNow()
    advance(1)
    watcher.scanNow()
    XCTAssertEqual(firedNames, [], "Given up after maxSettle; never fires late")
  }

  func testMissingFolderDoesNotStart() {
    let watcher = AutomationFolderWatcher(folder: folder.appendingPathComponent("nope"), onNewFiles: { _ in })
    XCTAssertFalse(watcher.start())
  }

  func testOriginTrackerMatchesThroughSymlinkedFolderBeforeTheFileExists() throws {
    let real = folder.appendingPathComponent("real")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    let link = folder.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    let tracker = AutomationFileOriginTracker()
    // Save to Folder marks the destination before it is written.
    tracker.markWritten([link.appendingPathComponent("saved.png")])
    try write("real/saved.png")
    XCTAssertTrue(tracker.wasWrittenBySnapzy(real.appendingPathComponent("saved.png")))
  }

  func testEmptyFileIsGivenUpQuickly() throws {
    let watcher = AutomationFolderWatcher(
      folder: folder,
      timing: .init(coalesce: 3600, stability: 0.5, maxSettle: 600, maxEmpty: 5),
      now: { [unowned self] in lock.withLock { clock } },
      isOwnFile: { _ in false },
      onNewFiles: { [unowned self] urls in lock.withLock { fired.append(urls) } }
    )
    XCTAssertTrue(watcher.start())
    defer { watcher.stop() }
    watcher.scanNow() // waits for the baseline, which runs on the watcher queue
    try write("placeholder.png", bytes: 0)
    watcher.scanNow()
    advance(6)
    watcher.scanNow()
    try write("placeholder.png", bytes: 8)
    advance(1)
    watcher.scanNow()
    advance(1)
    watcher.scanNow()
    XCTAssertEqual(firedNames, [], "Given up while empty; filled in later it is an old file")
  }

  func testOriginTrackerForgetsAfterMemory() {
    var now = Date(timeIntervalSince1970: 0)
    let lock = NSLock()
    let tracker = AutomationFileOriginTracker(memory: 10, now: { lock.withLock { now } })
    let url = folder.appendingPathComponent("x.png")
    tracker.markWritten([url])
    XCTAssertTrue(tracker.wasWrittenBySnapzy(url))
    lock.withLock { now = now.addingTimeInterval(11) }
    XCTAssertFalse(tracker.wasWrittenBySnapzy(url))
  }
}

// MARK: - Clipboard watcher

@MainActor
private final class FakePasteboard: AutomationPasteboardReading {
  var changeCount = 0
  var types: [NSPasteboard.PasteboardType]?
  var files: [URL] = []
  func fileURLs() -> [URL] { files }
}

@MainActor
final class AutomationClipboardWatcherTests: XCTestCase {
  private var pasteboard: FakePasteboard!
  private var ownCount: Int?
  private var frontmost = false
  private var fired: [Int] = []
  private var watcher: AutomationClipboardWatcher!

  override func setUp() {
    super.setUp()
    pasteboard = FakePasteboard()
    ownCount = nil
    frontmost = false
    fired = []
    watcher = AutomationClipboardWatcher(
      pasteboard: pasteboard,
      isOwnWrite: { [unowned self] in $0 == ownCount },
      isSnapzyFrontmost: { [unowned self] in frontmost },
      isSnapzyFile: { $0.path.hasPrefix("/snapzy/") },
      onImageCopied: { [unowned self] in fired.append($0) }
    )
  }

  private func copy(_ types: [NSPasteboard.PasteboardType], files: [URL] = []) {
    pasteboard.changeCount += 1
    pasteboard.types = types
    pasteboard.files = files
    watcher.poll()
  }

  func testImageDataFiresOncePerChange() {
    copy([.png])
    watcher.poll()
    XCTAssertEqual(fired, [1])
  }

  func testTextAndPrivateContentIgnored() {
    copy([.string])
    copy([.tiff, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")])
    copy([.png, NSPasteboard.PasteboardType("org.nspasteboard.TransientType")])
    XCTAssertEqual(fired, [])
  }

  func testSnapzyWritesIgnored() {
    ownCount = 1
    copy([.png])
    frontmost = true
    copy([.png])
    frontmost = false
    copy([.fileURL, .tiff], files: [URL(fileURLWithPath: "/snapzy/cap.png")])
    XCTAssertEqual(fired, [])
  }

  func testFinderCopiesOnlyCountForImageFiles() {
    copy([.fileURL, .tiff], files: [URL(fileURLWithPath: "/Users/me/report.pdf")])
    XCTAssertEqual(fired, [], "A document's icon is not a copied image")
    copy([.fileURL, .tiff], files: [URL(fileURLWithPath: "/Users/me/photo.jpg")])
    XCTAssertEqual(fired, [2])
  }

  func testWhatIsOnTheClipboardAtStartNeverFires() {
    pasteboard.changeCount = 7
    pasteboard.types = [.png]
    watcher.start(interval: 3600)
    defer { watcher.stop() }
    watcher.poll()
    XCTAssertEqual(fired, [])
    XCTAssertTrue(watcher.isRunning)
  }
}

// MARK: - Launcher gate and monitor

@MainActor
final class AutomationEventLaunchTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!
  private var store: AutomationStore!
  private var environment: FakeAutomationEnvironment!
  private var launcher: AutomationLauncher!
  private var directory: URL!
  private var image: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    suiteName = "AutomationEventLaunchTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.set(true, forKey: PreferencesKeys.automationsSeeded)
    store = AutomationStore(defaults: defaults)
    environment = FakeAutomationEnvironment()
    launcher = AutomationLauncher(
      store: store,
      runner: AutomationRunner(environment: environment),
      isURLSchemeEnabled: { true },
      allowsCodeSteps: { true }
    )
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutomationEventLaunchTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    image = directory.appendingPathComponent("shot.png")
    try AutomationTestImages.png(width: 20, height: 20).write(to: image)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    defaults.removePersistentDomain(forName: suiteName)
    try super.tearDownWithError()
  }

  private func rejection(_ outcome: AutomationLaunchOutcome) -> AutomationLaunchRejection? {
    if case .rejected(let rejection) = outcome { return rejection }
    return nil
  }

  func testForeignContentNeverReachesScripts() async {
    let automation = Automation(
      name: "Script",
      source: .input,
      steps: [AutomationStep(.copyImage), AutomationStep(.runScript(AutomationRunScriptConfig(script: "echo hi")))]
    )
    store.add(automation)
    let input = AutomationInput(files: [image], isAlreadyInHistory: true)

    for invocation in [AutomationInvocation.folderWatch, .clipboardChange] {
      let outcome = await launcher.launch(.id(automation.id), invocation: invocation, input: input)
      XCTAssertEqual(rejection(outcome), .eventCodeNotAllowed, "\(invocation)")
    }
    XCTAssertTrue(environment.processRequests.isEmpty)

    let fromCapture = await launcher.launch(.id(automation.id), invocation: .captureSaved, input: input)
    XCTAssertNil(rejection(fromCapture), "A Snapzy capture is the user's own content")
  }

  func testEventRunsNeedNoExternalOptIn() async {
    let automation = Automation(name: "Copy", source: .input, steps: [AutomationStep(.copyImage)])
    store.add(automation)
    let outcome = await launcher.launch(
      .id(automation.id),
      invocation: .folderWatch,
      input: AutomationInput(files: [image], isAlreadyInHistory: true)
    )
    XCTAssertNil(rejection(outcome))
  }

  // MARK: Monitor

  private func makeMonitor(folders: AutomationFolderAccessStore? = nil) -> AutomationEventMonitor {
    AutomationEventMonitor(
      store: store,
      folders: folders ?? AutomationFolderAccessStore(defaults: defaults, exportDirectory: { nil }),
      defaults: defaults,
      dispatcher: AutomationEventDispatcher(launch: { _, _, _ in .cancelled }),
      makeClipboardWatcher: { AutomationClipboardWatcher(pasteboard: FakePasteboard(), onImageCopied: $0) }
    )
  }

  func testNoEventTriggersMeansNoWatchers() {
    store.add(Automation(name: "Plain", source: .input, steps: [AutomationStep(.copyImage)]))
    let monitor = makeMonitor()
    monitor.reconcile()
    XCTAssertFalse(monitor.isWatchingClipboard)
    XCTAssertTrue(monitor.activeFolderPaths.isEmpty)
  }

  func testWatchersFollowTheStoreAndThePauseSwitch() {
    let folders = AutomationFolderAccessStore(defaults: defaults, exportDirectory: { nil })
    let ref = AutomationFolderRef.bookmark(folders.register(directory))
    var automation = Automation(name: "Watch", source: .input, steps: [AutomationStep(.copyImage)])
    automation.runsOnClipboardChange = true
    automation.folderWatch = AutomationFolderWatchConfig(folder: ref, folderPath: directory.path)
    store.add(automation)

    let monitor = makeMonitor(folders: folders)
    monitor.reconcile()
    XCTAssertTrue(monitor.isWatchingClipboard)
    XCTAssertEqual(monitor.activeFolderPaths, [directory.standardizedFileURL.resolvingSymlinksInPath().path])

    defaults.set(true, forKey: PreferencesKeys.automationsEventTriggersPaused)
    monitor.reconcile()
    XCTAssertFalse(monitor.isWatchingClipboard)
    XCTAssertTrue(monitor.activeFolderPaths.isEmpty)

    defaults.set(false, forKey: PreferencesKeys.automationsEventTriggersPaused)
    var disabled = store.automation(id: automation.id)!
    disabled.isEnabled = false
    store.update(disabled)
    monitor.reconcile()
    XCTAssertFalse(monitor.isWatchingClipboard, "Disabled automations watch nothing")
    XCTAssertTrue(monitor.activeFolderPaths.isEmpty)
  }

  func testClipboardIsNotWatchedForAutomationsWithScripts() {
    var automation = Automation(
      name: "Script",
      source: .input,
      steps: [AutomationStep(.copyImage), AutomationStep(.runScript(AutomationRunScriptConfig(script: "echo hi")))]
    )
    automation.runsOnClipboardChange = true
    store.add(automation)
    let monitor = makeMonitor()
    monitor.reconcile()
    XCTAssertFalse(monitor.isWatchingClipboard, "The launcher would refuse every run; don't read the clipboard for it")
  }

  func testCaptureSavedMatchesKindAndAcceptedFiles() async {
    var launched: [(UUID, AutomationInvocation)] = []
    let dispatcher = AutomationEventDispatcher(launch: { id, invocation, _ in
      launched.append((id, invocation))
      return .cancelled
    })
    var screenshots = Automation(name: "Shots", source: .input, steps: [AutomationStep(.copyImage)])
    screenshots.captureEvent = AutomationCaptureEventConfig(kinds: [.screenshot])
    var recordings = Automation(name: "Recs", source: .input, steps: [AutomationStep(.copyImage)])
    recordings.captureEvent = AutomationCaptureEventConfig(kinds: [.recording])
    store.add(screenshots)
    store.add(recordings)

    let monitor = AutomationEventMonitor(
      store: store,
      folders: AutomationFolderAccessStore(defaults: defaults, exportDirectory: { nil }),
      defaults: defaults,
      dispatcher: dispatcher,
      makeClipboardWatcher: { AutomationClipboardWatcher(pasteboard: FakePasteboard(), onImageCopied: $0) }
    )
    monitor.captureSaved(type: .screenshot, urls: [image])
    for _ in 0 ..< 20 { await Task.yield() }
    XCTAssertEqual(launched.map(\.0), [screenshots.id])
    XCTAssertEqual(launched.first?.1, .captureSaved)
  }
}
