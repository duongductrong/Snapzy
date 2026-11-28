//
//  VideoEditorSnapzyProjectPackageTests.swift
//  SnapzyTests
//
//  Real-world end-to-end and hostile-input regression tests for the `.snapzy` project
//  package format (`SnapzyProjectPackage`, `VideoEditorWindowController`, `Info.plist`):
//  1. Off-main-thread async save & load (`saveAsync` / `loadAsync`) round-tripping
//     primary/secondary video, wallpaper, zooms, speeds, captions, and RecordingMetadata
//     after deleting all original source files.
//  2. Font licensing safety: font binaries are NEVER copied into `.snapzy` packages or
//     auto-installed on load; missing fonts record their display name reference only.
//  3. Hostile `.snapzy` input: duplicate IDs strictly rejected across all persisted
//     arrays (`clips`, `zoomSegments`, `speedSegments`, `audioClips`, `captions.segments`,
//     `textOverlays`, `cameraSettings.hiddenRanges`, `recordingMetadata.audioSourceTracks`),
//     out-of-range numbers clamped, and oversized `> 8 MB` manifests / metadata rejected.
//  4. Restore-failure data-loss protection: mismatched media duration sets
//     `sessionRestoreFailed`, triggers the visible alert flag, and blocks in-place
//     `Save` (`⌘S`) from overwriting the original `.snapzy` package while allowing
//     `Save Project As` to a separate path.
//  5. Atomic overwrite, move/rename URL rebinding + export, path-traversal & symlink
//     escape rejection, `Info.plist` UTI / GIF-on-Image verification, and off-main
//     auto-recovery draft persistence.
//

import AppKit
import AVFoundation
import CoreMedia
@testable import Snapzy
import SwiftUI
import XCTest

@MainActor
final class VideoEditorSnapzyProjectPackageTests: XCTestCase {
  private var tempDir: URL!

  override func setUpWithError() throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyProjectPkgTests_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    VideoEditorManager.shared.closeAll()
    if let tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  // MARK: - 1. Async Off-Main Round-Trip & Zero Commercial Font Binary Redistribution

