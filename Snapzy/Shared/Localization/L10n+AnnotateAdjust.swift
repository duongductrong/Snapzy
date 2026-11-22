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
    static let exposure = string(
      "annotate.adjust.exposure",
      defaultValue: "Exposure",
      comment: "Image adjustment slider label: overall exposure in EV"
    )
    static let highlights = string(
      "annotate.adjust.highlights",
      defaultValue: "Highlights",
      comment: "Image adjustment slider label: brightness of the bright tones"
    )
    static let shadows = string(
      "annotate.adjust.shadows",
      defaultValue: "Shadows",
      comment: "Image adjustment slider label: brightness of the dark tones"
    )
    static let whites = string(
      "annotate.adjust.whites",
      defaultValue: "Whites",
      comment: "Image adjustment slider label: white point"
    )
    static let blacks = string(
      "annotate.adjust.blacks",
      defaultValue: "Blacks",
      comment: "Image adjustment slider label: black point"
    )
    static let temperature = string(
      "annotate.adjust.temperature",
      defaultValue: "Temperature",
      comment: "Image adjustment slider label: color temperature (cooler/warmer)"
    )
    static let tint = string(
      "annotate.adjust.tint",
      defaultValue: "Tint",
      comment: "Image adjustment slider label: green/magenta tint"
    )
    static let vibrance = string(
      "annotate.adjust.vibrance",
      defaultValue: "Vibrance",
      comment: "Image adjustment slider label: boosts muted colors"
    )
    static let clarity = string(
      "annotate.adjust.clarity",
      defaultValue: "Clarity",
      comment: "Image adjustment slider label: local mid-tone contrast"
    )
    static let vignette = string(
      "annotate.adjust.vignette",
      defaultValue: "Vignette",
      comment: "Image adjustment slider label: darkens or lightens the image corners"
    )
    static let intensity = string(
      "annotate.adjust.intensity",
      defaultValue: "Intensity",
      comment: "Slider label: strength of the selected filter preset"
    )
    static let groupLight = string(
      "annotate.adjust.group.light",
      defaultValue: "Light",
      comment: "Image adjustments group title: exposure, contrast, highlights, shadows"
    )
    static let groupColor = string(
      "annotate.adjust.group.color",
      defaultValue: "Color",
      comment: "Image adjustments group title: temperature, tint, vibrance, saturation"
    )
    static let groupEffects = string(
      "annotate.adjust.group.effects",
      defaultValue: "Effects",
      comment: "Image adjustments group title: clarity, sharpness, vignette"
    )
    static let groupResetHelp = string(
      "annotate.adjust.group.reset-help",
      defaultValue: "Reset this group",
      comment: "Tooltip for the button that resets one group of image adjustment sliders"
    )
    static let sliderResetHelp = string(
      "annotate.adjust.slider.reset-help",
      defaultValue: "Double-click to reset",
      comment: "Tooltip on an image adjustment slider: double-click resets it"
    )
    static let presetWarm = string(
      "annotate.adjust.preset.warm",
      defaultValue: "Warm",
      comment: "Filter preset name: warmer, golden tones"
    )
    static let presetCool = string(
      "annotate.adjust.preset.cool",
      defaultValue: "Cool",
      comment: "Filter preset name: cooler, bluish tones"
    )
    static let presetDramatic = string(
      "annotate.adjust.preset.dramatic",
      defaultValue: "Dramatic",
      comment: "Filter preset name: punchy contrast with dark corners"
    )
    static let presetMatte = string(
      "annotate.adjust.preset.matte",
      defaultValue: "Matte",
      comment: "Filter preset name: lifted blacks, soft muted look"
    )
  }
}
