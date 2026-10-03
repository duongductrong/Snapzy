//
//  VideoEditorProgressOperationTests.swift
//  SnapzyTests
//
//  Tests for operation-specific Video Editor progress copy.
//

import XCTest
@testable import Snapzy

final class VideoEditorProgressOperationTests: XCTestCase {
  func testSaveOperationUsesSaveCopyAndPreparationMessage() {
    let operation = VideoEditorProgressOperation.saveVideo

    XCTAssertEqual(operation.title, L10n.VideoEditor.savingVideo)
    XCTAssertEqual(operation.initialStatusMessage, L10n.VideoEditor.preparingSave)
    XCTAssertNotEqual(operation.title, L10n.VideoEditor.exportingVideo)
    XCTAssertNotEqual(operation.initialStatusMessage, L10n.VideoEditor.preparingExport)
  }

  func testOtherOperationsKeepTheirSpecificTitles() {
    XCTAssertEqual(
      VideoEditorProgressOperation.exportVideo.title,
      L10n.VideoEditor.exportingVideo
    )
    XCTAssertEqual(
      VideoEditorProgressOperation.saveGIF.title,
      L10n.VideoEditor.saveGIFTitle
    )
    XCTAssertEqual(
      VideoEditorProgressOperation.exportGIF.title,
      L10n.VideoEditor.saveResizedGIFTitle
    )
    XCTAssertEqual(
      VideoEditorProgressOperation.uploadToCloud.title,
      L10n.PreferencesHistory.uploadingToCloud
    )
  }
}