  func testSnapzyPackage_asyncRoundTripAndNoImportedFontRedistributionOrAutoInstall() async throws {
    let sourcesDir = tempDir.appendingPathComponent("OriginalSources", isDirectory: true)
    try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

    let primaryVideoURL = try await makeTestMovie(
      in: sourcesDir,
      name: "primary_capture.mov",
      durationSeconds: 4.0,
      width: 640,
      height: 360
    )
    let secondaryClipURL = try await makeTestMovie(
      in: sourcesDir,
      name: "inserted_broll.mov",
      durationSeconds: 2.0,
      width: 640,
      height: 360
    )
    let customBgURL = try makeTestPNG(in: sourcesDir, name: "studio_wallpaper.png")

    // Register a referenced custom font display name (simulating a commercial font reference)
    let referencedFontId = "custom-commercial-\(UUID().uuidString.prefix(8))"
    let referencedFontName = "Commercial Sans Pro"
    SnapzyProjectPackage.registerReferencedFontNames([referencedFontId: referencedFontName])

    let state = VideoEditorState(url: primaryVideoURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    XCTAssertNotNil(state.splitClip(atTimeline: 2.0))
    let insertedClipId = await state.insertClip(url: secondaryClipURL)
    XCTAssertNotNil(insertedClipId)
    XCTAssertEqual(state.clips.count, 3)

    _ = state.addZoom(at: 0.4)
    _ = state.addSpeed(range: 2.1 ... 3.3, rate: 2.0)
    state.backgroundStyle = .blurred(customBgURL)
    state.backgroundPadding = 36
    state.backgroundShadowIntensity = 0.55
    state.backgroundCornerRadius = 18

    state.applyCaptions(VideoEditorCaptions(
      segments: [CaptionSegment(sourceRange: 0.3 ... 2.6, text: "Self-contained Snapzy package test")],
      settings: .default
    ))
    state.seek(to: CMTime(seconds: 1.75, preferredTimescale: 600))

    // Save asynchronously off MainActor!
    let packageURL = tempDir.appendingPathComponent("CompleteProject.snapzy", isDirectory: true)
    let savedProject = try await SnapzyProjectPackage.saveAsync(state: state, to: packageURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("manifest.json").path))

    // Section 2a.4: Commercial/user-imported font binaries MUST NOT be copied into `.snapzy`!
    let fontsSubdir = packageURL.appendingPathComponent("Fonts", isDirectory: true)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: fontsSubdir.path),
      "User-imported font binaries must never be redistributed inside .snapzy packages"
    )
    XCTAssertEqual(savedProject.manifest.referencedFontDisplayNames?[referencedFontId], referencedFontName)

    // Delete all original sources so the restored project relies 100% on internal `Media/`
    try FileManager.default.removeItem(at: sourcesDir)

    // Load asynchronously off MainActor!
    let loadedProject = try await SnapzyProjectPackage.loadAsync(from: packageURL)
    XCTAssertEqual(loadedProject.playheadSeconds, 1.75, accuracy: 0.05)
    XCTAssertEqual(SnapzyProjectPackage.referencedFontDisplayName(for: referencedFontId), referencedFontName)

    let restoredState = VideoEditorState(
      url: loadedProject.sessionData.sourceSnapshotURL,
      originalURL: packageURL,
      sessionData: loadedProject.sessionData
    )
    defer { restoredState.cancelPendingPerformanceWork() }
    await restoredState.loadMetadata()

    XCTAssertFalse(restoredState.sessionRestoreFailed)
    XCTAssertFalse(restoredState.hasUnsavedChanges)
    XCTAssertEqual(restoredState.clips.count, 3)
    XCTAssertEqual(restoredState.zoomSegments.count, 1)
    XCTAssertEqual(restoredState.speedSegments.count, 1)
    XCTAssertEqual(restoredState.captions.segments.count, 1)
    XCTAssertEqual(restoredState.backgroundPadding, 36, accuracy: 0.01)

    // Exporting restored project after deleting all original sources succeeds!
    let exportedMP4 = tempDir.appendingPathComponent("restored_package_export.mp4")
    try await VideoEditorExporter.exportTrimmed(state: restoredState, to: exportedMP4) { _ in }
    XCTAssertTrue(FileManager.default.fileExists(atPath: exportedMP4.path))
  }

  // MARK: - 2. Hostile `.snapzy` Input: Duplicate IDs Rejected Across All Arrays & Numbers Clamped

  func testSnapzyPackage_rejectsDuplicateIDsAcrossAllArraysAndClampsExtremeNumbers() async throws {
    let videoURL = try await makeTestMovie(
      in: tempDir,
      name: "hostile_pkg_base.mov",
      durationSeconds: 4.0,
      width: 320,
      height: 180
    )
    let state = VideoEditorState(url: videoURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    _ = state.addZoom(at: 0.4)
    _ = state.addSpeed(range: 0.5 ... 1.5, rate: 2.0)
    state.applyCaptions(VideoEditorCaptions(
      segments: [CaptionSegment(sourceRange: 0.2 ... 1.2, text: "Cue 1")],
      settings: .default
    ))

    var baseSession = VideoEditorSessionData.snapshot(from: state, sourceSnapshotURL: videoURL)
    baseSession.recordingMetadata = RecordingMetadata(
      captureSize: CGSize(width: 320, height: 180),
      samplesPerSecond: 60,
      mouseSamples: [],
      audioSourceTrackRoles: [.systemAudio],
      audioSourceTracks: [RecordingAudioSourceTrack(trackID: 1, role: .systemAudio)]
    )

    let basePkgURL = tempDir.appendingPathComponent("HostileBase.snapzy", isDirectory: true)
    _ = try SnapzyProjectPackage.save(sessionData: baseSession, to: basePkgURL)
    let manifestURL = basePkgURL.appendingPathComponent("manifest.json")
    let cleanManifestData = try Data(contentsOf: manifestURL)

    // Verify duplicate IDs in each of the 7 `editState` arrays strictly throw `.manifestCorrupted`
    let arrayKeys = [
      "clips", "zoomSegments", "speedSegments", "audioClips",
      "textOverlays", "captions.segments", "cameraSettings.hiddenRanges",
    ]
    let dupUUID = "99999999-8888-7777-6666-555555555555"

    for key in arrayKeys {
      var root = try XCTUnwrap(JSONSerialization.jsonObject(with: cleanManifestData) as? [String: Any])
      var editState = try XCTUnwrap(root["editState"] as? [String: Any])
      if key == "captions.segments" {
        var captions = try XCTUnwrap(editState["captions"] as? [String: Any])
        var segs = try XCTUnwrap(captions["segments"] as? [[String: Any]])
        var first = try XCTUnwrap(segs.first)
        first["id"] = dupUUID
        segs = [first, first]
        captions["segments"] = segs
        editState["captions"] = captions
      } else if key == "cameraSettings.hiddenRanges" {
        let rangeItem: [String: Any] = ["id": dupUUID, "start": 0.2, "end": 1.0]
        var cam = (editState["cameraSettings"] as? [String: Any]) ?? [:]
        cam["hiddenRanges"] = [rangeItem, rangeItem]
        editState["cameraSettings"] = cam
      } else if key == "audioClips" || key == "textOverlays" {
        let syntheticItem: [String: Any] = ["id": dupUUID]
        editState[key] = [syntheticItem, syntheticItem]
      } else {
        var arr = try XCTUnwrap(editState[key] as? [[String: Any]])
        var first = try XCTUnwrap(arr.first)
        first["id"] = dupUUID
        arr = [first, first]
        editState[key] = arr
      }
      root["editState"] = editState
      try JSONSerialization.data(withJSONObject: root).write(to: manifestURL, options: .atomic)

      XCTAssertThrowsError(
        try SnapzyProjectPackage.load(from: basePkgURL),
        "Duplicate ID in \(key) must be rejected on .snapzy load"
      ) { err in
        guard case SnapzyProjectPackageError.manifestCorrupted(let msg) = err else {
          XCTFail("Expected manifestCorrupted for \(key), got \(err)")
          return
        }
        XCTAssertTrue(msg.contains("Duplicate ID"))
      }
    }

    // Restore clean manifest, then inject duplicate trackID/role into `Media/recording-metadata.json`
    // (`audioSourceTracks`)
    try cleanManifestData.write(to: manifestURL, options: .atomic)
    let recMetaURL = basePkgURL.appendingPathComponent("Media/recording-metadata.json")
    let cleanRecMetaData = try Data(contentsOf: recMetaURL)
    var recRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: cleanRecMetaData) as? [String: Any])
    let tracks = try XCTUnwrap(recRoot["audioSourceTracks"] as? [[String: Any]])
    let firstTrack = try XCTUnwrap(tracks.first)
    recRoot["audioSourceTracks"] = [firstTrack, firstTrack]
    try JSONSerialization.data(withJSONObject: recRoot).write(to: recMetaURL, options: .atomic)
    XCTAssertThrowsError(
      try SnapzyProjectPackage.load(from: basePkgURL),
      "Duplicate audioSourceTracks must be rejected"
    )
    try cleanRecMetaData.write(to: recMetaURL, options: .atomic)

    // Inject unique IDs with extreme out-of-range numbers -> must load cleanly with clamped values!
    var extremeRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: cleanManifestData) as? [String: Any])
    extremeRoot["playheadSeconds"] = 999_999_999.0
    var extremeEdit = try XCTUnwrap(extremeRoot["editState"] as? [String: Any])
    extremeEdit["backgroundPadding"] = 99_999.0
    extremeEdit["backgroundShadowIntensity"] = -20.0
    extremeEdit["backgroundCornerRadius"] = 50_000.0
    if var clipsArr = extremeEdit["clips"] as? [[String: Any]], !clipsArr.isEmpty {
      clipsArr[0]["sourceDuration"] = 999_999_999.0
      clipsArr[0]["sourceStart"] = -100.0
      extremeEdit["clips"] = clipsArr
    }
    extremeRoot["editState"] = extremeEdit
    try JSONSerialization.data(withJSONObject: extremeRoot).write(to: manifestURL, options: .atomic)

    let clampedProject = try SnapzyProjectPackage.load(from: basePkgURL)
    XCTAssertEqual(clampedProject.playheadSeconds, SnapzyProjectManifest.maxPlayheadSeconds, accuracy: 0.01)
    XCTAssertEqual(clampedProject.sessionData.backgroundPadding, 500, accuracy: 0.01)
    XCTAssertEqual(clampedProject.sessionData.backgroundShadowIntensity, 0, accuracy: 0.01)
    XCTAssertEqual(clampedProject.sessionData.backgroundCornerRadius, 500, accuracy: 0.01)
    let clampedClip = try XCTUnwrap(clampedProject.sessionData.clips.first)
    XCTAssertEqual(clampedClip.sourceDuration, TimelineClip.maxDurationSeconds, accuracy: 0.01)
    XCTAssertEqual(clampedClip.sourceStart, 0, accuracy: 0.01)
  }

  // MARK: - 3. Security: Oversized `> 8 MB` Manifest & Recording Metadata Rejected

  func testSnapzyPackage_rejectsOversizedManifestAndOversizedRecordingMetadata() async throws {
    let videoURL = try await makeTestMovie(
      in: tempDir,
      name: "oversized_pkg.mov",
      durationSeconds: 2.0,
      width: 320,
      height: 180
    )
    let state = VideoEditorState(url: videoURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()
    var sessionWithMeta = VideoEditorSessionData.snapshot(from: state, sourceSnapshotURL: videoURL)
    sessionWithMeta.recordingMetadata = RecordingMetadata(
      captureSize: CGSize(width: 320, height: 180),
      samplesPerSecond: 60,
      mouseSamples: []
    )

    let pkgURL = tempDir.appendingPathComponent("OversizedCheck.snapzy", isDirectory: true)
    _ = try SnapzyProjectPackage.save(sessionData: sessionWithMeta, to: pkgURL)

    let manifestURL = pkgURL.appendingPathComponent("manifest.json")
    let cleanManifest = try Data(contentsOf: manifestURL)
    let oversized = Data(repeating: 0x20, count: SnapzyProjectPackage.maxManifestBytes + 2048)

    // 1) Oversized `manifest.json`
    try oversized.write(to: manifestURL, options: .atomic)
    XCTAssertThrowsError(try SnapzyProjectPackage.load(from: pkgURL)) { err in
      XCTAssertEqual(err as? SnapzyProjectPackageError, .manifestTooLarge(SnapzyProjectPackage.maxManifestBytes))
    }

    // 2) Valid `manifest.json` + oversized `Media/recording-metadata.json`
    try cleanManifest.write(to: manifestURL, options: .atomic)
    let recMetaURL = pkgURL.appendingPathComponent("Media/recording-metadata.json")
    try oversized.write(to: recMetaURL, options: .atomic)
    XCTAssertThrowsError(try SnapzyProjectPackage.load(from: pkgURL)) { err in
      XCTAssertEqual(err as? SnapzyProjectPackageError, .manifestTooLarge(SnapzyProjectPackage.maxMetadataBytes))
    }
  }

  // MARK: - 4. Restore-Failure Data-Loss Protection (Visible Alert Flag + In-Place Save Blocked)

  func testSnapzyPackage_sessionRestoreFailureBlocksInPlaceOverwriteAndPreservesOriginalPackage() async throws {
    let fullVideoURL = try await makeTestMovie(
      in: tempDir,
      name: "full_4s.mov",
      durationSeconds: 4.0,
      width: 320,
      height: 180
    )
    let shortVideoURL = try await makeTestMovie(
      in: tempDir,
      name: "truncated_1s.mov",
      durationSeconds: 1.0,
      width: 320,
      height: 180
    )

    // Author a 2-clip project on the 4.0s source and save `Original.snapzy`
    let authorState = VideoEditorState(url: fullVideoURL)
    defer { authorState.cancelPendingPerformanceWork() }
    await authorState.loadMetadata()
    XCTAssertNotNil(authorState.splitClip(atTimeline: 2.0))
    XCTAssertEqual(authorState.clips.count, 2)

    let pkgURL = tempDir.appendingPathComponent("Original.snapzy", isDirectory: true)
    _ = try SnapzyProjectPackage.save(state: authorState, to: pkgURL)
    let originalManifestBefore = try Data(contentsOf: pkgURL.appendingPathComponent("manifest.json"))

    // Replace `Media/primary.mov` with the 1.0s video so clip [2.0...4.0s] fails `restoreSessionIfNeeded`!
    let internalPrimaryURL = pkgURL.appendingPathComponent("Media/primary.mov")
    try FileManager.default.removeItem(at: internalPrimaryURL)
    try FileManager.default.copyItem(at: shortVideoURL, to: internalPrimaryURL)

    let loaded = try SnapzyProjectPackage.load(from: pkgURL)
    let controller = VideoEditorWindowController(project: loaded)
    defer { controller.window?.close() }
    let editorState = try XCTUnwrap(controller.editorState)
    await editorState.loadMetadata()
    controller.handleMetadataLoaded()

    // 1) Restore failure must be flagged visibly and lock in-place overwrite!
    XCTAssertTrue(editorState.sessionRestoreFailed, "Mismatched primary media duration must flag sessionRestoreFailed")
    XCTAssertTrue(controller.didPresentRestoreFailureAlert)
    XCTAssertFalse(controller.canOverwriteProjectInPlace)

    // 2) Attempting in-place Save onto `Original.snapzy` MUST throw `.restoreFailedSaveBlocked` and leave manifest
    // untouched!
    XCTAssertThrowsError(try controller.performSaveProjectPackageSync(to: pkgURL)) { err in
      XCTAssertEqual(err as? SnapzyProjectPackageError, .restoreFailedSaveBlocked)
    }
    let manifestAfterBlockedSave = try Data(contentsOf: pkgURL.appendingPathComponent("manifest.json"))
    XCTAssertEqual(
      manifestAfterBlockedSave,
      originalManifestBefore,
      "Blocked in-place Save must never overwrite or mutate the original .snapzy manifest"
    )

    // 3) Saving to a DIFFERENT destination (`Save Project As`) succeeds cleanly!
    let recoveredCopyURL = tempDir.appendingPathComponent("Original-copy.snapzy", isDirectory: true)
    let savedCopy = try controller.performSaveProjectPackageSync(to: recoveredCopyURL)
    XCTAssertEqual(savedCopy.packageURL.standardizedFileURL, recoveredCopyURL.standardizedFileURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: recoveredCopyURL.appendingPathComponent("manifest.json").path))
  }

  // MARK: - 5. Atomic Overwrite, Move/Rebind, Path Security, Info.plist & Off-Main Auto-Recovery

  func testSnapzyPackage_atomicOverwriteMoveRebindPathSecurityInfoPlistAndOffMainAutoRecovery() async throws {
    // Verify Info.plist declares `.snapzy` UTI, keeps `.gif` under Image, and does NOT set `ATSApplicationFontsPath`
    let repoInfoPlistURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Snapzy/Resources/Info.plist")
    let plistDict = try XCTUnwrap(NSDictionary(contentsOf: repoInfoPlistURL) as? [String: Any])
    XCTAssertNil(plistDict["ATSApplicationFontsPath"], "Info.plist must not bundle app-wide fonts")
    let docTypes = try XCTUnwrap(plistDict["CFBundleDocumentTypes"] as? [[String: Any]])
    XCTAssertTrue(docTypes.contains { ($0["CFBundleTypeName"] as? String) == "Snapzy Project" })
    let imageDocType = try XCTUnwrap(docTypes.first { ($0["CFBundleTypeName"] as? String) == "Image" })
    let imageUTIs = try XCTUnwrap(imageDocType["LSItemContentTypes"] as? [String])
    XCTAssertTrue(imageUTIs.contains("com.compuserve.gif"), "GIF must remain registered under Image for Annotate")

    let primaryURL = try await makeTestMovie(
      in: tempDir,
      name: "move_primary.mov",
      durationSeconds: 2.0,
      width: 320,
      height: 180
    )
    let secondaryURL = try await makeTestMovie(
      in: tempDir,
      name: "move_secondary.mov",
      durationSeconds: 1.5,
      width: 320,
      height: 180
    )
    let bgURL = try makeTestPNG(in: tempDir, name: "move_bg.png")

    let state = VideoEditorState(url: primaryURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()
    _ = await state.insertClip(url: secondaryURL)
    state.backgroundStyle = .wallpaper(bgURL)

    // Verify off-main auto-recovery draft persistence (`persistDraftOffMain`)
    let storeRoot = tempDir.appendingPathComponent("AutoRecoveryStore", isDirectory: true)
    let isolatedStore = VideoEditorSessionStore(rootDirectory: storeRoot)
    let draftSnapshot = VideoEditorSessionData.snapshot(from: state, sourceSnapshotURL: state.editingSourceURL)
    let persistedDraft = await isolatedStore.persistDraftOffMain(
      snapshot: draftSnapshot,
      existingSourceSnapshotURL: nil,
      for: primaryURL
    )
    XCTAssertNotNil(persistedDraft)
    XCTAssertNotNil(isolatedStore.load(for: primaryURL))

    // Save ProjectA.snapzy, delete original files, move to ProjectB.snapzy, rebind, export, and atomic re-save!
    let pkgA = tempDir.appendingPathComponent("ProjectA.snapzy", isDirectory: true)
    _ = try SnapzyProjectPackage.save(state: state, to: pkgA)
    try FileManager.default.removeItem(at: primaryURL)
    try FileManager.default.removeItem(at: secondaryURL)
    try FileManager.default.removeItem(at: bgURL)

    let loadedA = try SnapzyProjectPackage.load(from: pkgA)
    let openedState = VideoEditorState(
      url: loadedA.sessionData.sourceSnapshotURL,
      originalURL: pkgA,
      sessionData: loadedA.sessionData
    )
    defer { openedState.cancelPendingPerformanceWork() }
    await openedState.loadMetadata()

    let pkgB = tempDir.appendingPathComponent("ProjectB.snapzy", isDirectory: true)
    try FileManager.default.moveItem(at: pkgA, to: pkgB)
    let loadedB = try SnapzyProjectPackage.load(from: pkgB)
    openedState.rebindProjectMediaURLs(from: loadedB.sessionData, newPackageURL: pkgB)
    XCTAssertTrue(openedState.editingSourceURL.path.hasPrefix(pkgB.standardizedFileURL.path))

    let resavedB = try await SnapzyProjectPackage.saveAsync(
      state: openedState,
      existingSourceSnapshotURL: openedState.editingSourceURL,
      existingPackageURL: pkgB,
      to: pkgB
    )
    XCTAssertEqual(resavedB.packageURL.standardizedFileURL, pkgB.standardizedFileURL)

    let siblings = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
    XCTAssertFalse(siblings.contains { $0.lastPathComponent.contains(".tmp-") })

    // Path traversal & symlink escape checks
    XCTAssertThrowsError(try SnapzyProjectPackage.resolveRelativePath("../escape.mov", inside: pkgB))
    XCTAssertThrowsError(try SnapzyProjectPackage.resolveRelativePath("/etc/passwd", inside: pkgB))
    XCTAssertThrowsError(try SnapzyProjectPackage.resolveRelativePath("Media/../../secret", inside: pkgB))

    let symlinkURL = pkgB.appendingPathComponent("Media/escaped_link.mov")
    try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
    XCTAssertThrowsError(try SnapzyProjectPackage.resolveRelativePath("Media/escaped_link.mov", inside: pkgB))
  }

  // MARK: - 6. Manager Window Reuse, Live Project Rename & GIF/Image Routing Isolation

  func testSnapzyPackage_managerWindowReuseLiveRenameAndGIFRoutingIsolation() async throws {
    // Section 3.2: Only `.snapzy` routes to project open; `.gif`, `.png`, `.mp4`, `.snapzyautomation` return false!
    XCTAssertTrue(SnapzyProjectPackage.isProjectURL(URL(fileURLWithPath: "/tmp/Demo.snapzy")))
    XCTAssertTrue(SnapzyProjectPackage.isProjectURL(URL(fileURLWithPath: "/tmp/Demo.SNAPZY")))
    XCTAssertFalse(SnapzyProjectPackage.isProjectURL(URL(fileURLWithPath: "/tmp/anim.gif")))
    XCTAssertFalse(SnapzyProjectPackage.isProjectURL(URL(fileURLWithPath: "/tmp/shot.png")))
    XCTAssertFalse(SnapzyProjectPackage.isProjectURL(URL(fileURLWithPath: "/tmp/clip.mp4")))
    XCTAssertFalse(SnapzyProjectPackage.isProjectURL(URL(fileURLWithPath: "/tmp/flow.snapzyautomation")))

    let videoURL = try await makeTestMovie(
      in: tempDir,
      name: "mgr_primary.mov",
      durationSeconds: 3.0,
      width: 320,
      height: 180
    )
    let authorState = VideoEditorState(url: videoURL)
    defer { authorState.cancelPendingPerformanceWork() }
    await authorState.loadMetadata()
    _ = authorState.addZoom(at: 0.5)

    let pkgURL = tempDir.appendingPathComponent("ManagerFlow.snapzy", isDirectory: true)
    _ = try SnapzyProjectPackage.save(state: authorState, to: pkgURL)

    // Open via VideoEditorManager and verify second open reuses the exact same controller!
    let c1 = try XCTUnwrap(VideoEditorManager.shared.openProjectSync(at: pkgURL))
    let c2 = try XCTUnwrap(VideoEditorManager.shared.openProjectSync(at: pkgURL))
    XCTAssertTrue(c1 === c2, "Opening the same .snapzy path twice must reuse the existing window controller")

    let liveState = try XCTUnwrap(c1.editorState)
    await liveState.loadMetadata()
    XCTAssertEqual(c1.projectContext.packageDisplayName, "ManagerFlow.snapzy")
    XCTAssertTrue(c1.canOverwriteProjectInPlace)

    // Rename project package live through `projectContext.onRenameProject` -> moves package & rebinds!
    try c1.projectContext.onRenameProject?("ManagerFlowRenamed")
    let expectedRenamedURL = tempDir.appendingPathComponent("ManagerFlowRenamed.snapzy", isDirectory: true)
    XCTAssertEqual(c1.projectPackageURL?.standardizedFileURL, expectedRenamedURL.standardizedFileURL)
    XCTAssertEqual(c1.window?.title, "ManagerFlowRenamed.snapzy")
    XCTAssertFalse(FileManager.default.fileExists(atPath: pkgURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: expectedRenamedURL.path))

    // Reject path-traversal rename attempts (`../escape`)
    XCTAssertThrowsError(try c1.projectContext.onRenameProject?("../escape"))

    // Edit speed segment, save in place onto renamed package, and export MP4!
    XCTAssertNotNil(liveState.addSpeed(range: 0.5 ... 1.5, rate: 2.0))
    XCTAssertTrue(liveState.hasUnsavedChanges)
    _ = try c1.performSaveProjectPackageSync(to: expectedRenamedURL)
    XCTAssertFalse(liveState.hasUnsavedChanges)

    let exportedURL = tempDir.appendingPathComponent("mgr_renamed_export.mp4")
    try await VideoEditorExporter.exportTrimmed(state: liveState, to: exportedURL) { _ in }
    XCTAssertTrue(FileManager.default.fileExists(atPath: exportedURL.path))

    VideoEditorManager.shared.closeAll()
  }

  // MARK: - Fixtures

  private func makeTestMovie(
    in directory: URL,
    name: String,
    durationSeconds: Double,
    width: Int,
    height: Int
  ) async throws -> URL {
    let outputURL = directory.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: outputURL)
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
    let fps: Int32 = 30
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
      ]
    )
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ]
    )
    writer.add(input)
    XCTAssertTrue(writer.startWriting())
    writer.startSession(atSourceTime: .zero)

    let totalFrames = max(6, Int(durationSeconds * Double(fps)))
    let q = DispatchQueue(label: "snapzy.pkg.test.movie.\(UUID().uuidString)")
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      var frame = 0
      input.requestMediaDataWhenReady(on: q) {
        while input.isReadyForMoreMediaData, frame < totalFrames {
          var pb: CVPixelBuffer?
          CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pb)
          if let pb {
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
              memset(base, Int32(28 + (frame * 5) % 160), CVPixelBufferGetDataSize(pb))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            let pts = CMTime(value: CMTimeValue(frame), timescale: fps)
            adaptor.append(pb, withPresentationTime: pts)
          }
          frame += 1
        }
        if frame >= totalFrames {
          input.markAsFinished()
          writer.finishWriting {
            if let err = writer.error {
              cont.resume(throwing: err)
            } else {
              cont.resume()
            }
          }
        }
      }
    }
    return outputURL
  }

  private func makeTestPNG(in directory: URL, name: String) throws -> URL {
    let url = directory.appendingPathComponent(name)
    let rep = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 64,
        pixelsHigh: 64,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(calibratedRed: 0.14, green: 0.24, blue: 0.42, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 64, height: 64).fill()
    NSGraphicsContext.restoreGraphicsState()
    let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    try png.write(to: url, options: .atomic)
    return url
  }
}
