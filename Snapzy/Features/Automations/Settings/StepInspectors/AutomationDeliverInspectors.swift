//
//  AutomationDeliverInspectors.swift
//  Snapzy
//
//  Settings for deliver steps: link format, text template, save to folder
//  (with a preview of the resolved file name).
//

import SwiftUI

struct LinkTemplateInspector: View {
  @Binding var template: AutomationLinkTemplate

  var body: some View {
    Section {
      Picker(L10n.Automations.linkFormatLabel, selection: $template.style) {
        ForEach(AutomationLinkStyle.allCases) { style in
          Text(style.displayName).tag(style)
        }
      }
      if template.style == .custom {
        HStack {
          TextField(L10n.Automations.templateLabel, text: $template.custom, prompt: Text("<{link}>"))
            .font(.system(.body, design: .monospaced))
          AutomationTokenHelpButton()
        }
      }
      LabeledContent(L10n.Automations.previewLabel) {
        Text(AutomationTemplatePreview.link(template))
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .textSelection(.enabled)
      }
    }
  }
}

struct TextTemplateInspector: View {
  @Binding var template: AutomationTextTemplate

  var body: some View {
    Section {
      HStack(alignment: .top) {
        TextField(L10n.Automations.templateLabel, text: $template.template, axis: .vertical)
          .font(.system(.body, design: .monospaced))
          .lineLimit(1...4)
        AutomationTokenHelpButton()
      }
      LabeledContent(L10n.Automations.previewLabel) {
        Text(AutomationTemplatePreview.sample.render(template.template))
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
    } footer: {
      Text(L10n.Automations.textTemplateFooter)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct SaveToFolderInspector: View {
  @Binding var config: AutomationSaveToFolderConfig

  var body: some View {
    Section {
      LabeledContent(L10n.Automations.folderLabel) {
        HStack(spacing: 8) {
          Text(folderDescription)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(config.folder == nil ? .orange : .secondary)
          Menu(L10n.Automations.chooseFolderButton) {
            Button(L10n.Automations.folderExport) {
              config.folder = .exportDirectory
              config.folderPath = nil
            }
            Button(L10n.Automations.chooseFolderMenuItem) { chooseFolder() }
          }
          .fixedSize()
        }
      }
      HStack {
        TextField(L10n.Automations.nameTemplateLabel, text: $config.nameTemplate, prompt: Text("{date}-{appName}"))
          .font(.system(.body, design: .monospaced))
        AutomationTokenHelpButton()
      }
      Picker(L10n.Automations.conflictLabel, selection: $config.conflict) {
        Text(L10n.Automations.conflictUniquify).tag(AutomationConflictPolicy.uniquify)
        Text(L10n.Automations.conflictOverwrite).tag(AutomationConflictPolicy.overwrite)
      }
      LabeledContent(L10n.Automations.previewLabel) {
        Text(namePreview)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }

  private var folderDescription: String {
    guard let folder = config.folder else { return L10n.Automations.issueFolder }
    if folder == .exportDirectory { return L10n.Automations.folderExport }
    let path = AutomationFolderAccessStore.shared.path(for: folder) ?? config.folderPath ?? ""
    return (path as NSString).abbreviatingWithTildeInPath
  }

  private var namePreview: String {
    let rendered = CaptureOutputNaming.sanitizedBaseName(AutomationTemplatePreview.sample.render(config.nameTemplate))
    return (rendered.isEmpty ? "Snapzy_shot" : rendered) + ".png"
  }

  private func chooseFolder() {
    let start = config.folder.flatMap { AutomationFolderAccessStore.shared.resolve($0) }
    guard let picked = AutomationFolderAccessStore.shared.chooseFolder(startingAt: start) else { return }
    config.folder = picked.ref
    config.folderPath = picked.path
  }
}

/// Sample values so template previews show something meaningful.
@MainActor
enum AutomationTemplatePreview {
  static var sample: AutomationVariables {
    let date = Date()
    var values = CaptureOutputNaming.tokenValues(
      kind: .screenshot,
      date: date,
      context: CaptureContext(appName: "Safari", windowTitle: "Snapzy")
    )
    values["{automation}"] = "Docs Shot"
    values["{link}"] = "https://cdn.example.com/Snapzy_shot.png"
    values["{text}"] = L10n.Automations.previewSampleText
    values["{file.name}"] = "Snapzy_shot.png"
    values["{file.basename}"] = "Snapzy_shot"
    values["{file.ext}"] = "png"
    values["{file.path}"] = "/Users/me/Desktop/Snapzy_shot.png"
    values["{width}"] = "1600"
    values["{height}"] = "1000"
    values["{saved.path}"] = "/Users/me/repo/docs/img/Snapzy_shot.png"
    values["{saved.relativePath}"] = "img/Snapzy_shot.png"
    values["{saved.relativeURL}"] = "img/Snapzy_shot.png"
    return AutomationVariables(values: values)
  }

  static func link(_ template: AutomationLinkTemplate) -> String {
    switch template.style {
    case .url: "https://cdn.example.com/Snapzy_shot.png"
    case .markdown: "![Snapzy_shot](https://cdn.example.com/Snapzy_shot.png)"
    case .html, .bbcode, .custom: sample.render(template.template, escape: template.escape)
    }
  }
}
