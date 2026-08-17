import Foundation

/// The edit operations a plugin can emit against a projected document.
public enum DocumentEditKind: String, Codable, Sendable, CaseIterable {
  case addItem
  case updateItem
  case removeItem
  case setCrop
}

/// One structured edit. The host validates every edit and applies the accepted
/// set as **one** undo group.
public enum DocumentEdit: Codable, Sendable, Hashable {
  case addItem(AnnotateDocItem)
  case updateItem(id: String, patch: AnnotateDocItemPatch)
  case removeItem(id: String)
  case setCrop(SnapzyRect)
  // .addCaption(start:end:text:) lands with the host caption track (vnext).

  public var kind: DocumentEditKind {
    switch self {
    case .addItem: return .addItem
    case .updateItem: return .updateItem
    case .removeItem: return .removeItem
    case .setCrop: return .setCrop
    }
  }

  private enum CodingKeys: String, CodingKey {
    case kind, item, id, patch, crop
  }

  private enum Kind: String, Codable {
    case addItem, updateItem, removeItem, setCrop
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let kind = try container.decodeIfPresent(Kind.self, forKey: .kind) else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: container, debugDescription: "Missing DocumentEdit kind."
      )
    }
    switch kind {
    case .addItem:
      self = .addItem(try container.decode(AnnotateDocItem.self, forKey: .item))
    case .updateItem:
      self = .updateItem(
        id: try container.decode(String.self, forKey: .id),
        patch: try container.decode(AnnotateDocItemPatch.self, forKey: .patch)
      )
    case .removeItem:
      self = .removeItem(id: try container.decode(String.self, forKey: .id))
    case .setCrop:
      self = .setCrop(try container.decode(SnapzyRect.self, forKey: .crop))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .addItem(let item):
      try container.encode(Kind.addItem, forKey: .kind)
      try container.encode(item, forKey: .item)
    case .updateItem(let id, let patch):
      try container.encode(Kind.updateItem, forKey: .kind)
      try container.encode(id, forKey: .id)
      try container.encode(patch, forKey: .patch)
    case .removeItem(let id):
      try container.encode(Kind.removeItem, forKey: .kind)
      try container.encode(id, forKey: .id)
    case .setCrop(let crop):
      try container.encode(Kind.setCrop, forKey: .kind)
      try container.encode(crop, forKey: .crop)
    }
  }
}

/// A partial update to one projected item. All fields optional.
public struct AnnotateDocItemPatch: Codable, Sendable, Hashable {
  public var rect: SnapzyRect?
  public var text: String?
  public var style: AnnotateDocStyle?
  public var zIndex: Int?

  public init(
    rect: SnapzyRect? = nil,
    text: String? = nil,
    style: AnnotateDocStyle? = nil,
    zIndex: Int? = nil
  ) {
    self.rect = rect
    self.text = text
    self.style = style
    self.zIndex = zIndex
  }
}
