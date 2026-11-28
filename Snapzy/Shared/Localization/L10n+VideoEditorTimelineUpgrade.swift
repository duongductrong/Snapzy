//
//  L10n+VideoEditorTimelineUpgrade.swift
//  Snapzy
//
//  Localized strings for Video Editor multi-track audio, detach audio,
//  close gaps, clip transitions, text overlays, timeline toolbar actions,
//  magnetic snapping, bookmarks, and shuttle controls.
//

import Foundation

extension L10n.VideoEditor {
  // MARK: - Multi-Track Audio & Clip Audio Controls

  nonisolated static let audioEmptyHint = L10n.string(
    "video-editor.audio-empty-hint",
    defaultValue: "Audio — click + Audio above to add music or voiceover",
    comment: "Placeholder shown in the empty audio timeline track"
  )

  nonisolated static func audioLaneDropHint(_ trackLabel: String) -> String {
    L10n.format(
      "video-editor.audio-lane-drop-hint",
      defaultValue: "Drop audio clip or right-click to import into %@",
      comment: "Placeholder shown inside an empty secondary audio track lane. %@ is the track label such as A2.",
      trackLabel
    )
  }

  nonisolated static func muteAudioTrack(_ trackLabel: String) -> String {
    L10n.format(
      "video-editor.mute-audio-track",
      defaultValue: "Mute Audio Track %@",
      comment: "Accessibility label for muting an audio track lane. %@ is the track label such as A1.",
      trackLabel
    )
  }

  nonisolated static func unmuteAudioTrack(_ trackLabel: String) -> String {
    L10n.format(
      "video-editor.unmute-audio-track",
      defaultValue: "Unmute Audio Track %@",
      comment: "Accessibility label for unmuting an audio track lane. %@ is the track label such as A1.",
      trackLabel
    )
  }

  nonisolated static func muteTrack(_ trackLabel: String) -> String {
    L10n.format(
      "video-editor.mute-track",
      defaultValue: "Mute Track %@",
      comment: "Tooltip and menu label for muting an audio track lane. %@ is the track label such as A1.",
      trackLabel
    )
  }

  nonisolated static func unmuteTrack(_ trackLabel: String) -> String {
    L10n.format(
      "video-editor.unmute-track",
      defaultValue: "Unmute Track %@",
      comment: "Tooltip and menu label for unmuting an audio track lane. %@ is the track label such as A1.",
      trackLabel
    )
  }

  nonisolated static let addAudioTrack = L10n.string(
    "video-editor.add-audio-track",
    defaultValue: "Add Audio Track",
    comment: "Button label and file picker title for adding an audio track"
  )

  nonisolated static func addAudioTrackLaneHint(_ trackLabel: String) -> String {
    L10n.format(
      "video-editor.add-audio-track-lane-hint",
      defaultValue: "Add new audio track lane (%@)",
      comment: "Tooltip for the + button that appends a new empty audio track lane. %@ is the next track label such as A2.",
      trackLabel
    )
  }

  nonisolated static func addAudioTrackNumbered(_ trackLabel: String) -> String {
    L10n.format(
      "video-editor.add-audio-track-numbered",
      defaultValue: "Add Audio Track (%@)",
      comment: "Context menu label for adding a new audio track lane. %@ is the next track label such as A2.",
      trackLabel
    )
  }

  nonisolated static func importAudioToTrack(_ trackLabel: String) -> String {
    L10n.format(
      "video-editor.import-audio-to-track",
      defaultValue: "Import Audio to Track %@…",
      comment: "Context menu label for importing an audio file directly into a track lane. %@ is the track label such as A2.",
      trackLabel
    )
  }

  nonisolated static func removeEmptyTrack(_ trackLabel: String) -> String {
    L10n.format(
      "video-editor.remove-empty-track",
      defaultValue: "Remove Empty Track %@",
      comment: "Context menu label for removing an empty trailing audio track lane. %@ is the track label such as A2.",
      trackLabel
    )
  }

  nonisolated static let splitAudioAtPlayhead = L10n.string(
    "video-editor.split-audio-at-playhead",
    defaultValue: "Split Audio at Playhead",
    comment: "Context menu label for splitting an audio clip at the current playhead"
  )

  nonisolated static func moveAudioTrackAbove(_ trackLabel: String) -> String {
    L10n.format(
      "video-editor.move-audio-track-above",
      defaultValue: "Move to Track Above (%@)",
      comment: "Context menu label for moving an audio clip to the track lane above. %@ is the destination track label.",
      trackLabel
    )
  }

  nonisolated static func moveAudioTrackBelow(_ trackLabel: String) -> String {
    L10n.format(
      "video-editor.move-audio-track-below",
      defaultValue: "Move to Track Below (%@)",
      comment: "Context menu label for moving an audio clip to the track lane below. %@ is the destination track label.",
      trackLabel
    )
  }

  nonisolated static let muteAudioClip = L10n.string(
    "video-editor.mute-audio-clip",
    defaultValue: "Mute Audio Clip",
    comment: "Context menu label for muting a selected audio clip"
  )

  nonisolated static let unmuteAudioClip = L10n.string(
    "video-editor.unmute-audio-clip",
    defaultValue: "Unmute Audio Clip",
    comment: "Context menu label for unmuting a selected audio clip"
  )

  nonisolated static let resetFades = L10n.string(
    "video-editor.reset-fades",
    defaultValue: "Reset Fades",
    comment: "Context menu label for resetting audio fade-in and fade-out durations to zero"
  )

  nonisolated static let deleteAudioClip = L10n.string(
    "video-editor.delete-audio-clip",
    defaultValue: "Delete Audio Clip",
    comment: "Context menu label for deleting an audio clip from the timeline"
  )

  nonisolated static let dragAudioFadeInHint = L10n.string(
    "video-editor.drag-audio-fade-in-hint",
    defaultValue: "Drag to adjust Audio Fade In",
    comment: "Tooltip for the interactive audio fade-in handle on the timeline"
  )

