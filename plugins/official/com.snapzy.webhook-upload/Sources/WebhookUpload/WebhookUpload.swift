import Foundation
import SnapzyPluginAPI
import SnapzyPluginSDK

@main
struct WebhookUploadPlugin: SnapzyPlugin {
  static let webhookSecretKey = "webhookURL"
  static let boundary = "snapzy-boundary-7c1f"

  init() {}

  func activate(_ context: SnapzyPluginContext) async throws {
    context.command("upload") { request, ctx in
      guard let webhook = try await resolveWebhook(ctx) else {
        return .failed("Add your Discord webhook URL to use this command.")
      }

      let bytes = try await ctx.asset.read()
      let name = fileName(request.documentKind)
      let message = request.options["message"]?.stringValue ?? ""

      var body = Data()
      if !message.isEmpty {
        body.append(Data("--\(Self.boundary)\r\nContent-Disposition: form-data; name=\"content\"\r\n\r\n\(message)\r\n".utf8))
      }
      body.append(Data("--\(Self.boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
      body.append(bytes)
      body.append(Data("\r\n--\(Self.boundary)--\r\n".utf8))

      let response = try await ctx.http.fetch(
        url: "\(webhook)?wait=true",
        method: "POST",
        headers: ["Content-Type": "multipart/form-data; boundary=\(Self.boundary)"],
        body: body
      )

      guard response.status == 200 || response.status == 204 else {
        let snippet = String(data: response.body.prefix(200), encoding: .utf8) ?? ""
        return .failed("Discord answered \(response.status): \(snippet)")
      }

      if let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
         let attachments = json["attachments"] as? [[String: Any]],
         let firstURL = attachments.first?["url"] as? String {
        return .url(firstURL)
      }

      return .failed("Discord accepted the upload but returned no link.")
    }
  }

  private func resolveWebhook(_ ctx: CommandContext) async throws -> String? {
    if let stored = try await ctx.secrets.get(Self.webhookSecretKey), !stored.isEmpty {
      return stored
    }

    let form = PluginUIForm(
      title: "Discord webhook",
      message: "Anyone with this URL can post to your channel, so it is kept in the Keychain rather than in settings.",
      fields: [
        PluginUIFormField(
          name: "webhook",
          label: "Webhook URL",
          kind: "secret",
          required: true
        )
      ],
      submitLabel: "Save"
    )

    guard let submitted = try await ctx.ui.form(form),
          let val = submitted["webhook"]?.stringValue,
          val.hasPrefix("https://") else {
      return nil
    }

    try await ctx.secrets.set(Self.webhookSecretKey, val)
    return val
  }

  private func fileName(_ kind: SnapzyDocumentKind?) -> String {
    switch kind {
    case .video: return "snapzy.mp4"
    case .gif: return "snapzy.gif"
    default: return "snapzy.png"
    }
  }
}
