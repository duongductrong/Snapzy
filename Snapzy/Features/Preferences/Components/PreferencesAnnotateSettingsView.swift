//
//  PreferencesAnnotateSettingsView.swift
//  Snapzy
//
//  Annotate preferences tab for editor behavior settings.
//

import SwiftUI

struct AnnotateSettingsView: View {
  private static let rememberLastToolSelection = "__remember_last_tool__"

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

  private var initialToolSelection: Binding<String> {
    Binding(
      get: {
        if annotateRememberLastTool {
          return Self.rememberLastToolSelection
        }
        return AnnotationToolType.inlineAnnotateTools.contains { $0.rawValue == annotateDefaultTool }
          ? annotateDefaultTool
          : AnnotationToolType.selection.rawValue
      },
      set: { selection in
        if selection == Self.rememberLastToolSelection {
          annotateRememberLastTool = true
        } else {
          annotateDefaultTool = selection
          annotateRememberLastTool = false
        }
      }
    )
  }

  var body: some View {
    Form {
      Section(L10n.PreferencesAnnotate.behaviorSection) {
        SettingRow(
          icon: "cursorarrow",
          title: L10n.PreferencesAnnotate.startToolTitle,
          description: L10n.PreferencesAnnotate.startToolDescription
        ) {
          Picker("", selection: initialToolSelection) {
            Label(
              L10n.PreferencesAnnotate.rememberLastToolTitle,
              systemImage: "clock.arrow.circlepath"
            )
            .tag(Self.rememberLastToolSelection)

            Divider()

            ForEach(AnnotationToolType.inlineAnnotateTools) { tool in
              Label(tool.displayName, systemImage: tool.icon).tag(tool.rawValue)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .fixedSize()
          .frame(width: 180, alignment: .trailing)
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