  nonisolated static let dragAudioFadeOutHint = L10n.string(
    "video-editor.drag-audio-fade-out-hint",
    defaultValue: "Drag to adjust Audio Fade Out",
    comment: "Tooltip for the interactive audio fade-out handle on the timeline"
  )

  nonisolated static let unmute = L10n.string(
    "video-editor.unmute",
    defaultValue: "Unmute",
    comment: "Button label for unmuting audio"
  )

  nonisolated static let clipVolume = L10n.string(
    "video-editor.clip-volume",
    defaultValue: "Clip Volume",
    comment: "Slider label for adjusting an individual audio clip's volume"
  )

  nonisolated static let fadeIn = L10n.string(
    "video-editor.fade-in",
    defaultValue: "Fade In",
    comment: "Slider label for audio fade-in duration"
  )

  nonisolated static let fadeOut = L10n.string(
    "video-editor.fade-out",
    defaultValue: "Fade Out",
    comment: "Slider label for audio fade-out duration"
  )

  nonisolated static let addAudioPrompt = L10n.string(
    "video-editor.add-audio-prompt",
    defaultValue: "Add Audio",
    comment: "Confirm button title in the file picker when importing an audio track"
  )

  nonisolated static func detachedAudioName(_ clipName: String) -> String {
    L10n.format(
      "video-editor.detached-audio-name",
      defaultValue: "%@ (Audio)",
      comment: "Default display name for an audio clip detached from a video clip. %@ is the video filename.",
      clipName
    )
  }

  // MARK: - Detach Audio, Gaps & Clip Transitions

  nonisolated static let detachAudio = L10n.string(
    "video-editor.detach-audio",
    defaultValue: "Detach Audio",
    comment: "Context menu label for detaching embedded audio from a video clip onto an audio track"
  )

  nonisolated static let audioDetached = L10n.string(
    "video-editor.audio-detached",
    defaultValue: "Audio Detached",
    comment: "Disabled context menu label indicating a video clip's audio has already been detached"
  )

  nonisolated static let closeGap = L10n.string(
    "video-editor.close-gap",
    defaultValue: "Close Gap",
    comment: "Pill button label inside an empty timeline gap to snap the following clip left"
  )

  nonisolated static func closeGapHint(_ formattedDuration: String) -> String {
    L10n.format(
      "video-editor.close-gap-hint",
      defaultValue: "Snap clip left to remove %@ black-screen gap",
      comment: "Tooltip for closing a black-screen timeline gap. %@ is the formatted gap duration such as 1.5s.",
      formattedDuration
    )
  }

  nonisolated static let closeThisGap = L10n.string(
    "video-editor.close-this-gap",
    defaultValue: "Close This Gap",
    comment: "Context menu label for closing the selected empty timeline gap"
  )

  nonisolated static let closeGapBeforeClip = L10n.string(
    "video-editor.close-gap-before-clip",
    defaultValue: "Close Gap Before Clip",
    comment: "Context menu label for closing the empty gap immediately preceding a video clip"
  )

  nonisolated static let closeAllGaps = L10n.string(
    "video-editor.close-all-gaps",
    defaultValue: "Close All Gaps",
    comment: "Context menu label for closing every empty timeline gap between video clips"
  )

  nonisolated static let clipTransition = L10n.string(
    "video-editor.clip-transition",
    defaultValue: "Clip Transition",
    comment: "Header title for the clip transition picker popover"
  )

  nonisolated static let addTransition = L10n.string(
    "video-editor.add-transition",
    defaultValue: "Add Transition",
    comment: "Accessibility label for the diamond transition button between abutting video clips"
  )

  nonisolated static func namedTransition(_ styleName: String) -> String {
    L10n.format(
      "video-editor.named-transition",
      defaultValue: "%@ Transition",
      comment: "Accessibility label for an active transition badge between clips. %@ is the transition style name.",
      styleName
    )
  }

  nonisolated static func transitionActiveHint(_ styleName: String, _ formattedDuration: String) -> String {
    L10n.format(
      "video-editor.transition-active-hint",
      defaultValue: "%@ (%@) — click to edit",
      comment: "Tooltip for an active clip transition badge. First %@ is style name, second %@ is duration such as 0.5s.",
      styleName,
      formattedDuration
    )
  }

  nonisolated static let addTransitionHint = L10n.string(
    "video-editor.add-transition-hint",
    defaultValue: "Add Crossfade or Dip to Black transition",
    comment: "Tooltip for adding a transition between two adjacent video clips"
  )

  nonisolated static let closeTransitionPopover = L10n.string(
    "video-editor.close-transition-popover",
    defaultValue: "Close Transition Popover",
    comment: "Accessibility label for the close button in the clip transition popover"
  )

  nonisolated static func transitionOptionAccessibility(_ styleName: String) -> String {
    L10n.format(
      "video-editor.transition-option-accessibility",
      defaultValue: "Transition %@",
      comment: "Accessibility label for a transition style button in the transition popover. %@ is the style name.",
      styleName
    )
  }

  nonisolated static let leadingTransition = L10n.string(
    "video-editor.leading-transition",
    defaultValue: "Leading Transition",
    comment: "Submenu label in a video clip's context menu for configuring its incoming transition"
  )

  nonisolated static let noneOption = L10n.string(
    "video-editor.none-option",
    defaultValue: "None",
    comment: "Option label representing no transition or no text animation"
  )

  nonisolated static let transitionCrossfade = L10n.string(
    "video-editor.transition-crossfade",
    defaultValue: "Crossfade",
    comment: "Transition style name for smoothly dissolving between two video clips"
  )

  nonisolated static let transitionDipToBlack = L10n.string(
    "video-editor.transition-dip-to-black",
    defaultValue: "Dip to Black",
    comment: "Transition style name for fading out to black and back in between two video clips"
  )

  // MARK: - Text / Title Overlays

  nonisolated static let textAndTitlesHint = L10n.string(
    "video-editor.text-and-titles-hint",
    defaultValue: "Text & Titles (T)",
    comment: "Tooltip and accessibility label for the Text & Titles sidebar rail button"
  )

  nonisolated static let defaultTitleText = L10n.string(
    "video-editor.default-title-text",
    defaultValue: "Title",
    comment: "Default placeholder text for a newly created timeline text overlay"
  )

