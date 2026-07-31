//
//  PreferencesAnnotateSettingsView.swift
//  Snapzy
//
//  Annotate preferences tab for editor behavior settings.
//

import SwiftUI

struct AnnotateSettingsView: View {
  @AppStorage(PreferencesKeys.annotateClipboardImageOpenBehavior)
  private var annotateClipboardImageOpenBehavior = AnnotateClipboardImageBehavior.ask.rawValue
  @AppStorage(PreferencesKeys.annotateDefaultTool)
  private var annotateDefaultTool = AnnotationToolType.selection.rawValue
  @AppStorage(PreferencesKeys.annotateRememberLastTool)
  private var annotateRememberLastTool = false
  @AppStorage(PreferencesKeys.annotateCloseAfterDrag) private var annotateCloseAfterDrag = true
  @AppStorage(PreferencesKeys.annotateBringForwardAfterDrag)
  private var annotateBringForwardAfterDrag = false
  @AppStorage(PreferencesKeys.annotateQuickPropertiesSyncEnabled)
  private var annotateQuickPropertiesSyncEnabled = true
  @AppStorage(PreferencesKeys.annotateCombineSaveAsEdit)
  private var annotateCombineSaveAsEdit = true
  @AppStorage(PreferencesKeys.annotateCropSnapToEdgesEnabled)
  private var annotateCropSnapToEdgesEnabled = true

  var body: some View {
    Form {
      Section(L10n.PreferencesAnnotate.behaviorSection) {
        SettingRow(
          icon: "cursorarrow",
          title: L10n.PreferencesAnnotate.defaultToolTitle,
          description: L10n.PreferencesAnnotate.defaultToolDescription
        ) {
          Picker("", selection: $annotateDefaultTool) {
            ForEach(AnnotationToolType.inlineAnnotateTools) { tool in
              Label(tool.displayName, systemImage: tool.icon).tag(tool.rawValue)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .fixedSize()
          .frame(width: 180, alignment: .trailing)
        }
        .disabled(annotateRememberLastTool)
        .opacity(annotateRememberLastTool ? 0.5 : 1)

        SettingRow(
          icon: "clock.arrow.circlepath",
          title: L10n.PreferencesAnnotate.rememberLastToolTitle,
          description: L10n.PreferencesAnnotate.rememberLastToolDescription
        ) {
          Toggle("", isOn: $annotateRememberLastTool)
            .labelsHidden()
        }

        SettingRow(
          icon: "slider.horizontal.3",
          title: L10n.PreferencesAnnotate.quickPropertiesSyncTitle,
          description: L10n.PreferencesAnnotate.quickPropertiesSyncDescription
        ) {
          Toggle("", isOn: $annotateQuickPropertiesSyncEnabled)
            .labelsHidden()
        }

        SettingRow(
          icon: "rectangle.stack",
          title: L10n.PreferencesAnnotate.combineSaveAsEditTitle,
          description: L10n.PreferencesAnnotate.combineSaveAsEditDescription
        ) {
          Toggle("", isOn: $annotateCombineSaveAsEdit)
            .labelsHidden()
        }

        SettingRow(
          icon: CropToolbarSymbols.snapToEdges,
          title: L10n.AnnotateUI.cropSnapToEdges,
          description: L10n.AnnotateUI.cropSnapToEdgesDescription
        ) {
          Toggle("", isOn: $annotateCropSnapToEdgesEnabled)
            .labelsHidden()
        }

        SettingRow(
          icon: "doc.on.clipboard",
          title: L10n.PreferencesAnnotate.clipboardTitle,
          description: L10n.PreferencesAnnotate.clipboardDescription
        ) {
          Picker("", selection: $annotateClipboardImageOpenBehavior) {
            ForEach(AnnotateClipboardImageBehavior.allCases) { behavior in
              Text(behavior.displayName).tag(behavior.rawValue)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .fixedSize()
          .frame(width: 180, alignment: .trailing)
        }

        SettingRow(
          icon: "arrow.up.forward.app",
          title: L10n.PreferencesAnnotate.closeAfterDragTitle,
          description: L10n.PreferencesAnnotate.closeAfterDragDescription
        ) {
          Toggle("", isOn: $annotateCloseAfterDrag)
            .labelsHidden()
        }

        SettingRow(
          icon: "macwindow",
          title: L10n.PreferencesAnnotate.bringForwardAfterDragTitle,
          description: L10n.PreferencesAnnotate.bringForwardAfterDragDescription
        ) {
          Toggle("", isOn: $annotateBringForwardAfterDrag)
            .labelsHidden()
        }
        .disabled(annotateCloseAfterDrag)
      }
    }
    .formStyle(.grouped)
  }
}

#Preview {
  AnnotateSettingsView()
    .frame(width: 600, height: 550)
}
