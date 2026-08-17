import Foundation
import PluginKitCore
import SnapzyPluginAPI
import SnapzyPluginMessages
import SnapzyPluginProtocol

public protocol HostCallDispatcher: Sendable {
  func call(
    pluginID: String,
    invocationID: UUID?,
    service: String,
    payload: JSONValue
  ) async throws -> JSONValue

  func progress(invocationID: UUID, fraction: Double?, message: String?) async throws
  func log(level: String, message: String, invocationID: UUID?) async throws
}

public struct CommandContext: Sendable {
  public let pluginID: String
  public let invocationID: UUID
  public let request: SnapzyCommandRequest
  private let dispatcher: any HostCallDispatcher

  public init(
    pluginID: String,
    invocationID: UUID,
    request: SnapzyCommandRequest,
    dispatcher: any HostCallDispatcher
  ) {
    self.pluginID = pluginID
    self.invocationID = invocationID
    self.request = request
    self.dispatcher = dispatcher
  }

  // MARK: - Capabilities

  public var asset: AssetFacade { AssetFacade(ctx: self) }
  public var ocr: OCRFacade { OCRFacade(ctx: self) }
  public var image: ImageFacade { ImageFacade(ctx: self) }
  public var media: MediaFacade { MediaFacade(ctx: self) }
  public var http: HTTPFacade { HTTPFacade(ctx: self) }
  public var ui: UIFacade { UIFacade(ctx: self) }
  public var clipboard: ClipboardFacade { ClipboardFacade(ctx: self) }
  public var storage: StorageFacade { StorageFacade(ctx: self) }
  public var secrets: SecretsFacade { SecretsFacade(ctx: self) }
  public var notify: NotifyFacade { NotifyFacade(ctx: self) }

  // MARK: - Internal Call Dispatch

  func callHost(service: String, payload: JSONValue) async throws -> JSONValue {
    try await dispatcher.call(
      pluginID: pluginID,
      invocationID: invocationID,
      service: service,
      payload: payload
    )
  }

  public func reportProgress(_ fraction: Double? = nil, message: String? = nil) async throws {
    try await dispatcher.progress(
      invocationID: invocationID,
      fraction: fraction,
      message: message
    )
  }

  public func progress(_ fraction: Double? = nil, message: String? = nil) async throws {
    try await reportProgress(fraction, message: message)
  }

  public func log(_ message: String, level: String = "info") async throws {
    try await dispatcher.log(level: level, message: message, invocationID: invocationID)
  }
}

// MARK: - Asset Facade

public struct AssetFacade: Sendable {
  private let ctx: CommandContext
  init(ctx: CommandContext) { self.ctx = ctx }

  public func read() async throws -> Data {
    let result = try await ctx.callHost(service: "asset.read", payload: .object([:]))
    guard let data = SnapzyPluginIPC.binaryData(result) else {
      throw SnapzyPluginError.hostCallFailed("Host did not return asset data")
    }
    return data
  }

  public func thumbnail(maxSize: Int = 512) async throws -> Data {
    let result = try await ctx.callHost(
      service: "asset.thumbnail",
      payload: .object(["maxSize": .int(maxSize)])
    )
    guard let data = SnapzyPluginIPC.binaryData(result) else {
      throw SnapzyPluginError.hostCallFailed("Host did not return thumbnail data")
    }
    return data
  }
}

// MARK: - OCR Facade

public struct OCRFacade: Sendable {
  private let ctx: CommandContext
  init(ctx: CommandContext) { self.ctx = ctx }

  public func recognize(
    _ image: Data,
    language: String? = nil,
    contentType: String? = nil,
    coordinateSize: SnapzySize? = nil
  ) async throws -> PluginOCRResult {
    let request = PluginOCRRequest(
      image: image,
      language: language,
      contentType: contentType,
      coordinateSize: coordinateSize
    )
    let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
    let resultJSON = try await ctx.callHost(service: "ocr.recognize", payload: payload)
    let data = try JSONEncoder().encode(resultJSON)
    return try JSONDecoder().decode(PluginOCRResult.self, from: data)
  }
}

// MARK: - Image Facade

public struct ImageFacade: Sendable {
  private let ctx: CommandContext
  init(ctx: CommandContext) { self.ctx = ctx }

  public func resize(_ image: Data, targetSize: SnapzySize) async throws -> Data {
    let op = PluginImageOperation(operation: "resize", image: image, targetSize: targetSize)
    return try await runImageOp(op)
  }

