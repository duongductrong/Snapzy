import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Snapzy

final class AnnotateImageDropLoaderTests: XCTestCase {
  func testLoadsImageObjectProvider() throws {
    let image = try makeImage(width: 24, height: 16)
    let provider = NSItemProvider(object: image)
    let loaded = expectation(description: "image object loaded")

    XCTAssertTrue(AnnotateImageDropLoader.load(from: provider) { result in
      XCTAssertEqual(result?.image.size, image.size)
      loaded.fulfill()
    })

    wait(for: [loaded], timeout: 2)
  }

  func testLoadsFileRepresentationProvider() throws {
    let image = try makeImage(width: 30, height: 20)
    let data = try XCTUnwrap(image.tiffRepresentation)
    let sourceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("snapzy-drop-\(UUID().uuidString).tiff")
    try data.write(to: sourceURL)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let provider = NSItemProvider()
    provider.registerFileRepresentation(
      forTypeIdentifier: UTType.tiff.identifier,
      fileOptions: [],
      visibility: .all
    ) { completion in
      completion(sourceURL, false, nil)
      return nil
    }

    let loaded = expectation(description: "file representation loaded")
    XCTAssertTrue(AnnotateImageDropLoader.load(from: provider) { result in
      XCTAssertNotNil(result?.image)
      XCTAssertFalse(result?.data?.isEmpty ?? true)
      loaded.fulfill()
    })

    wait(for: [loaded], timeout: 2)
  }

  func testRejectsProviderWithoutImageContent() {
    XCTAssertFalse(AnnotateImageDropLoader.load(from: NSItemProvider()) { _ in
      XCTFail("Completion should not run for an unsupported provider")
    })
  }

  private func makeImage(width: Int, height: Int) throws -> NSImage {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: width, height: height))
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
  }
}
