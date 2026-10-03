//
//  AnnotateColorPaletteStore.swift
//  Snapzy
//
//  Persistence for user-defined Annotate colors and quick favorites.
//

import Combine
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum AnnotateColorPaletteRole: String, CaseIterable, Codable {
  case canvasBackground
  case annotationStroke
  case annotationFill
  case textBackground
}

nonisolated struct AnnotateColorDragPayload: Codable {
  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double
  let sourceFavoriteRole: AnnotateColorPaletteRole?

  private static let plainTextMarker = "com.snapzy.annotate-color"

  init?(color: Color, sourceFavoriteRole: AnnotateColorPaletteRole? = nil) {
    guard let value = RGBAColor(color: color) else { return nil }
    red = value.red
    green = value.green
    blue = value.blue
    alpha = value.alpha
    self.sourceFavoriteRole = sourceFavoriteRole
  }

  var color: Color {
    RGBAColor(red: red, green: green, blue: blue, alpha: alpha).color
  }

  static let supportedContentTypes: [UTType] = [.plainText]

  var encodedPlainText: String {
    guard let data = try? JSONEncoder().encode(self) else {
      return Self.plainTextMarker
    }
    return "\(Self.plainTextMarker)|\(data.base64EncodedString())"
  }

  static func itemProvider(
    color: Color,
    sourceFavoriteRole: AnnotateColorPaletteRole?
  ) -> NSItemProvider {
    guard let payload = AnnotateColorDragPayload(
      color: color,
      sourceFavoriteRole: sourceFavoriteRole
    ) else { return NSItemProvider() }

    return NSItemProvider(object: payload.encodedPlainText as NSString)
  }

  static func load(
    from providers: [NSItemProvider],
    completion: @escaping (AnnotateColorDragPayload?) -> Void
  ) -> Bool {
    guard let provider = providers.first(where: {
      $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
    }) else {
      return false
    }

    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
      let text: String?
      if let data = item as? Data {
        text = String(data: data, encoding: .utf8)
      } else if let string = item as? String {
        text = string
      } else if let string = item as? NSString {
        text = string as String
      } else {
        text = nil
      }

      let payload = text.flatMap(parsePlainText(_:))
      DispatchQueue.main.async {
        completion(payload)
      }
    }

    return true
  }

  nonisolated static func parsePlainText(_ text: String) -> AnnotateColorDragPayload? {
    let parts = text.split(separator: "|", maxSplits: 1).map(String.init)
    guard parts.count == 2,
          parts[0] == plainTextMarker,
          let data = Data(base64Encoded: parts[1])
    else { return nil }

    return try? JSONDecoder().decode(Self.self, from: data)
  }
}

@MainActor
final class AnnotateColorPaletteStore: ObservableObject {
  static let shared = AnnotateColorPaletteStore()
  static let maximumCustomColorCount = 24
  static let maximumFavoriteColorCount = 4

  @Published private(set) var customColors: [Color]
  @Published private var favoriteColorBuckets: [AnnotateColorPaletteRole: [Color]]

