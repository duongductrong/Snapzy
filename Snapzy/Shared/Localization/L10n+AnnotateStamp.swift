//
//  L10n+AnnotateStamp.swift
//  Snapzy
//
//  Strings for the Annotate Stamp tool and its picker.
//

import Foundation

extension L10n.Annotate {
  nonisolated static let stampTool = L10n.string(
    "annotate.tool.stamp",
    defaultValue: "Stamp",
    comment: "Annotation tool display name: places sticker badges, emoji and image stamps"
  )
}

extension L10n {
  nonisolated enum AnnotateStamp {
    static let stickers = L10n.string(
      "annotate.stamp.stickers",
      defaultValue: "Stickers",
      comment: "Stamp picker tab: designed sticker badges"
    )
    static let emoji = L10n.string(
      "annotate.stamp.emoji",
      defaultValue: "Emoji",
      comment: "Stamp picker tab: emoji"
    )
    static let image = L10n.string(
      "annotate.stamp.image",
      defaultValue: "Image",
      comment: "Stamp picker tab: use an image file as a stamp"
    )
    static let searchEmoji = L10n.string(
      "annotate.stamp.search-emoji",
      defaultValue: "Search emoji",
      comment: "Placeholder of the emoji search field in the stamp picker"
    )
    static let recent = L10n.string(
      "annotate.stamp.recent",
      defaultValue: "Recent",
      comment: "Stamp picker section: recently used stamps"
    )
    static let popular = L10n.string(
      "annotate.stamp.popular",
      defaultValue: "Popular",
      comment: "Stamp picker section: commonly used emoji"
    )
    static let allEmoji = L10n.string(
      "annotate.stamp.all-emoji",
      defaultValue: "All Emoji",
      comment: "Stamp picker section: every emoji"
    )
    static let noResults = L10n.string(
      "annotate.stamp.no-results",
      defaultValue: "No matching emoji",
      comment: "Stamp picker: the emoji search found nothing"
    )
    static let chooseImage = L10n.string(
      "annotate.stamp.choose-image",
      defaultValue: "Choose Image…",
      comment: "Button and open panel title: pick an image file to use as a stamp"
    )
    static let imageHint = L10n.string(
      "annotate.stamp.image-hint",
      defaultValue: "Use any image file as a stamp. Transparent PNGs make the best stickers.",
      comment: "Stamp picker Image tab explanation"
    )
    static let chooseStamp = L10n.string(
      "annotate.stamp.choose",
      defaultValue: "Choose Stamp",
      comment: "Tooltip of the quick properties button that opens the stamp picker"
    )
    static let stickerStyle = L10n.string(
      "annotate.stamp.sticker-style",
      defaultValue: "Sticker",
      comment: "Toggle label: draw the stamp with a white sticker outline and shadow"
    )
    static let stickerStyleHelp = L10n.string(
      "annotate.stamp.sticker-style-help",
      defaultValue: "White outline and soft shadow",
      comment: "Tooltip for the sticker style toggle"
    )
    static let opacity = L10n.string(
      "annotate.stamp.opacity",
      defaultValue: "Opacity",
      comment: "Label for the stamp opacity slider"
    )
    static let gestureHint = L10n.string(
      "annotate.stamp.gesture-hint",
      defaultValue: "Click to place · Drag to size",
      comment: "Hint for the Stamp tool: a click places the stamp, a drag sets its size"
    )
    static let badges = L10n.string(
      "annotate.stamp.badges",
      defaultValue: "Badges",
      comment: "Stamp picker section: text badges"
    )
    static let icons = L10n.string(
      "annotate.stamp.icons",
      defaultValue: "Icons",
      comment: "Stamp picker section: round icon stickers"
    )
    static let stickerApproved = L10n.string(
      "annotate.stamp.sticker.approved",
      defaultValue: "Approved",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerRejected = L10n.string(
      "annotate.stamp.sticker.rejected",
      defaultValue: "Rejected",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerLGTM = L10n.string(
      "annotate.stamp.sticker.lgtm",
      defaultValue: "Looks Good to Me",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerNew = L10n.string(
      "annotate.stamp.sticker.new",
      defaultValue: "New",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerBeta = L10n.string(
      "annotate.stamp.sticker.beta",
      defaultValue: "Beta",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerHot = L10n.string(
      "annotate.stamp.sticker.hot",
      defaultValue: "Hot",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerTodo = L10n.string(
      "annotate.stamp.sticker.todo",
      defaultValue: "To Do",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerWIP = L10n.string(
      "annotate.stamp.sticker.wip",
      defaultValue: "Work in Progress",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerBug = L10n.string(
      "annotate.stamp.sticker.bug",
      defaultValue: "Bug",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerFixed = L10n.string(
      "annotate.stamp.sticker.fixed",
      defaultValue: "Fixed",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerThumbsUp = L10n.string(
      "annotate.stamp.sticker.thumbs-up",
      defaultValue: "Thumbs Up",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerHeart = L10n.string(
      "annotate.stamp.sticker.heart",
      defaultValue: "Heart",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerStar = L10n.string(
      "annotate.stamp.sticker.star",
      defaultValue: "Star",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerCheck = L10n.string(
      "annotate.stamp.sticker.check",
      defaultValue: "Check",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerCross = L10n.string(
      "annotate.stamp.sticker.cross",
      defaultValue: "Cross",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerWarning = L10n.string(
      "annotate.stamp.sticker.warning",
      defaultValue: "Warning",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerQuestion = L10n.string(
      "annotate.stamp.sticker.question",
      defaultValue: "Question",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerIdea = L10n.string(
      "annotate.stamp.sticker.idea",
      defaultValue: "Idea",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerSparkles = L10n.string(
      "annotate.stamp.sticker.sparkles",
      defaultValue: "Sparkles",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerPin = L10n.string(
      "annotate.stamp.sticker.pin",
      defaultValue: "Pin",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerArrowRight = L10n.string(
      "annotate.stamp.sticker.arrow-right",
      defaultValue: "Arrow Right",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerArrowLeft = L10n.string(
      "annotate.stamp.sticker.arrow-left",
      defaultValue: "Arrow Left",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerArrowUp = L10n.string(
      "annotate.stamp.sticker.arrow-up",
      defaultValue: "Arrow Up",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
    static let stickerArrowDown = L10n.string(
      "annotate.stamp.sticker.arrow-down",
      defaultValue: "Arrow Down",
      comment: "Stamp picker: name of a sticker, shown as its tooltip"
    )
  }
}

