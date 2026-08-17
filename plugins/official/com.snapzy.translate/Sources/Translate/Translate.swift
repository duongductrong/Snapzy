import Foundation
import SnapzyPluginAPI
import SnapzyPluginSDK

@main
struct TranslatePlugin: SnapzyPlugin {
  static let apiKeySecret = "apiKey"
  static let batchSize = 24

  struct Options {
    let endpoint: String
    let model: String
    let targetLanguage: String
    let style: String
    let minimumConfidence: Double
  }

  init() {}

  func activate(_ context: SnapzyPluginContext) async throws {
    context.command("translate") { request, ctx in
      let options = readOptions(request.options)
      var annotateDoc: AnnotateDocument?
      if case .annotate(let doc) = request.document {
        annotateDoc = doc
      }

      guard let apiKey = try await resolveAPIKey(ctx) else {
        return .failed("Translate needs an API key. Add one in Settings › Plugins › Translate.")
      }

      try await ctx.progress(0.05, message: "Reading the image…")
      let image = try await ctx.asset.read()

      try await ctx.progress(0.15, message: "Finding text…")
      let ocrResult = try await ctx.ocr.recognize(
        image,
        coordinateSize: annotateDoc?.size
      )

      let usable = inReadingOrder(ocrResult.lines).filter {
        $0.confidence >= options.minimumConfidence && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }

      guard !usable.isEmpty else {
        return .failed("No text was found in this image.")
      }

      var translations: [String] = []
      for start in stride(from: 0, to: usable.count, by: Self.batchSize) {
        let end = min(start + Self.batchSize, usable.count)
        let batch = Array(usable[start..<end])
        let progressFraction = 0.2 + (0.7 * Double(start) / Double(usable.count))
        try await ctx.progress(progressFraction, message: "Translating \(start + 1)–\(end) of \(usable.count)…")
        let batchTranslations = try await translate(ctx, lines: batch, options: options, apiKey: apiKey)
        translations.append(contentsOf: batchTranslations)
      }

      try await ctx.progress(0.95, message: "Placing translations…")

      // If no annotate document to write into, return plain text
      guard let annotateDoc else {
        let textLines = usable.enumerated().map { idx, line in
          idx < translations.count ? translations[idx] : line.text
        }.joined(separator: "\n")
        return .text(textLines)
      }

      let existingIDs = Set(annotateDoc.items.map(\.id))
      var edits: [DocumentEdit] = []
      for (index, line) in usable.enumerated() {
        let translation = index < translations.count ? translations[index] : line.text
        let itemId = stableID(line.text)
        guard !existingIDs.contains(itemId) else { continue }

        let item = textItem(
          id: itemId,
          rect: line.box,
          text: translation
        )
        edits.append(addItem(item))
      }

      return .patch(edits)
    }
  }

  private func resolveAPIKey(_ ctx: CommandContext) async throws -> String? {
    if let stored = try await ctx.secrets.get(Self.apiKeySecret), !stored.isEmpty {
      return stored
    }
    return nil
  }

  private func readOptions(_ json: JSONValue) -> Options {
    let endpoint = json["endpoint"]?.stringValue ?? "https://api.openai.com/v1/chat/completions"
    let model = json["model"]?.stringValue ?? "gpt-4o-mini"
    let target = json["targetLanguage"]?.stringValue ?? "English"
    let style = json["style"]?.stringValue ?? "overlay"
    let confidence = json["minimumConfidence"]?.doubleValue ?? 0.3
    return Options(
      endpoint: endpoint,
      model: model,
      targetLanguage: target,
      style: style,
      minimumConfidence: confidence
    )
  }

  private func translate(
    _ ctx: CommandContext,
    lines: [PluginOCRLine],
    options: Options,
    apiKey: String
  ) async throws -> [String] {
    let sourceTexts = lines.map(\.text)
    let prompt = "Translate the following JSON array of text strings to \(options.targetLanguage). Return ONLY a JSON array of translated strings with the exact same length.\n\n\(sourceTexts)"

    let reqBody: [String: Any] = [
      "model": options.model,
      "messages": [
        ["role": "system", "content": "You are a professional translator. Respond only with valid JSON."],
        ["role": "user", "content": prompt]
      ],
      "temperature": 0.3
    ]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: reqBody) else {
      return sourceTexts
    }

    let response = try await ctx.http.fetch(
      url: options.endpoint,
      method: "POST",
      headers: [
        "Content-Type": "application/json",
        "Authorization": "Bearer \(apiKey)"
      ],
      body: jsonData
    )

    guard response.status == 200,
          let respJSON = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
          let choices = respJSON["choices"] as? [[String: Any]],
          let firstChoice = choices.first,
          let msg = firstChoice["message"] as? [String: Any],
          let content = msg["content"] as? String,
          let parsedData = content.data(using: String.Encoding.utf8),
          let parsedArray = try? JSONSerialization.jsonObject(with: parsedData) as? [String] else {
      return sourceTexts
    }

    return parsedArray
  }
}