  private let defaults: UserDefaults
  private let encoder = JSONEncoder()
  private var storedColors: [RGBAColor]
  private var storedFavoriteColors: [AnnotateColorPaletteRole: [RGBAColor]]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let decoder = JSONDecoder()
    storedColors = Self.loadStoredColors(from: defaults, decoder: decoder)
    storedFavoriteColors = Self.loadStoredFavoriteColors(from: defaults, decoder: decoder)
    customColors = storedColors.map(\.color)
    favoriteColorBuckets = Self.colorBuckets(from: storedFavoriteColors)
    encoder.outputFormatting = []
  }

  /// Test-visible normalized values backing the published SwiftUI colors.
  var customColorValues: [RGBAColor] {
    storedColors
  }

  /// Test-visible normalized values backing the quick favorites.
  var favoriteColorValues: [AnnotateColorPaletteRole: [RGBAColor]] {
    storedFavoriteColors
  }

  func addColor(_ color: Color) {
    guard let value = Self.rgbaColor(for: color),
          value.alpha > 0.001 else { return }

    guard !storedColors.contains(where: { Self.matches($0, value) }) else { return }

    var nextValues = storedColors
    nextValues.append(value)
    if nextValues.count > Self.maximumCustomColorCount {
      nextValues = Array(nextValues.suffix(Self.maximumCustomColorCount))
    }

    commitCustomColors(nextValues)
  }

  func removeColor(_ color: Color) {
    guard let value = Self.rgbaColor(for: color) else { return }
    commitCustomColors(storedColors.filter { !Self.matches($0, value) })
    removeFavoriteValueFromAllRoles(value)
  }

  func contains(_ color: Color) -> Bool {
    guard let value = Self.rgbaColor(for: color) else { return false }
    return storedColors.contains { Self.matches($0, value) }
  }

  func favoriteColors(for role: AnnotateColorPaletteRole) -> [Color] {
    favoriteColorBuckets[role] ?? []
  }

  func addFavorite(_ color: Color, for role: AnnotateColorPaletteRole) {
    guard let value = Self.rgbaColor(for: color) else { return }
    addFavoriteValue(value, for: role)
  }

  func removeFavorite(_ color: Color, for role: AnnotateColorPaletteRole) {
    guard let value = Self.rgbaColor(for: color) else { return }

    let nextValues = storedFavoriteColors[role, default: []].filter { !Self.matches($0, value) }
    commitFavoriteColors(nextValues, for: role)
  }

  func toggleFavorite(_ color: Color, for role: AnnotateColorPaletteRole) {
    if isFavorite(color, for: role) {
      removeFavorite(color, for: role)
    } else {
      addFavorite(color, for: role)
    }
  }

  func isFavorite(_ color: Color, for role: AnnotateColorPaletteRole) -> Bool {
    guard let value = Self.rgbaColor(for: color) else { return false }
    return storedFavoriteColors[role, default: []].contains { Self.matches($0, value) }
  }

  func acceptFavoriteDrop(
    _ payload: AnnotateColorDragPayload,
    for role: AnnotateColorPaletteRole
  ) {
    guard let value = Self.rgbaColor(for: payload.color) else { return }

    if payload.sourceFavoriteRole == role {
      moveFavoriteValueToEnd(value, for: role)
    } else {
      addFavoriteValue(value, for: role)
    }
  }

  func acceptFavoriteDrop(
    _ payload: AnnotateColorDragPayload,
    for role: AnnotateColorPaletteRole,
    targetColor: Color
  ) {
    guard let sourceValue = Self.rgbaColor(for: payload.color),
          let targetValue = Self.rgbaColor(for: targetColor)
    else { return }

    if payload.sourceFavoriteRole == role {
      swapFavoriteValues(sourceValue, with: targetValue, for: role)
    } else {
      addFavoriteValue(sourceValue, for: role)
    }
  }

  static func colorsMatch(_ lhs: Color?, _ rhs: Color?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
      return true
    case let (.some(lhs), .some(rhs)):
      guard let lhsValue = rgbaColor(for: lhs),
            let rhsValue = rgbaColor(for: rhs)
      else {
        return lhs == rhs
      }
      return matches(lhsValue, rhsValue)
    default:
      return false
    }
  }

  static func isClear(_ color: Color) -> Bool {
    guard let value = rgbaColor(for: color) else {
      return color == .clear
    }
    return value.alpha <= 0.001
  }

  private func commitCustomColors(_ values: [RGBAColor]) {
    storedColors = Self.sanitized(values, maximumCount: Self.maximumCustomColorCount, allowsClear: false)
    customColors = storedColors.map(\.color)

    do {
      let data = try encoder.encode(storedColors)
      defaults.set(data, forKey: PreferencesKeys.annotateCustomColors)
    } catch {
      print("Failed to save annotate custom colors: \(error.localizedDescription)")
    }
  }

  private func commitFavoriteColors(
    _ values: [RGBAColor],
    for role: AnnotateColorPaletteRole
  ) {
    let sanitizedValues = Self.sanitized(
      values,
      maximumCount: Self.maximumFavoriteColorCount,
      allowsClear: true
    )

    guard storedFavoriteColors[role, default: []] != sanitizedValues else { return }

    if sanitizedValues.isEmpty {
      storedFavoriteColors.removeValue(forKey: role)
    } else {
      storedFavoriteColors[role] = sanitizedValues
    }

    favoriteColorBuckets = Self.colorBuckets(from: storedFavoriteColors)
    persistFavoriteColors()
  }

  private func addFavoriteValue(_ value: RGBAColor, for role: AnnotateColorPaletteRole) {
    var nextValues = storedFavoriteColors[role, default: []]
    guard !nextValues.contains(where: { Self.matches($0, value) }) else { return }
    guard nextValues.count < Self.maximumFavoriteColorCount else { return }

    nextValues.append(value)
    commitFavoriteColors(nextValues, for: role)
  }

  private func moveFavoriteValueToEnd(_ value: RGBAColor, for role: AnnotateColorPaletteRole) {
    var nextValues = storedFavoriteColors[role, default: []]

    guard let sourceIndex = nextValues.firstIndex(where: { Self.matches($0, value) }) else {
      addFavoriteValue(value, for: role)
      return
    }
    guard sourceIndex != nextValues.indices.last else { return }

    let movedValue = nextValues.remove(at: sourceIndex)
    nextValues.append(movedValue)
    commitFavoriteColors(nextValues, for: role)
  }

  private func swapFavoriteValues(
    _ sourceValue: RGBAColor,
    with targetValue: RGBAColor,
    for role: AnnotateColorPaletteRole
  ) {
    var nextValues = storedFavoriteColors[role, default: []]

    guard let sourceIndex = nextValues.firstIndex(where: { Self.matches($0, sourceValue) }),
          let targetIndex = nextValues.firstIndex(where: { Self.matches($0, targetValue) }),
          sourceIndex != targetIndex
    else { return }

    nextValues.swapAt(sourceIndex, targetIndex)
    commitFavoriteColors(nextValues, for: role)
  }

  private func removeFavoriteValueFromAllRoles(_ value: RGBAColor) {
    var didChange = false

    for role in AnnotateColorPaletteRole.allCases {
      let currentValues = storedFavoriteColors[role, default: []]
      let nextValues = currentValues.filter { !Self.matches($0, value) }

      guard nextValues.count != currentValues.count else { continue }
      didChange = true

      if nextValues.isEmpty {
        storedFavoriteColors.removeValue(forKey: role)
      } else {
        storedFavoriteColors[role] = nextValues
      }
    }

    guard didChange else { return }
    favoriteColorBuckets = Self.colorBuckets(from: storedFavoriteColors)
    persistFavoriteColors()
  }

  private func persistFavoriteColors() {
    let encodableValues = Dictionary(
      uniqueKeysWithValues: storedFavoriteColors.map { role, values in
        (role.rawValue, values)
      }
    )

    do {
      let data = try encoder.encode(encodableValues)
      defaults.set(data, forKey: PreferencesKeys.annotateFavoriteColors)
    } catch {
      print("Failed to save annotate favorite colors: \(error.localizedDescription)")
    }
  }

  private static func loadStoredColors(
    from defaults: UserDefaults,
    decoder: JSONDecoder
  ) -> [RGBAColor] {
    guard let data = defaults.data(forKey: PreferencesKeys.annotateCustomColors) else {
      return []
    }

    do {
      let decoded = try decoder.decode([RGBAColor].self, from: data)
      return sanitized(decoded, maximumCount: maximumCustomColorCount, allowsClear: false)
    } catch {
      defaults.removeObject(forKey: PreferencesKeys.annotateCustomColors)
      return []
    }
  }

  private static func loadStoredFavoriteColors(
    from defaults: UserDefaults,
    decoder: JSONDecoder
  ) -> [AnnotateColorPaletteRole: [RGBAColor]] {
    guard let data = defaults.data(forKey: PreferencesKeys.annotateFavoriteColors) else {
      return [:]
    }

    do {
      let decoded = try decoder.decode([String: [RGBAColor]].self, from: data)
      var result: [AnnotateColorPaletteRole: [RGBAColor]] = [:]

      for role in AnnotateColorPaletteRole.allCases {
        guard let values = decoded[role.rawValue] else { continue }
        let sanitizedValues = sanitized(
          values,
          maximumCount: maximumFavoriteColorCount,
          allowsClear: true
        )
        if !sanitizedValues.isEmpty {
          result[role] = sanitizedValues
        }
      }

      return result
    } catch {
      defaults.removeObject(forKey: PreferencesKeys.annotateFavoriteColors)
      return [:]
    }
  }

  private static func colorBuckets(
    from storedValues: [AnnotateColorPaletteRole: [RGBAColor]]
  ) -> [AnnotateColorPaletteRole: [Color]] {
    Dictionary(
      uniqueKeysWithValues: storedValues.map { role, values in
        (role, values.map(\.color))
      }
    )
  }

  private static func sanitized(
    _ values: [RGBAColor],
    maximumCount: Int,
    allowsClear: Bool
  ) -> [RGBAColor] {
    var result: [RGBAColor] = []

    for value in values where allowsClear || value.alpha > 0.001 {
      guard !result.contains(where: { matches($0, value) }) else { continue }
      result.append(value)
      if result.count == maximumCount {
        break
      }
    }

    return result
  }

  private static func rgbaColor(for color: Color) -> RGBAColor? {
    RGBAColor(color: color)
  }

  private static func matches(_ lhs: RGBAColor, _ rhs: RGBAColor) -> Bool {
    abs(lhs.red - rhs.red) < 0.001
      && abs(lhs.green - rhs.green) < 0.001
      && abs(lhs.blue - rhs.blue) < 0.001
      && abs(lhs.alpha - rhs.alpha) < 0.001
  }
}

private struct AnnotateColorDraggableModifier: ViewModifier {
  let color: Color
  let sourceFavoriteRole: AnnotateColorPaletteRole?

  func body(content: Content) -> some View {
    content.onDrag {
      AnnotateColorDragPayload.itemProvider(
        color: color,
        sourceFavoriteRole: sourceFavoriteRole
      )
    }
  }
}

extension View {
  func annotateColorDraggable(
    _ color: Color,
    sourceFavoriteRole: AnnotateColorPaletteRole? = nil
  ) -> some View {
    modifier(
      AnnotateColorDraggableModifier(
        color: color,
        sourceFavoriteRole: sourceFavoriteRole
      )
    )
  }
}
