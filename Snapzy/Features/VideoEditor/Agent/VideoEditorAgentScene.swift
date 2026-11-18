//
//  VideoEditorAgentScene.swift
//  Snapzy
//
//  What the model reads about the open video (`get_timeline`, and the scene sent
//  with each request). Times are seconds on the structural timeline, rounded to
//  hundredths. Encoded with snake_case keys.
//

import Foundation

nonisolated struct VideoEditorAgentScene: Encodable, Equatable {
  struct Clip: Encodable, Equatable {
    let id: String
    /// The clip's span on the timeline.
    let start: Double
    let end: Double
    /// The part of that span that plays (trimmed footage outside it stays visible but silent).
    let playsFrom: Double
    let playsTo: Double
    /// `recording`, or the file name of an inserted video.
    let source: String
  }

  struct Zoom: Encodable, Equatable {
    let id: String
    let start: Double
    let end: Double
    let level: Double
    /// [x, y] 0…1 from the top left; nil while following the mouse.
    let center: [Double]?
    let followMouse: Bool
    let enabled: Bool
  }

  struct Speed: Encodable, Equatable {
    let id: String
    let start: Double
    let end: Double
    let rate: Double
    let enabled: Bool
  }

  struct Background: Encodable, Equatable {
    let style: String
    let padding: Int
    let shadow: Double
    let cornerRadius: Int
    let alignment: String
    let aspectRatio: String
  }

  struct AudioTrack: Encodable, Equatable {
    let name: String
    /// Percent of the original, as exported.
    let volume: Int
  }

  struct Audio: Encodable, Equatable {
    let muted: Bool
    let tracks: [AudioTrack]
  }

  struct Selection: Encodable, Equatable {
    let clip: String?
    let zoom: String?
    let speed: String?
  }

  /// Studio cursor; nil when the recording has no editable cursor.
  struct Cursor: Encodable, Equatable {
    let visible: Bool
    let scale: Double
    let smoothing: Double
    let hideWhenIdle: Bool
    let clickEffect: String
    let clickSound: Bool
  }

  /// Studio camera; nil without a camera sidecar.
  struct Camera: Encodable, Equatable {
    let visible: Bool
    let shape: String
    let size: Double
    /// [x, y] 0…1 from the top left of the video.
    let center: [Double]
    let mirrored: Bool
  }

  struct Caption: Encodable, Equatable {
    let id: String
    /// Where it first shows on the timeline; nil when its footage is trimmed out.
    let start: Double?
    let end: Double?
    let text: String
  }

  struct Captions: Encodable, Equatable {
    let showOnVideo: Bool
    let position: String
    let textSize: Double
    let count: Int
    /// The first captions only; `count` tells how many there are.
    let items: [Caption]
  }

  /// Timeline length, trimmed footage included.
  let duration: Double
  /// What plays, before speed changes.
  let playableDuration: Double
  /// Exported length, speed applied.
  let outputDuration: Double
  let size: [Int]
  let playhead: Double
  let clips: [Clip]
  let zooms: [Zoom]
  let speeds: [Speed]
  let background: Background
  let audio: Audio
  let selection: Selection
  let hasMouseData: Bool
  var cursor: Cursor?
  var camera: Camera?
  /// nil before captions are generated.
  var captions: Captions?
}
