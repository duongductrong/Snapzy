//
//  VideoEditorAgentSurface.swift
//  Snapzy
//
//  Plugs the Video Editor timeline into the shared agent core (`Features/Agent`):
//  the words providers use and the toolbox conformance.
//

import CoreGraphics
import Foundation

// MARK: - Surface

extension AgentSurface {
  static let video = AgentSurface(
    id: "video",
    logCategory: .editor,
    instructions: """
    You edit a screen recording in Snapzy's video editor. Do what the user asks right away; never ask questions.
    Times are seconds on the timeline the user sees (a number, or "m:ss.s"). \
    The timeline lists clips (c1, c2…), zoom blocks (z1…) and speed blocks (s1…); use those ids.
    Cut first, then add zooms and speeds: a cut slides everything after it left, so times you read before a cut change. \
    When cutting several parts, cut the latest part first so earlier times stay valid.
    Zoom centers are [x, y] from 0 to 1 with the origin at the top left. Speed blocks cannot overlap.
    For pauses, waiting or "zoom where I work", use remove_silences, speed_up_idle and auto_zoom_activity: \
    they find the parts themselves. get_activity tells when the user talks, waits or moves the cursor.
    Keep Snapzy's defaults unless the user asks for something else. "It"/"that" usually means what you changed last.
    You cannot export, save, share or open files; say so if asked.
    """,
    toolsModeNote: "The timeline is already in the request, so don't call get_timeline unless something changed.",
    planModeHint: #"removing 0:10–0:15 and 0:40–0:45 = two cut_range ops, latest first; "speed up the middle 4x" = one add_speed op."#,
    cliModeNote: "Use only its tools to change the video; you have no shell, files or web, and must not try them. "
      + "The timeline is in the message, so don't call get_timeline unless something changed.",
    snapshotToolDescription: "Look at the video frame under the playhead.",
    imageAttachedNote: "The attached image is the video frame under the playhead.",
    imageOnRequestNote: "Call get_snapshot if you need to see a video frame."
  )
}

// MARK: - Toolbox

extension VideoEditorAgentToolbox: AgentToolbox {
  var surface: AgentSurface { .video }
  var toolSpecs: [AgentToolSpec] { VideoEditorAgentToolCatalog.all }

  /// Unknown names are neither paced nor counted: they always fail.
  func isReadOnly(_ name: String) -> Bool {
    VideoEditorAgentToolName(rawValue: name)?.isReadOnly ?? true
  }
}

extension VideoEditorAgentScene: AgentScene {
  /// The video scene is text only; frames come later (phase 6).
  var imageUnitSize: CGSize? { nil }
}