  nonisolated static let addTitle = L10n.string(
    "video-editor.add-title",
    defaultValue: "Add Title",
    comment: "Button label for inserting a new text title overlay at the playhead"
  )

  nonisolated static let addTextAtPlayhead = L10n.string(
    "video-editor.add-text-at-playhead",
    defaultValue: "Add Text at Playhead",
    comment: "Accessibility label for the button that adds a text overlay at the current playhead"
  )

  nonisolated static let deleteTextOverlayHint = L10n.string(
    "video-editor.delete-text-overlay-hint",
    defaultValue: "Delete text overlay",
    comment: "Tooltip for the row trash button that deletes a text overlay"
  )

  nonisolated static let enterTitlePlaceholder = L10n.string(
    "video-editor.enter-title-placeholder",
    defaultValue: "Enter title text…",
    comment: "Placeholder text inside the text overlay content field"
  )

  nonisolated static let toggleBoldHint = L10n.string(
    "video-editor.toggle-bold-hint",
    defaultValue: "Toggle Bold",
    comment: "Tooltip for toggling bold weight on a text overlay"
  )

  nonisolated static let textPill = L10n.string(
    "video-editor.text-pill",
    defaultValue: "Pill",
    comment: "Label for the rounded background pill toggle on a text overlay"
  )

  nonisolated static let textAnimation = L10n.string(
    "video-editor.text-animation",
    defaultValue: "Animation",
    comment: "Section label for choosing a text overlay entrance/exit animation"
  )

  nonisolated static let textAnimationFade = L10n.string(
    "video-editor.text-animation-fade",
    defaultValue: "Fade",
    comment: "Text overlay animation style: smooth opacity fade in and out"
  )

  nonisolated static let textAnimationPop = L10n.string(
    "video-editor.text-animation-pop",
    defaultValue: "Pop",
    comment: "Text overlay animation style: scale pop-in and pop-out"
  )

  nonisolated static let positionTop = L10n.string(
    "video-editor.position-top",
    defaultValue: "Top",
    comment: "Position preset placing a text overlay near the top of the video frame"
  )

  nonisolated static let positionBottom = L10n.string(
    "video-editor.position-bottom",
    defaultValue: "Bottom",
    comment: "Position preset placing a text overlay near the bottom of the video frame"
  )

  nonisolated static let duplicate = L10n.string(
    "video-editor.duplicate",
    defaultValue: "Duplicate",
    comment: "Button label for duplicating the selected text overlay"
  )

  nonisolated static let textEmptyHeadline = L10n.string(
    "video-editor.text-empty-headline",
    defaultValue: "Add animated titles, callouts, or lower thirds directly on your video timeline.",
    comment: "Empty state primary description in the Text & Titles sidebar panel"
  )

  nonisolated static let textEmptySubheadline = L10n.string(
    "video-editor.text-empty-subheadline",
    defaultValue: "Drag any title on the preview to reposition it, or resize its bar on the timeline.",
    comment: "Empty state secondary hint in the Text & Titles sidebar panel"
  )

  nonisolated static func textOverlayAccessibility(_ text: String) -> String {
    L10n.format(
      "video-editor.text-overlay-accessibility",
      defaultValue: "Text Overlay: %@",
      comment: "Accessibility label for a draggable text overlay rendered over the video preview. %@ is the text content.",
      text
    )
  }

  nonisolated static let editTextOverlay = L10n.string(
    "video-editor.edit-text-overlay",
    defaultValue: "Edit Text Overlay",
    comment: "Context menu label for opening the inspector for a text overlay"
  )

  nonisolated static let duplicateTextOverlay = L10n.string(
    "video-editor.duplicate-text-overlay",
    defaultValue: "Duplicate Text Overlay",
    comment: "Context menu label for duplicating a text overlay on the timeline"
  )

  nonisolated static let deleteTextOverlay = L10n.string(
    "video-editor.delete-text-overlay",
    defaultValue: "Delete Text Overlay",
    comment: "Context menu label for deleting a text overlay from the timeline"
  )

  nonisolated static let colorWhite = L10n.string(
    "video-editor.color-white",
    defaultValue: "White",
    comment: "Color swatch tooltip: white"
  )

  nonisolated static let colorYellow = L10n.string(
    "video-editor.color-yellow",
    defaultValue: "Yellow",
    comment: "Color swatch tooltip: yellow"
  )

  nonisolated static let colorCyan = L10n.string(
    "video-editor.color-cyan",
    defaultValue: "Cyan",
    comment: "Color swatch tooltip: cyan"
  )

  nonisolated static let colorCoral = L10n.string(
    "video-editor.color-coral",
    defaultValue: "Coral",
    comment: "Color swatch tooltip: coral red"
  )

  nonisolated static let colorBlack = L10n.string(
    "video-editor.color-black",
    defaultValue: "Black",
    comment: "Color swatch tooltip: black"
  )

  nonisolated static let colorNavy = L10n.string(
    "video-editor.color-navy",
    defaultValue: "Navy",
    comment: "Color swatch tooltip: navy blue"
  )

  nonisolated static let colorViolet = L10n.string(
    "video-editor.color-violet",
    defaultValue: "Violet",
    comment: "Color swatch tooltip: violet purple"
  )

  nonisolated static let colorCrimson = L10n.string(
    "video-editor.color-crimson",
    defaultValue: "Crimson",
    comment: "Color swatch tooltip: crimson red"
  )

  // MARK: - Timeline Controls, Snapping, Bookmarks & Shuttle

  nonisolated static let trimStartToPlayhead = L10n.string(
    "video-editor.trim-start-to-playhead",
    defaultValue: "Trim Start to Playhead",
    comment: "Accessibility label for trimming the start of the selected clip to the playhead"
  )

  nonisolated static let trimStartToPlayheadHint = L10n.string(
    "video-editor.trim-start-to-playhead-hint",
    defaultValue: "Trim start of selected clip to playhead ([)",
    comment: "Tooltip for trimming the start of the selected clip to the playhead"
  )

