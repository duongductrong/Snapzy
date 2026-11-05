//
//  CloudShareLinkStyle.swift
//  Snapzy
//
//  How new S3 and R2 uploads are named, which is what a share link shows
//

import Foundation

nonisolated enum CloudShareLinkStyle: String, CaseIterable, Identifiable {
  case descriptive
  case short

  static let defaultStyle: CloudShareLinkStyle = .descriptive

  var id: String { rawValue }

  static func stored(userDefaults: UserDefaults = .standard) -> CloudShareLinkStyle {
    CloudShareLinkStyle(
      rawValue: userDefaults.string(forKey: PreferencesKeys.cloudShareLinkStyle) ?? ""
    ) ?? .defaultStyle
  }

  var displayName: String {
    switch self {
    case .descriptive: return L10n.CloudSettings.shareLinkStyleDescriptive
    case .short: return L10n.CloudSettings.shareLinkStyleShort
    }
  }
}
