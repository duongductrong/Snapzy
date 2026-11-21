//
//  L10n+AnnotateAdjust.swift
//  Snapzy
//
//  Strings for the Annotate image adjustments section (sliders, filter presets).
//

import Foundation

extension L10n {
  nonisolated enum AnnotateAdjust {
    static let section = string(
      "annotate.adjust.section",
      defaultValue: "Adjust",
      comment: "Annotate sidebar section title for image adjustments (brightness, contrast, filters)"
    )
    static let reset = string(
      "annotate.adjust.reset",
      defaultValue: "Reset",
      comment: "Button that resets all image adjustments and filters to the original image"
    )
    static let resetHelp = string(
      "annotate.adjust.reset-help",
      defaultValue: "Restore the original image",
      comment: "Tooltip for the reset button in the image adjustments section"
    )
    static let brightness = string(
      "annotate.adjust.brightness",
      defaultValue: "Brightness",
      comment: "Image adjustment slider label"
    )
    static let contrast = string(
      "annotate.adjust.contrast",
      defaultValue: "Contrast",
      comment: "Image adjustment slider label"
    )
    static let saturation = string(
      "annotate.adjust.saturation",
      defaultValue: "Saturation",
      comment: "Image adjustment slider label"
    )
    static let sharpness = string(
      "annotate.adjust.sharpness",
      defaultValue: "Sharpness",
      comment: "Image adjustment slider label"
    )
    static let filters = string(
      "annotate.adjust.filters",
      defaultValue: "Filters",
      comment: "Label above the filter preset thumbnails in the image adjustments section"
    )
    static let presetOriginal = string(
      "annotate.adjust.preset.original",
      defaultValue: "Original",
      comment: "Filter preset: no filter"
    )
    static let presetVivid = string(
      "annotate.adjust.preset.vivid",
      defaultValue: "Vivid",
      comment: "Filter preset name: more vibrant colors"
    )
    static let presetMono = string(
      "annotate.adjust.preset.mono",
      defaultValue: "Mono",
      comment: "Filter preset name: black and white"
    )
    static let presetNoir = string(
      "annotate.adjust.preset.noir",
      defaultValue: "Noir",
      comment: "Filter preset name: high-contrast black and white"
    )
    static let presetTonal = string(
      "annotate.adjust.preset.tonal",
      defaultValue: "Tonal",
      comment: "Filter preset name: soft black and white"
    )
    static let presetSepia = string(
      "annotate.adjust.preset.sepia",
      defaultValue: "Sepia",
      comment: "Filter preset name: brownish vintage tone"
    )
    static let presetChrome = string(
      "annotate.adjust.preset.chrome",
      defaultValue: "Chrome",
      comment: "Filter preset name: punchy, high-saturation look"
    )
    static let presetFade = string(
      "annotate.adjust.preset.fade",
      defaultValue: "Fade",
      comment: "Filter preset name: washed-out colors"
    )
    static let presetInstant = string(
      "annotate.adjust.preset.instant",
      defaultValue: "Instant",
      comment: "Filter preset name: instant-camera look"
    )
    static let presetProcess = string(
      "annotate.adjust.preset.process",
      defaultValue: "Process",
      comment: "Filter preset name: cool cross-processed look"
    )
    static let presetTransfer = string(
      "annotate.adjust.preset.transfer",
      defaultValue: "Transfer",
      comment: "Filter preset name: warm vintage look"
    )
  }
}