  nonisolated static let trimEndToPlayhead = L10n.string(
    "video-editor.trim-end-to-playhead",
    defaultValue: "Trim End to Playhead",
    comment: "Accessibility label for trimming the end of the selected clip to the playhead"
  )

  nonisolated static let trimEndToPlayheadHint = L10n.string(
    "video-editor.trim-end-to-playhead-hint",
    defaultValue: "Trim end of selected clip to playhead (])",
    comment: "Tooltip for trimming the end of the selected clip to the playhead"
  )

  nonisolated static let duplicateClip = L10n.string(
    "video-editor.duplicate-clip",
    defaultValue: "Duplicate Clip",
    comment: "Accessibility label for duplicating the selected clip"
  )

  nonisolated static let duplicateClipHint = L10n.string(
    "video-editor.duplicate-clip-hint",
    defaultValue: "Duplicate selected clip (⌘D)",
    comment: "Tooltip for duplicating the selected clip"
  )

  nonisolated static let addVideoClip = L10n.string(
    "video-editor.add-video-clip",
    defaultValue: "Add Video Clip",
    comment: "Accessibility label for inserting a video clip into the timeline"
  )

  nonisolated static let addAudioTrackHint = L10n.string(
    "video-editor.add-audio-track-hint",
    defaultValue: "Add audio track (MP3, M4A, WAV, AAC)",
    comment: "Tooltip for importing an audio file onto the timeline"
  )

  nonisolated static let addBookmark = L10n.string(
    "video-editor.add-bookmark",
    defaultValue: "Add Bookmark",
    comment: "Accessibility label for adding a timeline bookmark at the playhead"
  )

  nonisolated static let removeBookmark = L10n.string(
    "video-editor.remove-bookmark",
    defaultValue: "Remove Bookmark",
    comment: "Accessibility and context menu label for removing a timeline bookmark"
  )

  nonisolated static let toggleBookmarkHint = L10n.string(
    "video-editor.toggle-bookmark-hint",
    defaultValue: "Toggle bookmark marker at playhead (M)",
    comment: "Tooltip for toggling a timeline bookmark marker at the playhead"
  )

  nonisolated static let jumpToBookmarkHint = L10n.string(
    "video-editor.jump-to-bookmark-hint",
    defaultValue: "Jump to bookmark (right-click to remove)",
    comment: "Tooltip for a bookmark flag on the timeline ruler"
  )

  nonisolated static let enableSnapping = L10n.string(
    "video-editor.enable-snapping",
    defaultValue: "Enable Snapping",
    comment: "Accessibility label for enabling magnetic timeline snapping"
  )

  nonisolated static let disableSnapping = L10n.string(
    "video-editor.disable-snapping",
    defaultValue: "Disable Snapping",
    comment: "Accessibility label for disabling magnetic timeline snapping"
  )

  nonisolated static let toggleSnappingHint = L10n.string(
    "video-editor.toggle-snapping-hint",
    defaultValue: "Toggle magnetic timeline snapping (N — or hold Option to temporarily bypass)",
    comment: "Tooltip for the magnetic timeline snapping toggle button"
  )

  nonisolated static func shuttleSpeedAccessibility(_ formattedRate: String) -> String {
    L10n.format(
      "video-editor.shuttle-speed-accessibility",
      defaultValue: "Shuttle Speed %@",
      comment: "Accessibility label for the J/K/L shuttle playback speed badge. %@ is the rate such as 2× or -2×.",
      formattedRate
    )
  }

  // MARK: - Editorial Captions / Subtitles Studio

  nonisolated static let captionsAddManual = L10n.string(
    "video-editor.captions-add-manual",
    defaultValue: "Add Subtitle",
    comment: "Button label for inserting a manual subtitle cue at the current playhead"
  )

  nonisolated static let captionsImportFile = L10n.string(
    "video-editor.captions-import-file",
    defaultValue: "Import SRT/VTT",
    comment: "Button label for importing an external .srt or .vtt subtitle file"
  )

  nonisolated static let captionsDefaultSampleText = L10n.string(
    "video-editor.captions-default-sample-text",
    defaultValue: "Subtitle",
    comment: "Default text content for a newly inserted manual subtitle segment"
  )

  nonisolated static let captionsPresets = L10n.string(
    "video-editor.captions-presets",
    defaultValue: "Style Presets",
    comment: "Section label for curated editorial subtitle style presets"
  )

  nonisolated static let captionsPresetKineticPulse = L10n.string(
    "video-editor.captions-preset-kinetic-pulse",
    defaultValue: "Kinetic Word",
    comment: "Subtitle preset name: active spoken word pill highlight"
  )

  nonisolated static let captionsPresetEditorialInk = L10n.string(
    "video-editor.captions-preset-editorial-ink",
    defaultValue: "Editorial Ink",
    comment: "Subtitle preset name: serif ink on crisp editorial paper card"
  )

  nonisolated static let captionsSurfaceClassicPill = L10n.string(
    "video-editor.captions-surface-classic-pill",
    defaultValue: "Classic Pill",
    comment: "Subtitle surface option: classic rounded pill"
  )

  nonisolated static let captionsSurfaceStudioGlass = L10n.string(
    "video-editor.captions-surface-studio-glass",
    defaultValue: "Frosted Glass",
    comment: "Subtitle surface option: translucent frosted studio capsule"
  )

  nonisolated static let captionsSurfaceCinemaClean = L10n.string(
    "video-editor.captions-surface-cinema-clean",
    defaultValue: "Borderless",
    comment: "Subtitle surface option: borderless cinema stroke + shadow"
  )

  nonisolated static let captionsSurfaceEditorialPaper = L10n.string(
    "video-editor.captions-surface-editorial-paper",
    defaultValue: "Paper Card",
    comment: "Subtitle surface option: light paper card"
  )

  nonisolated static let captionsSurfaceAccentRule = L10n.string(
    "video-editor.captions-surface-accent-rule",
    defaultValue: "Left Rule",
    comment: "Subtitle surface option: dark card with vertical accent bar"
  )

  nonisolated static let captionsTracking = L10n.string(
    "video-editor.captions-tracking",
    defaultValue: "Tracking",
    comment: "Label for subtitle character letter-spacing control"
  )

