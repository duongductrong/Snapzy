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
    The timeline lists clips (c1, c2…), zoom blocks (z1…), speed blocks (s1…), captions (t1…) and hidden-camera stretches (h1…); use those ids.
    Cut first, then add zooms and speeds: a cut slides everything after it left, so times you read before a cut change. \
    When cutting several parts, cut the latest part first so earlier times stay valid.
    Zoom centers are [x, y] from 0 to 1 with the origin at the top left. Speed blocks cannot overlap.
    For pauses, waiting or "zoom where I work", use remove_silences, speed_up_idle and auto_zoom_activity: \
    they find the parts themselves. get_activity tells when the user talks, waits or moves the cursor.
    To act on something on screen ("zoom on the Deploy button when it appears"), give add_zoom its text; \
    find_on_screen tells when and where words show, get_frame shows a moment. \
    get_transcript tells what is said, for requests about speech ("cut where I say 'um'", "zoom when I mention the settings").
    Studio recordings (studio true) keep the cursor and camera apart from the screen: set_cursor and set_camera restyle them, \
    and only when the timeline lists cursor or camera; otherwise they are part of the picture, so tell the user it can't be changed. \
    On Studio recordings get_activity lists clicks; auto_zoom_activity with source clicks zooms where the user clicks. \
    The camera bubble sits over the video: when a result notes it covers a zoom or the captions, move it or hide it \
    during zooms (set_camera hide_during_zooms) unless the user placed it on purpose.
    Captions (t1…) follow the recording, not the timeline: cuts hide the captions of removed footage. \
    Fix wording with edit_caption or replace_in_captions, add_caption / remove_captions for single ones, \
    translate_captions for another language; get_captions lists them all.
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
  /// The scene is text only; frames come through `get_frame`, which sizes its own image.
  var imageUnitSize: CGSize? { nil }
}
