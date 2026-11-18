//
//  VideoEditorAgentStudioArguments.swift
//  Snapzy
//
//  Arguments of the Studio and caption agent tools (snake_case JSON) and their presets.
//

import CoreGraphics
import Foundation

nonisolated struct VideoEditorAgentCursorArguments: Decodable {
  var visible: Bool?
  var scale: Double?
  var smoothing: Double?
  var hideWhenIdle: Bool?
  var clickEffect: String?
  var clickSound: Bool?
}

nonisolated struct VideoEditorAgentCameraArguments: Decodable {
  var visible: Bool?
  var shape: String?
  var size: Double?
  var position: String?
  var center: [Double]?
  var mirrored: Bool?
  var hideStart: VideoEditorAgentTime?
  var hideEnd: VideoEditorAgentTime?
  var clearHidden: Bool?
}

nonisolated struct VideoEditorAgentCaptionArguments: Decodable {
  var language: String?
  var showOnVideo: Bool?
}

nonisolated struct VideoEditorAgentCaptionEditArguments: Decodable {
  var id: String?
  var text: String?
  var start: VideoEditorAgentTime?
  var end: VideoEditorAgentTime?
  var showOnVideo: Bool?
  var position: String?
  var textSize: Double?
}

nonisolated enum VideoEditorAgentStudioTools {
  static let cameraPositions: [(name: String, center: CGPoint)] = [
    ("top_left", CGPoint(x: 0.15, y: 0.15)), ("top", CGPoint(x: 0.5, y: 0.15)), ("top_right", CGPoint(x: 0.85, y: 0.15)),
    ("left", CGPoint(x: 0.15, y: 0.5)), ("center", CGPoint(x: 0.5, y: 0.5)), ("right", CGPoint(x: 0.85, y: 0.5)),
    ("bottom_left", CGPoint(x: 0.15, y: 0.85)), ("bottom", CGPoint(x: 0.5, y: 0.85)), ("bottom_right", CGPoint(x: 0.85, y: 0.85)),
  ]
  /// Captions get_timeline lists before it only counts them.
  static let maximumListedCaptions = 40
}