  nonisolated static let captionsTrackingTight = L10n.string(
    "video-editor.captions-tracking-tight",
    defaultValue: "Tight",
    comment: "Letter tracking option: tight"
  )

  nonisolated static let captionsTrackingNormal = L10n.string(
    "video-editor.captions-tracking-normal",
    defaultValue: "Normal",
    comment: "Letter tracking option: normal"
  )

  nonisolated static let captionsTrackingWide = L10n.string(
    "video-editor.captions-tracking-wide",
    defaultValue: "Wide",
    comment: "Letter tracking option: wide"
  )

  nonisolated static let captionsTrackingCinema = L10n.string(
    "video-editor.captions-tracking-cinema",
    defaultValue: "Cinema",
    comment: "Letter tracking option: wide cinema spacing"
  )

  nonisolated static let captionsWordMode = L10n.string(
    "video-editor.captions-word-mode",
    defaultValue: "Word Timing",
    comment: "Label for word-level highlight or progressive reveal mode"
  )

  nonisolated static let captionsWordFullLine = L10n.string(
    "video-editor.captions-word-full-line",
    defaultValue: "Full Line",
    comment: "Word timing option: show full caption line at once"
  )

  nonisolated static let captionsWordActiveHighlight = L10n.string(
    "video-editor.captions-word-active-highlight",
    defaultValue: "Highlight",
    comment: "Word timing option: highlight active spoken word with accent pill"
  )

  nonisolated static let captionsWordProgressiveReveal = L10n.string(
    "video-editor.captions-word-progressive-reveal",
    defaultValue: "Reveal",
    comment: "Word timing option: reveal words progressively as spoken"
  )

  nonisolated static let captionsAnimationIn = L10n.string(
    "video-editor.captions-animation-in",
    defaultValue: "In",
    comment: "Label for subtitle entrance animation picker"
  )

  nonisolated static let captionsAnimationOut = L10n.string(
    "video-editor.captions-animation-out",
    defaultValue: "Out",
    comment: "Label for subtitle exit animation picker"
  )

  nonisolated static let captionsAnimSpringRise = L10n.string(
    "video-editor.captions-anim-spring-rise",
    defaultValue: "Spring Rise",
    comment: "Subtitle animation option: smooth upward spring rise"
  )

  nonisolated static let captionsAnimOpticalBlur = L10n.string(
    "video-editor.captions-anim-optical-blur",
    defaultValue: "Optical Blur",
    comment: "Subtitle animation option: optical Gaussian defocus transition"
  )

  nonisolated static let captionsAnimCinematicFade = L10n.string(
    "video-editor.captions-anim-cinematic-fade",
    defaultValue: "Cinema Fade",
    comment: "Subtitle animation option: smooth S-curve dissolve"
  )

  nonisolated static let captionsAnimStudioPop = L10n.string(
    "video-editor.captions-anim-studio-pop",
    defaultValue: "Studio Pop",
    comment: "Subtitle animation option: critically-damped spring scale"
  )

  nonisolated static let captionsAnimEditorialWipe = L10n.string(
    "video-editor.captions-anim-editorial-wipe",
    defaultValue: "Mask Wipe",
    comment: "Subtitle animation option: horizontal reveal wipe"
  )

  nonisolated static let captionsAnimDriftSlide = L10n.string(
    "video-editor.captions-anim-drift-slide",
    defaultValue: "Drift Slide",
    comment: "Subtitle animation option: horizontal editorial glide"
  )

  nonisolated static let captionsMotionSpeed = L10n.string(
    "video-editor.captions-motion-speed",
    defaultValue: "Transition Duration",
    comment: "Slider label for subtitle in/out animation duration"
  )

  nonisolated static let captionsPreviewMotion = L10n.string(
    "video-editor.captions-preview-motion",
    defaultValue: "Preview Motion",
    comment: "Button label that replays the current subtitle's entrance and exit animation"
  )

  nonisolated static let captionsPresetCyberCyan = L10n.string(
    "video-editor.captions-preset-cyber-cyan",
    defaultValue: "Cyber Cyan",
    comment: "Subtitle preset name: dual-line white lead + uppercase ice-cyan gradient hero with neon bloom"
  )

  nonisolated static let captionsPresetVelvetSerif = L10n.string(
    "video-editor.captions-preset-velvet-serif",
    defaultValue: "Velvet Serif",
    comment: "Subtitle preset name: editorial italic serif with electric violet gradient and glow"
  )

  nonisolated static let captionsPresetSelectFrame = L10n.string(
    "video-editor.captions-preset-select-frame",
    defaultValue: "Select Frame",
    comment: "Subtitle preset name: blue motion-design selection bounding box with 8 anchor handles"
  )

  nonisolated static let captionsPresetSolarSheen = L10n.string(
    "video-editor.captions-preset-solar-sheen",
    defaultValue: "Solar Sheen",
    comment: "Subtitle preset name: solar yellow pill badge with dark ink and diagonal light sheen"
  )

  nonisolated static let captionsPresetGoldSlide = L10n.string(
    "video-editor.captions-preset-gold-slide",
    defaultValue: "Gold Slide",
    comment: "Subtitle preset name: golden amber gradient with masked baseline slide-up"
  )

  nonisolated static let captionsSurfaceGlowBloom = L10n.string(
    "video-editor.captions-surface-glow-bloom",
    defaultValue: "Neon Bloom",
    comment: "Subtitle surface option: floating luminous neon bloom with contact shadow"
  )

  nonisolated static let captionsSurfaceSelectionFrame = L10n.string(
    "video-editor.captions-surface-selection-frame",
    defaultValue: "Select Box",
    comment: "Subtitle surface option: wireframe bounding box with 8 square transform handles"
  )

  nonisolated static let captionsSurfaceSolarPill = L10n.string(
    "video-editor.captions-surface-solar-pill",
    defaultValue: "Badge Pill",
    comment: "Subtitle surface option: high-contrast rounded badge with inner specular rim"
  )

