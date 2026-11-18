import Foundation

enum HistoryDisplayStyle: String, CaseIterable, Identifiable {
  case traditional
  case hanging

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .traditional: L10n.HistoryHanging.traditional
    case .hanging: L10n.HistoryHanging.hanging
    }
  }

  static func stored(userDefaults: UserDefaults = .standard) -> Self {
    Self(rawValue: userDefaults.string(forKey: PreferencesKeys.historyDisplayStyle) ?? "") ?? .traditional
  }
}
