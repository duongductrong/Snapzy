import AppKit
import Foundation
import SnapzyPluginAPI

/// `snapzy.ui` — declarative only: the host renders forms, confirmations, and
/// result panels from schemas. A plugin never draws; the moment a plugin could
/// draw, the sandbox would have to contain a renderer.
final class PluginUIService {
  func run(_ request: PluginUIRequest) async throws -> PluginUIResult {
    switch request {
    case .form(let form):
      return await Self.presentForm(form)
    case .confirm(let title, let message):
      let confirmed = await MainActor.run { () -> Bool in
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Confirm")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
      }
      return .confirmed(confirmed)
    case .showResult(let title, let text):
      await MainActor.run {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        }
      }
      return .dismissed
    }
  }

  /// A minimal host-rendered form: one row per field. Field kinds: string,
  /// secret, number, boolean, enum, url.
  private static func presentForm(_ form: PluginUIForm) async -> PluginUIResult {
    await MainActor.run {
      let alert = NSAlert()
      alert.messageText = form.title
      alert.informativeText = form.message ?? ""
      alert.alertStyle = .informational
      alert.addButton(withTitle: form.submitLabel ?? "Submit")
      alert.addButton(withTitle: "Cancel")

      guard !form.fields.isEmpty else {
        return alert.runModal() == .alertFirstButtonReturn ? .submitted(.object([:])) : .dismissed
      }

      let accessory = NSStackView()
      accessory.orientation = .vertical
      accessory.alignment = .leading
      accessory.spacing = 8
      accessory.frame = NSRect(x: 0, y: 0, width: 380, height: 0)

      var fields: [(field: PluginUIFormField, control: NSControl)] = []
      var height: CGFloat = 0

      for field in form.fields {
        let label = NSTextField(labelWithString: field.label)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        accessory.addArrangedSubview(label)
        height += 20

        let control: NSControl
        switch field.kind {
        case "boolean":
          let checkbox = NSButton(checkboxWithTitle: field.label, target: nil, action: nil)
          checkbox.state = (field.defaultValue == .bool(true)) ? .on : .off
          control = checkbox
          height += 26
        case "number":
          let textField = NSTextField()
          textField.placeholderString = field.defaultValue?.string ?? ""
          control = textField
          height += 26
        case "enum":
          let popup = NSPopUpButton(frame: .zero, pullsDown: false)
          popup.addItems(withTitles: field.options ?? [])
          if let defaultValue = field.defaultValue?.string, let index = popup.itemTitles.firstIndex(of: defaultValue) {
            popup.selectItem(at: index)
          }
          control = popup
          height += 26
        default:
          let textField = NSSecureTextField()
          textField.placeholderString = field.defaultValue?.string ?? ""
          if field.kind != "secret" {
            let plain = NSTextField()
            plain.placeholderString = field.defaultValue?.string ?? ""
            control = plain
          } else {
            control = textField
          }
          height += 26
        }
        control.translatesAutoresizingMaskIntoConstraints = false
        accessory.addArrangedSubview(control)
        control.widthAnchor.constraint(equalTo: accessory.widthAnchor).isActive = true
        fields.append((field, control))
      }

      accessory.setFrameSize(NSSize(width: 380, height: height + CGFloat(fields.count) * 8))
      alert.accessoryView = accessory

      let response = alert.runModal()
      guard response == .alertFirstButtonReturn else { return .dismissed }

      var values: [String: JSONValue] = [:]
      for (field, control) in fields {
        switch field.kind {
        case "boolean":
          values[field.name] = .bool((control as? NSButton)?.state == .on)
        case "number":
          let text = (control as? NSTextField)?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
          values[field.name] = text.isEmpty ? (field.defaultValue ?? .null) : .double(Double(text) ?? 0)
        case "enum":
          values[field.name] = .string((control as? NSPopUpButton)?.titleOfSelectedItem ?? "")
        default:
          let text = (control as? NSTextField)?.stringValue ?? ""
          if field.kind == "url", !text.isEmpty, URL(string: text)?.scheme == nil {
            values[field.name] = .null
          } else {
            values[field.name] = .string(text)
          }
        }
      }
      return .submitted(.object(values))
    }
  }
}