  nonisolated static let captionsAnimMaskSlideUp = L10n.string(
    "video-editor.captions-anim-mask-slide-up",
    defaultValue: "Mask Slide",
    comment: "Subtitle animation option: masked baseline upward reveal"
  )

  nonisolated static let captionsAnimElasticBounce = L10n.string(
    "video-editor.captions-anim-elastic-bounce",
    defaultValue: "Elastic Bounce",
    comment: "Subtitle animation option: playful elastic spring pop"
  )

  nonisolated static let captionsAnimNeonFlicker = L10n.string(
    "video-editor.captions-anim-neon-flicker",
    defaultValue: "Neon Flicker",
    comment: "Subtitle animation option: optical neon tube ignition flicker"
  )

  nonisolated static let captionsAnimWhipBlur = L10n.string(
    "video-editor.captions-anim-whip-blur",
    defaultValue: "Whip Blur",
    comment: "Subtitle animation option: fast horizontal whip glide with motion blur"
  )

  nonisolated static let captionsItalic = L10n.string(
    "video-editor.captions-italic",
    defaultValue: "Italic",
    comment: "Tooltip for toggling italic slant on subtitles"
  )

  nonisolated static let captionsGradientText = L10n.string(
    "video-editor.captions-gradient-text",
    defaultValue: "Gradient Fill",
    comment: "Toggle label for linear color gradient inside subtitle glyphs"
  )

  nonisolated static let captionsGlow = L10n.string(
    "video-editor.captions-glow",
    defaultValue: "Glow",
    comment: "Label for optical neon glow intensity and color controls"
  )

  nonisolated static let captionsShimmerSweep = L10n.string(
    "video-editor.captions-shimmer-sweep",
    defaultValue: "Light Sheen Sweep",
    comment: "Toggle label for sweeping a specular light highlight across settled subtitles"
  )

  // MARK: - Text ↔ Captions Integration

  nonisolated static let captionsPresetRangeHighlight = L10n.string(
    "video-editor.captions-preset-range-highlight",
    defaultValue: "Range Highlight",
    comment: "Text preset name: cobalt selection bar with left and right cursor pins"
  )

  nonisolated static let captionsSurfaceRangeHighlight = L10n.string(
    "video-editor.captions-surface-range-highlight",
    defaultValue: "Range Pins",
    comment: "Surface format option: text-selection bar with left/right cursor pins"
  )

  nonisolated static let textSyncStyleToCaptions = L10n.string(
    "video-editor.text-sync-style-to-captions",
    defaultValue: "Apply Style to Captions",
    comment: "Button in Text Studio that copies the selected text overlay's style to the Captions track"
  )

  nonisolated static let textConvertToCaption = L10n.string(
    "video-editor.text-convert-to-caption",
    defaultValue: "Move to Captions",
    comment: "Button that converts a Text overlay item into a Caption cue on the Captions track"
  )

  nonisolated static let captionsPromoteCueToText = L10n.string(
    "video-editor.captions-promote-cue-to-text",
    defaultValue: "Promote to Text (Aa) for custom style & position",
    comment: "Tooltip and label for promoting a single subtitle cue into an independent Text overlay"
  )

  nonisolated static let captionsConvertAllToText = L10n.string(
    "video-editor.captions-convert-all-to-text",
    defaultValue: "Convert All to Text (Aa)",
    comment: "Button in Captions panel that converts all subtitle cues into independent editable Text overlays"
  )

  nonisolated static let captionsSyncStyleFromText = L10n.string(
    "video-editor.captions-sync-style-from-text",
    defaultValue: "Sync Style from Text",
    comment: "Button in Captions panel that adopts the style of the selected Text overlay"
  )

  nonisolated static let captionsOpenTextStudio = L10n.string(
    "video-editor.captions-open-text-studio",
    defaultValue: "Open Text Studio (Aa)",
    comment: "Button in Captions panel that switches to the Text Studio sidebar for rich per-item styles"
  )

  nonisolated static let captionsTextRelationshipHint = L10n.string(
    "video-editor.captions-text-relationship-hint",
    defaultValue: "Convert key lines or the full transcript to Text (Aa) for independent presets, free drag placement, and per-item motion.",
    comment: "Concise helper description explaining how Captions and Text work together"
  )

  // MARK: - Font Library, Weights, Treatments & Advanced Motion

  nonisolated static let fontLibraryButton = L10n.string(
    "video-editor.font-library-button",
    defaultValue: "Fonts",
    comment: "Button label opening the installed macOS fonts and local TTF/OTF font picker popover"
  )

  nonisolated static let fontImportLocalFile = L10n.string(
    "video-editor.font-import-local-file",
    defaultValue: "Import .TTF / .OTF…",
    comment: "Button in Font Library popover for importing custom font files from disk"
  )

  nonisolated static let fontWeightRegular = L10n.string(
    "video-editor.font-weight-regular",
    defaultValue: "Regular",
    comment: "Font weight 400 label"
  )

  nonisolated static let fontWeightMedium = L10n.string(
    "video-editor.font-weight-medium",
    defaultValue: "Medium",
    comment: "Font weight 500 label"
  )

  nonisolated static let fontWeightSemiBold = L10n.string(
    "video-editor.font-weight-semibold",
    defaultValue: "SemiBold",
    comment: "Font weight 600 label"
  )

  nonisolated static let fontWeightBold = L10n.string(
    "video-editor.font-weight-bold",
    defaultValue: "Bold",
    comment: "Font weight 700 label"
  )

  nonisolated static let fontWeightExtraBold = L10n.string(
    "video-editor.font-weight-extrabold",
    defaultValue: "ExtraBold",
    comment: "Font weight 800 label"
  )

  nonisolated static let fontWeightBlack = L10n.string(
    "video-editor.font-weight-black",
    defaultValue: "Black",
    comment: "Font weight 900 label"
  )

  nonisolated static let captionsPresetSplitTone = L10n.string(
    "video-editor.captions-preset-split-tone",
    defaultValue: "Split Tone",
    comment: "Preset name: crisp dual-ink headline with accented final keyword"
  )