  public func crop(_ image: Data, rect: SnapzyRect) async throws -> Data {
    let op = PluginImageOperation(operation: "crop", image: image, cropRect: rect)
    return try await runImageOp(op)
  }

  public func encode(_ image: Data, format: String, quality: Double? = nil) async throws -> Data {
    let op = PluginImageOperation(operation: "encode", image: image, format: format, quality: quality)
    return try await runImageOp(op)
  }

  public func inspect(_ image: Data) async throws -> PluginImageResult {
    let op = PluginImageOperation(operation: "decode", image: image)
    let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(op))
    let resultJSON = try await ctx.callHost(service: "image.run", payload: payload)
    guard case .object(let dict) = resultJSON,
          let sizeVal = dict["size"] else {
      throw SnapzyPluginError.hostCallFailed("Missing image size in result")
    }
    let sizeData = try JSONEncoder().encode(sizeVal)
    let size = try JSONDecoder().decode(SnapzySize.self, from: sizeData)
    let imageBytes = dict["image"].flatMap { SnapzyPluginIPC.binaryData($0) } ?? Data()
    let format = dict["format"]?.stringValue
    return PluginImageResult(image: imageBytes, size: size, format: format)
  }

  private func runImageOp(_ op: PluginImageOperation) async throws -> Data {
    let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(op))
    let resultJSON = try await ctx.callHost(service: "image.run", payload: payload)
    guard case .object(let dict) = resultJSON,
          let imageVal = dict["image"],
          let data = SnapzyPluginIPC.binaryData(imageVal) else {
      throw SnapzyPluginError.hostCallFailed("Host did not return image data")
    }
    return data
  }
}

// MARK: - Media Facade

public struct MediaFacade: Sendable {
  private let ctx: CommandContext
  init(ctx: CommandContext) { self.ctx = ctx }

  public func duration() async throws -> Double? {
    let op = PluginMediaOperation(operation: "duration")
    let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(op))
    let resultJSON = try await ctx.callHost(service: "media.run", payload: payload)
    return resultJSON["duration"]?.doubleValue
  }

  public func frameAt(time: Double) async throws -> Data {
    let op = PluginMediaOperation(operation: "frameAt", time: time)
    let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(op))
    let resultJSON = try await ctx.callHost(service: "media.run", payload: payload)
    guard let imgVal = resultJSON["image"],
          let data = SnapzyPluginIPC.binaryData(imgVal) else {
      throw SnapzyPluginError.hostCallFailed("Host returned no video frame")
    }
    return data
  }

  public func extractAudio() async throws -> Data {
    let op = PluginMediaOperation(operation: "extractAudio")
    let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(op))
    let resultJSON = try await ctx.callHost(service: "media.run", payload: payload)
    guard let audioVal = resultJSON["audio"],
          let data = SnapzyPluginIPC.binaryData(audioVal) else {
      throw SnapzyPluginError.hostCallFailed("Host returned no audio data")
    }
    return data
  }
}

// MARK: - HTTP Facade

public struct HTTPFacade: Sendable {
  private let ctx: CommandContext
  init(ctx: CommandContext) { self.ctx = ctx }

  public func fetch(_ request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
    let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
    let resultJSON = try await ctx.callHost(service: "http.fetch", payload: payload)
    guard let status = resultJSON["status"]?.intValue else {
      throw SnapzyPluginError.hostCallFailed("Invalid HTTP response format")
    }
    var headers: [String: String] = [:]
    if let headerDict = resultJSON["headers"]?.objectValue {
      for (k, v) in headerDict {
        if let s = v.stringValue { headers[k] = s }
      }
    }
    let body = resultJSON["body"].flatMap { SnapzyPluginIPC.binaryData($0) } ?? Data()
    return PluginHTTPResponse(status: status, headers: headers, body: body)
  }

  public func fetch(
    url: String,
    method: String = "GET",
    headers: [String: String] = [:],
    body: Data? = nil
  ) async throws -> PluginHTTPResponse {
    let request = PluginHTTPRequest(url: url, method: method, headers: headers, body: body)
    return try await fetch(request)
  }

  public func fetch<T: Encodable>(
    url: String,
    method: String = "POST",
    headers: [String: String] = ["Content-Type": "application/json"],
    json: T
  ) async throws -> PluginHTTPResponse {
    let body = try JSONEncoder().encode(json)
    return try await fetch(url: url, method: method, headers: headers, body: body)
  }
}

// MARK: - UI Facade

public struct UIFacade: Sendable {
  private let ctx: CommandContext
  init(ctx: CommandContext) { self.ctx = ctx }

