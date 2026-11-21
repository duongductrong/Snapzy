//
//  QuickAccessActionKind.swift
//  Snapzy
//
//  Stable action identifiers for Quick Access card customization.
//

import Foundation

enum QuickAccessActionDisplayStyle: String, Codable {
  case primary
  case corner
}

enum QuickAccessActionSurface: Equatable {
  case overlay
  case contextMenu
}

enum QuickAccessActionSlot: String, CaseIterable, Codable, Hashable, Identifiable {
  case centerTop
  case centerBottom
  case topTrailing
  case topLeading
  case bottomLeading
  case bottomTrailing

  var id: String { rawValue }

  static let centerSlots: [QuickAccessActionSlot] = [
    .centerTop,
    .centerBottom,
  ]

  static let cornerSlots: [QuickAccessActionSlot] = [
    .topTrailing,
    .topLeading,
    .bottomLeading,
    .bottomTrailing,
  ]

  static let defaultAssignments: [QuickAccessActionSlot: QuickAccessActionKind] = [
    .centerTop: .copy,
    .centerBottom: .saveOrOpen,
    .topTrailing: .dismiss,
    .topLeading: .delete,
    .bottomLeading: .edit,
    .bottomTrailing: .uploadToCloud,
  ]

  var isCenterSlot: Bool {
    Self.centerSlots.contains(self)
  }

  var settingsTitle: String {
    switch self {
    case .centerTop:
      return L10n.PreferencesQuickAccess.slotCenterTop
    case .centerBottom:
      return L10n.PreferencesQuickAccess.slotCenterBottom
    case .topTrailing:
      return L10n.PreferencesQuickAccess.slotTopRight
    case .topLeading:
      return L10n.PreferencesQuickAccess.slotTopLeft
    case .bottomLeading:
      return L10n.PreferencesQuickAccess.slotBottomLeft
    case .bottomTrailing:
      return L10n.PreferencesQuickAccess.slotBottomRight
    }
  }
}

enum QuickAccessActionKind: String, CaseIterable, Codable, Hashable, Identifiable {
  case copy
  case saveOrOpen
  case dismiss
  case delete
  case edit
  case uploadToCloud
  case pinToScreen
  case optimize
  case collapseToEdge

  var id: String { rawValue }

  static let defaultOrder: [QuickAccessActionKind] = [
    .copy,
    .saveOrOpen,
    .dismiss,
    .delete,
    .edit,
    .uploadToCloud,
    .pinToScreen,
    .optimize,
    .collapseToEdge,
  ]

  static let defaultEnabledActions = Set(defaultOrder)

  /// Actions that existed before the known-actions list was persisted. A saved
  /// enabled list written back then never had a chance to include later actions,
  /// so those are treated as new (enabled) rather than explicitly disabled.
  static let legacyKnownActions: Set<QuickAccessActionKind> = [
    .copy, .saveOrOpen, .dismiss, .delete, .edit, .uploadToCloud, .pinToScreen,
  ]

  var displayStyle: QuickAccessActionDisplayStyle {
    switch self {
    case .copy, .saveOrOpen:
      return .primary
    case .dismiss, .delete, .edit, .uploadToCloud, .pinToScreen, .optimize, .collapseToEdge:
      return .corner
    }
  }

  var settingsTitle: String {
    switch self {
    case .copy:
      return L10n.Common.copy
    case .saveOrOpen:
      return L10n.PreferencesQuickAccess.saveOrOpenAction
    case .dismiss:
      return L10n.Common.close
    case .delete:
      return L10n.Common.deleteAction
    case .edit:
      return L10n.PreferencesQuickAccess.editAction
    case .uploadToCloud:
      return L10n.AnnotateUI.uploadToCloud
    case .pinToScreen:
      return L10n.PreferencesQuickAccess.pinToScreenAction
    case .optimize:
      return L10n.PreferencesQuickAccess.optimizeAction
    case .collapseToEdge:
      return L10n.QuickAccess.collapseToEdge
    }
  }

  var settingsPlacementTitle: String {
    switch displayStyle {
    case .primary:
      return L10n.PreferencesQuickAccess.primaryActionBadge
    case .corner:
      return L10n.PreferencesQuickAccess.cornerActionBadge
    }
  }

  var isContextMenuDestructiveGroup: Bool {
    switch self {
    case .dismiss, .delete:
      return true
    case .copy, .saveOrOpen, .edit, .uploadToCloud, .pinToScreen, .optimize, .collapseToEdge:
      return false
    }
  }

  static func contextMenuOrder(from actions: [QuickAccessActionKind]) -> [QuickAccessActionKind] {
    let regularActions = actions.filter { !$0.isContextMenuDestructiveGroup }
    let destructiveActions = actions.filter { $0.isContextMenuDestructiveGroup }
    return regularActions + destructiveActions
  }

  var systemImage: String {
    switch self {
    case .copy:
      return "doc.on.doc"
    case .saveOrOpen:
      return "square.and.arrow.down"
    case .dismiss:
      return "xmark"
    case .delete:
      return "trash"
    case .edit:
      return "pencil"
    case .uploadToCloud:
      return "icloud.and.arrow.up"
    case .pinToScreen:
      return "pin"
    case .optimize:
      return "wand.and.stars"
    case .collapseToEdge:
      return "arrow.right.to.line"
    }
  }
}