  nonisolated static let captionsPresetHollowHero = L10n.string(
    "video-editor.captions-preset-hollow-hero",
    defaultValue: "Hollow Hero",
    comment: "Preset name: architectural hollow vector stroke paired with solid hero word"
  )

  nonisolated static let captionsPresetMonoTag = L10n.string(
    "video-editor.captions-preset-mono-tag",
    defaultValue: "Mono Tag",
    comment: "Preset name: minimal technical tag with emerald indicator dot and typewriter reveal"
  )

  nonisolated static let captionsPresetCinemaIvory = L10n.string(
    "video-editor.captions-preset-cinema-ivory",
    defaultValue: "Cinema Ivory",
    comment: "Preset name: warm 35mm theatrical italic subtitle with wide tracking pull"
  )

  nonisolated static let captionsSurfaceMonoTag = L10n.string(
    "video-editor.captions-surface-mono-tag",
    defaultValue: "Status Tag",
    comment: "Surface format option: matte dark tag with leading status indicator dot"
  )

  nonisolated static let captionsTreatmentLabel = L10n.string(
    "video-editor.captions-treatment-label",
    defaultValue: "Ink Mode",
    comment: "Label for choosing solid, split-accent, or hollow-outline word treatment"
  )

  nonisolated static let captionsTreatmentSolid = L10n.string(
    "video-editor.captions-treatment-solid",
    defaultValue: "Solid",
    comment: "Text treatment option: uniform fill or gradient"
  )

  nonisolated static let captionsTreatmentSplit = L10n.string(
    "video-editor.captions-treatment-split",
    defaultValue: "Split",
    comment: "Text treatment option: final word highlighted in accent ink"
  )

  nonisolated static let captionsTreatmentHollow = L10n.string(
    "video-editor.captions-treatment-hollow",
    defaultValue: "Outline",
    comment: "Text treatment option: hollow vector outline with solid final word"
  )

  nonisolated static let captionsAnimWordCascade = L10n.string(
    "video-editor.captions-anim-word-cascade",
    defaultValue: "Word Cascade",
    comment: "Animation option: staggered per-word upward glide"
  )

  nonisolated static let captionsAnimWordBlurIn = L10n.string(
    "video-editor.captions-anim-word-blur-in",
    defaultValue: "Word Focus",
    comment: "Animation option: staggered per-word optical focus reveal"
  )

  nonisolated static let captionsAnimTypewriterPro = L10n.string(
    "video-editor.captions-anim-typewriter-pro",
    defaultValue: "Typewriter",
    comment: "Animation option: character-by-character typing with live cursor"
  )

  nonisolated static let captionsAnimShutterFlip = L10n.string(
    "video-editor.captions-anim-shutter-flip",
    defaultValue: "Shutter Flip",
    comment: "Animation option: X-axis vertical title flip"
  )

  nonisolated static let captionsAnimTrackingPull = L10n.string(
    "video-editor.captions-anim-tracking-pull",
    defaultValue: "Tracking Pull",
    comment: "Animation option: wide cinema letter-spacing pulling smoothly together"
  )

  // MARK: - Redesigned Spacious Text Studio Inspector Tabs & Labeled Controls

  nonisolated static let textTabPresets = L10n.string(
    "video-editor.text-tab-presets",
    defaultValue: "Presets",
    comment: "Text Studio segmented tab 1: curated architectural and cinema presets"
  )

  nonisolated static let textTabDesign = L10n.string(
    "video-editor.text-tab-design",
    defaultValue: "Style",
    comment: "Text Studio segmented tab 2: font, colors, surface, and layout design"
  )

  nonisolated static let textTabEffects = L10n.string(
    "video-editor.text-tab-effects",
    defaultValue: "Motion",
    comment: "Text Studio segmented tab 3: entrance, exit, and per-word motion effects"
  )

  nonisolated static let textTabItems = L10n.string(
    "video-editor.text-tab-items",
    defaultValue: "Items",
    comment: "Text Studio segmented tab 4: timeline text overlay list"
  )

  nonisolated static let textSectionTypography = L10n.string(
    "video-editor.text-section-typography",
    defaultValue: "Typography",
    comment: "Section header in Text Studio Style tab for font family, weight, bold, italic, and casing"
  )

  nonisolated static let textSectionColorSurface = L10n.string(
    "video-editor.text-section-color-surface",
    defaultValue: "Color & Surface",
    comment: "Section header in Text Studio Style tab for text color, gradient, ink treatment, backdrop, and glow"
  )

  nonisolated static let textSectionLayout = L10n.string(
    "video-editor.text-section-layout",
    defaultValue: "Layout",
    comment: "Section header in Text Studio Style tab for font size, wrap width, tracking, position, and 2-tier hierarchy"
  )

  nonisolated static let textColorInk = L10n.string(
    "video-editor.text-color-ink",
    defaultValue: "Text",
    comment: "Short label beside the primary text color well"
  )

  nonisolated static let textColorGradientEnd = L10n.string(
    "video-editor.text-color-gradient-end",
    defaultValue: "End",
    comment: "Short label beside the gradient end color well"
  )

  nonisolated static let textColorAccentShort = L10n.string(
    "video-editor.text-color-accent-short",
    defaultValue: "Accent",
    comment: "Short label beside the accent highlight color well"
  )

  nonisolated static let textColorSurfaceShort = L10n.string(
    "video-editor.text-color-surface-short",
    defaultValue: "Fill",
    comment: "Short label beside the surface backdrop color well"
  )

  nonisolated static let textSurfaceLabel = L10n.string(
    "video-editor.text-surface-label",
    defaultValue: "Backdrop",
    comment: "Label for choosing the text overlay backdrop frame style"
  )

  nonisolated static let textBackdropOpacity = L10n.string(
    "video-editor.text-backdrop-opacity",
    defaultValue: "Opacity",
    comment: "Slider label for adjusting backdrop frame opacity"
  )

  nonisolated static let textMaxWidthWrap = L10n.string(
    "video-editor.text-max-width-wrap",
    defaultValue: "Box Width (Wrap)",
    comment: "Slider label for controlling maximum horizontal text box width fraction and line wrapping"
  )