  public func form(_ form: PluginUIForm) async throws -> [String: JSONValue]? {
    let request = PluginUIRequest.form(form)
    let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
    let resultJSON = try await ctx.callHost(service: "ui.run", payload: payload)
    let result = try JSONDecoder().decode(PluginUIResult.self, from: try JSONEncoder().encode(resultJSON))
    switch result {
    case .submitted(let values):
      if case .object(let dict) = values { return dict }
      return [:]
    case .confirmed, .dismissed:
      return nil
    }
  }

  public func confirm(title: String, message: String) async throws -> Bool {
    let request = PluginUIRequest.confirm(title: title, message: message)
    let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
    let resultJSON = try await ctx.callHost(service: "ui.run", payload: payload)
    let result = try JSONDecoder().decode(PluginUIResult.self, from: try JSONEncoder().encode(resultJSON))
    if case .confirmed(let confirmed) = result {
      return confirmed
    }
    return false
  }

  public func showResult(title: String, text: String) async throws {
    let request = PluginUIRequest.showResult(title: title, text: text)
    let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
    _ = try await ctx.callHost(service: "ui.run", payload: payload)
  }

  public func progress(fraction: Double? = nil, message: String? = nil) async throws {
    try await ctx.reportProgress(fraction, message: message)
  }
}

// MARK: - Clipboard Facade

public struct ClipboardFacade: Sendable {
  private let ctx: CommandContext
  init(ctx: CommandContext) { self.ctx = ctx }

  public func writeText(_ text: String) async throws {
    let payload: JSONValue = .object(["text": .string(text)])
    _ = try await ctx.callHost(service: "clipboard.writeText", payload: payload)
  }

  public func writeImage(_ image: Data) async throws {
    let payload: JSONValue = .object(["image": SnapzyPluginIPC.binary(image)])
    _ = try await ctx.callHost(service: "clipboard.writeImage", payload: payload)
  }
}

// MARK: - Storage Facade

public struct StorageFacade: Sendable {
  private let ctx: CommandContext
  init(ctx: CommandContext) { self.ctx = ctx }

  public func get(_ key: String) async throws -> String? {
    let payload: JSONValue = .object(["key": .string(key)])
    let result = try await ctx.callHost(service: "storage.get", payload: payload)
    guard let valueObj = result["value"] else { return nil }
    if let data = SnapzyPluginIPC.binaryData(valueObj) {
      return String(data: data, encoding: .utf8)
    }
    return valueObj.stringValue
  }

  public func set(_ key: String, _ value: String?) async throws {
    let valJSON: JSONValue
    if let value = value, let data = value.data(using: .utf8) {
      valJSON = SnapzyPluginIPC.binary(data)
    } else {
      valJSON = .null
    }
    let payload: JSONValue = .object(["key": .string(key), "value": valJSON])
    _ = try await ctx.callHost(service: "storage.set", payload: payload)
  }

  public func getJSON<T: Decodable>(_ key: String) async throws -> T? {
    guard let string = try await get(key),
          let data = string.data(using: .utf8) else { return nil }
    return try JSONDecoder().decode(T.self, from: data)
  }

  public func setJSON<T: Encodable>(_ key: String, _ value: T?) async throws {
    if let value = value {
      let data = try JSONEncoder().encode(value)
      let str = String(data: data, encoding: .utf8)
      try await set(key, str)
    } else {
      try await set(key, nil)
    }
  }
}

// MARK: - Secrets Facade

public struct SecretsFacade: Sendable {
  private let ctx: CommandContext
  init(ctx: CommandContext) { self.ctx = ctx }

  public func get(_ name: String) async throws -> String? {
    let payload: JSONValue = .object(["name": .string(name)])
    let result = try await ctx.callHost(service: "secrets.get", payload: payload)
    return result["value"]?.stringValue
  }

  public func set(_ name: String, _ value: String?) async throws {
    let payload: JSONValue = .object([
      "name": .string(name),
      "value": value.map { .string($0) } ?? .null
    ])
    _ = try await ctx.callHost(service: "secrets.set", payload: payload)
  }
}

// MARK: - Notify Facade

public struct NotifyFacade: Sendable {
  private let ctx: CommandContext
  init(ctx: CommandContext) { self.ctx = ctx }

  public func post(title: String, body: String? = nil) async throws {
    let payload: JSONValue = .object([
      "title": .string(title),
      "body": .string(body ?? "")
    ])
    _ = try await ctx.callHost(service: "notify.post", payload: payload)
  }
}
