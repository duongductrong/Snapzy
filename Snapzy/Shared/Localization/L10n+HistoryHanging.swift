import Foundation

extension L10n {
  enum HistoryHanging {
    static var sectionTitle: String {
      L10n.string(
        "preferences-history.hanging.section-title",
        defaultValue: "History Experience",
        comment: "History settings section for choosing the display style"
      )
    }

    static var styleTitle: String {
      L10n.string(
        "preferences-history.hanging.style-title",
        defaultValue: "Display style",
        comment: "Title above the traditional and hanging history options"
      )
    }

    static var styleDescription: String {
      L10n.string(
        "preferences-history.hanging.style-description",
        defaultValue: "Two ways to browse the same capture history. Selecting Hanging enables it automatically.",
        comment: "Explains that the styles share history and Hanging needs no separate enable toggle"
      )
    }

    static var traditional: String {
      L10n.string(
        "preferences-history.hanging.traditional",
        defaultValue: "Traditional",
        comment: "Name of the existing floating history panel style"
      )
    }

    static var hanging: String {
      L10n.string(
        "preferences-history.hanging.hanging",
        defaultValue: "Hanging",
        comment: "Name of the history style with photos hanging from a line at the screen edge"
      )
    }

    static var traditionalDescription: String {
      L10n.string(
        "preferences-history.hanging.traditional-description",
        defaultValue: "Browse captures in the familiar floating panel.",
        comment: "Description below the traditional history style preview"
      )
    }

    static var hangingDescription: String {
      L10n.string(
        "preferences-history.hanging.hanging-description",
        defaultValue: "Move to the topmost screen edge to reveal captures. Move away to auto-hide.",
        comment: "Description below the hanging history style preview explaining reveal and auto-hide"
      )
    }

    static var preview: String {
      L10n.string(
        "preferences-history.hanging.preview",
        defaultValue: "Preview History",
        comment: "Button that opens history in the selected display style"
      )
    }

    static var shelfTitle: String {
      L10n.string(
        "preferences-history.hanging.shelf-title",
        defaultValue: "Hanging History",
        comment: "Title of the hanging capture history shelf"
      )
    }

    static var shelfHint: String {
      L10n.string(
        "preferences-history.hanging.shelf-hint",
        defaultValue: "Your captures, close at hand. Drag one to use it anywhere.",
        comment: "Hint shown in the hanging history shelf"
      )
    }

    static var emptyTitle: String {
      L10n.string(
        "preferences-history.hanging.empty-title",
        defaultValue: "Nothing hanging here yet",
        comment: "Title when the hanging history shelf has no captures to display"
      )
    }

    static var emptyDescription: String {
      L10n.string(
        "preferences-history.hanging.empty-description",
        defaultValue: "Take a capture to see it here, or try a different filter.",
        comment: "Explains how to populate an empty hanging history shelf"
      )
    }

    static var historyDisabled: String {
      L10n.string(
        "preferences-history.hanging.history-disabled",
        defaultValue: "Capture history is turned off. Enable it in Settings to keep new captures here.",
        comment: "Message shown when capture history storage is disabled"
      )
    }

    static var browseAll: String {
      L10n.string(
        "preferences-history.hanging.browse-all",
        defaultValue: "Browse All History",
        comment: "Button that opens the full capture history window"
      )
    }

    static var pinImage: String {
      L10n.string(
        "preferences-history.hanging.pin-image",
        defaultValue: "Pin Image",
        comment: "Action to pin a capture image on screen"
      )
    }

    static var unpinImage: String {
      L10n.string(
        "preferences-history.hanging.unpin-image",
        defaultValue: "Unpin Image",
        comment: "Action to stop pinning a capture image on screen"
      )
    }

    static var keepOpen: String {
      L10n.string(
        "preferences-history.hanging.keep-open",
        defaultValue: "Keep Open",
        comment: "Action to keep the hanging history shelf visible when the pointer leaves"
      )
    }

    static var autoHide: String {
      L10n.string(
        "preferences-history.hanging.auto-hide",
        defaultValue: "Auto-hide",
        comment: "Action to let the hanging history shelf hide when the pointer leaves"
      )
    }

    static var close: String {
      L10n.string(
        "preferences-history.hanging.close",
        defaultValue: "Close Hanging History",
        comment: "Accessibility label for closing the hanging history shelf"
      )
    }

    static var missingFile: String {
      L10n.string(
        "preferences-history.hanging.missing-file",
        defaultValue: "The original capture file is no longer available.",
        comment: "Message when a hanging history capture file cannot be found"
      )
    }
  }
}