  nonisolated static let textDualLineHeroFull = L10n.string(
    "video-editor.text-dual-line-hero-full",
    defaultValue: "2-Tier Hierarchy (Lead + Hero)",
    comment: "Toggle label for dual-tier lead + hero title layout"
  )

  nonisolated static let textMotionTabWord = L10n.string(
    "video-editor.text-motion-tab-word",
    defaultValue: "By Word",
    comment: "Sub-tab in Text Studio Motion tab for per-word timing and kinetic word animation"
  )

  nonisolated static let textWordAnimationLabel = L10n.string(
    "video-editor.text-word-animation-label",
    defaultValue: "Word Motion",
    comment: "Section label for choosing the per-word arrival animation physics"
  )

  nonisolated static let textSelectOrCreateHint = L10n.string(
    "video-editor.text-select-or-create-hint",
    defaultValue: "Select a title on the canvas or add one at the playhead to customize its style and motion.",
    comment: "Helper prompt shown in Style or Motion tab when no text overlay is currently selected"
  )

  nonisolated static let textItemsEmpty = L10n.string(
    "video-editor.text-items-empty",
    defaultValue: "No timeline titles yet.",
    comment: "Empty state text in the Text Studio Items tab when no text overlays exist"
  )

  nonisolated static let textCommitShortcutHint = L10n.string(
    "video-editor.text-commit-shortcut-hint",
    defaultValue: "⌘↩ Done",
    comment: "Compact button/shortcut badge to commit text edits and exit keyboard focus"
  )

  nonisolated static let textApplyStyleToAll = L10n.string(
    "video-editor.text-apply-style-to-all",
    defaultValue: "Apply Style to All Text",
    comment: "Button applying the selected text overlay's typography, color, and layout style to all text overlays"
  )

  nonisolated static let textApplyStyleMotionToAll = L10n.string(
    "video-editor.text-apply-style-motion-to-all",
    defaultValue: "Apply Style & Motion to All",
    comment: "Button applying both style and motion of the selected text overlay to all text overlays"
  )

  nonisolated static let textApplyMotionToAll = L10n.string(
    "video-editor.text-apply-motion-to-all",
    defaultValue: "Apply Motion to All Text",
    comment: "Button applying the selected text overlay's In/Out and Word Timing motion to all text overlays"
  )

  nonisolated static func bulkSelectedCount(_ count: Int) -> String {
    L10n.format(
      "video-editor.bulk-selected-count",
      defaultValue: "%lld selected",
      comment: "Label showing how many timeline items are currently selected after Cmd+A",
      count
    )
  }

  nonisolated static let deleteSelectedAll = L10n.string(
    "video-editor.delete-selected-all",
    defaultValue: "Delete All",
    comment: "Destructive button deleting all multi-selected items on the active track"
  )

  // MARK: - Live WYSIWYG Canvas Editing

  nonisolated static let textCanvasEditingBadge = L10n.string(
    "video-editor.text-canvas-editing-badge",
    defaultValue: "Editing • Esc / ⌘↩",
    comment: "Compact floating badge shown above a title while editing directly on the video canvas"
  )

  // MARK: - System & Installed Font Picker

  nonisolated static let systemFontDisplayName = L10n.string(
    "video-editor.system-font-display-name",
    defaultValue: "System (SF Pro)",
    comment: "Display name for the default macOS system font in the Video Editor font picker"
  )

  nonisolated static let installedFontsSection = L10n.string(
    "video-editor.installed-fonts-section",
    defaultValue: "Installed Fonts",
    comment: "Section header for fonts already installed on the Mac"
  )

  nonisolated static let importedFontsSection = L10n.string(
    "video-editor.imported-fonts-section",
    defaultValue: "Imported Fonts",
    comment: "Section header for user-imported local font files"
  )

  nonisolated static let fontSearchPlaceholder = L10n.string(
    "video-editor.font-search-placeholder",
    defaultValue: "Search installed fonts…",
    comment: "Search field placeholder inside the Video Editor font picker"
  )

  nonisolated static let fontMissingNotice = L10n.string(
    "video-editor.font-missing-notice",
    defaultValue: "Font not installed — showing System Font",
    comment: "Notice shown when a text overlay references a font family that is not installed on this Mac"
  )

  nonisolated static let fontUseSystemSubstitute = L10n.string(
    "video-editor.font-use-system-substitute",
    defaultValue: "Use System Font",
    comment: "Button switching a missing font reference to the macOS system font"
  )

  nonisolated static func addTextTrackNumbered(_ trackLabel: String) -> String {
    L10n.format(
      "video-editor.add-text-track-numbered",
      defaultValue: "Add Text Track %@",
      comment: "Accessibility label and tooltip for adding a numbered text overlay track lane (e.g. T2)",
      trackLabel
    )
  }

  nonisolated static let italicBadgeSuffix = L10n.string(
    "video-editor.italic-badge-suffix",
    defaultValue: "Italic",
    comment: "Badge label appended when italic style is active on captions or titles"
  )

  nonisolated static func textCanvasFontSizePoints(_ points: Int) -> String {
    L10n.format(
      "video-editor.text-canvas-font-size-points",
      defaultValue: "%lld pt",
      comment: "Readout badge showing text font size in points while dragging a corner scale handle on canvas",
      points
    )
  }

  nonisolated static func textCanvasWrapPercent(_ percent: Int) -> String {
    L10n.format(
      "video-editor.text-canvas-wrap-percent",
      defaultValue: "Wrap %lld%%",
      comment: "Readout badge showing text wrap width percentage while dragging a width handle on canvas",
      percent
    )
  }

  nonisolated static let textWrapHandleAccessibility = L10n.string(
    "video-editor.text-wrap-handle-accessibility",
    defaultValue: "Adjust text wrap width",
    comment: "Accessibility label for the side pill handle that resizes text wrap width on the canvas"
  )

  nonisolated static let textScaleHandleAccessibility = L10n.string(
    "video-editor.text-scale-handle-accessibility",
    defaultValue: "Scale text size",
    comment: "Accessibility label for the corner handle that scales text size on the canvas"
  )
}
