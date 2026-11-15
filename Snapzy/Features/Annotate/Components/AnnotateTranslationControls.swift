//
//  AnnotateTranslationControls.swift
//  Snapzy
//
//  Quick-properties controls and the editor popover for a selected Auto Translate item.
//

import SwiftUI

struct QuickTranslationControl: View {
  @ObservedObject var state: AnnotateState
  let buttonWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    if let selection = state.selectedTranslation {
      QuickPropertiesGroup(title: L10n.AnnotateTranslate.translationTitle, spacing: groupSpacing) {
        HStack(spacing: 4) {
          iconButton("pencil", help: L10n.AnnotateTranslate.editTranslation, isActive: state.translationEditorID == selection.id) {
            state.translationEditorID = selection.id
          }
          .popover(isPresented: editorBinding(for: selection.id), arrowEdge: .bottom) {
            AnnotateTranslationEditor(state: state, id: selection.id)
          }

          ColorPicker(L10n.AnnotateTranslate.textColor, selection: colorBinding(id: selection.id, isText: true), supportsOpacity: false)
            .labelsHidden()
            .help(L10n.AnnotateTranslate.textColor)

          ColorPicker(L10n.AnnotateTranslate.coverColor, selection: colorBinding(id: selection.id, isText: false), supportsOpacity: false)
            .labelsHidden()
            .help(L10n.AnnotateTranslate.coverColor)
            .disabled(selection.block.cover == .none)

          coverMenu(selection.id, current: selection.block.cover)

          iconButton("textformat.size.smaller", help: L10n.AnnotateTranslate.smallerText) {
            state.setTranslationFontSize(id: selection.id, size: selection.item.properties.fontSize - 1)
          }
          Text("\(Int(selection.item.properties.fontSize.rounded()))")
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .frame(minWidth: 18)
          iconButton("textformat.size.larger", help: L10n.AnnotateTranslate.largerText) {
            state.setTranslationFontSize(id: selection.id, size: selection.item.properties.fontSize + 1)
          }

          iconButton("bold", help: L10n.AnnotateTranslate.bold, isActive: selection.block.isBold) {
            state.updateTranslation(id: selection.id, refit: true) { block, _ in block.isBold.toggle() }
          }

          alignmentMenu(selection.id, current: selection.block.alignment)

          iconButton("arrow.up.left.and.arrow.down.right", help: L10n.AnnotateTranslate.fitText,
                     isActive: false) {
            state.fitTranslationText(id: selection.id)
          }
          .disabled(!selection.block.isFontSizeManual)
          .opacity(selection.block.isFontSizeManual ? 1 : 0.4)
        }
      }
    }
  }

  private func editorBinding(for id: UUID) -> Binding<Bool> {
    Binding(
      get: { state.translationEditorID == id },
      set: { if !$0, state.translationEditorID == id { state.translationEditorID = nil } }
    )
  }

  private func colorBinding(id: UUID, isText: Bool) -> Binding<Color> {
    Binding(
      get: {
        guard let item = state.annotations.first(where: { $0.id == id }) else { return .black }
        return isText ? item.properties.strokeColor : item.properties.fillColor
      },
      set: { color in
        state.updateTranslation(id: id) { _, properties in
          if isText {
            properties.strokeColor = color
          } else {
            properties.fillColor = color
          }
        }
      }
    )
  }

  private func coverMenu(_ id: UUID, current: TranslationCoverStyle) -> some View {
    Menu {
      ForEach(TranslationCoverStyle.allCases, id: \.self) { style in
        Button {
          state.updateTranslation(id: id) { block, _ in block.cover = style }
        } label: {
          if style == current {
            Label(title(for: style), systemImage: "checkmark")
          } else {
            Text(title(for: style))
          }
        }
      }
    } label: {
      Image(systemName: icon(for: current))
        .font(.system(size: 11, weight: .semibold))
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .frame(width: buttonWidth, height: QuickPropertiesMetrics.chip)
    .liquidGlassControl(isActive: false)
    .help(L10n.AnnotateTranslate.cover)
  }

  private func alignmentMenu(_ id: UUID, current: TranslationTextAlignment) -> some View {
    let options: [(TranslationTextAlignment, String)] = [
      (.leading, "text.alignleft"), (.center, "text.aligncenter"), (.trailing, "text.alignright"),
    ]
    return Menu {
      ForEach(options, id: \.0) { option in
        Button {
          state.updateTranslation(id: id) { block, _ in block.alignment = option.0 }
        } label: {
          Label("", systemImage: option.1)
        }
      }
    } label: {
      Image(systemName: options.first { $0.0 == current }?.1 ?? "text.alignleft")
        .font(.system(size: 11, weight: .semibold))
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .frame(width: buttonWidth, height: QuickPropertiesMetrics.chip)
    .liquidGlassControl(isActive: false)
  }

  private func iconButton(
    _ symbol: String,
    help: String,
    isActive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(isActive ? .accentColor : .secondary)
        .frame(width: buttonWidth, height: QuickPropertiesMetrics.chip)
        .liquidGlassControl(isActive: isActive)
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private func title(for style: TranslationCoverStyle) -> String {
    switch style {
    case .solid: L10n.AnnotateTranslate.coverSolid
    case .frosted: L10n.AnnotateTranslate.coverFrosted
    case .none: L10n.AnnotateTranslate.coverNone
    }
  }

  private func icon(for style: TranslationCoverStyle) -> String {
    switch style {
    case .solid: "square.fill"
    case .frosted: "square.dashed.inset.filled"
    case .none: "square.dashed"
    }
  }
}

/// Edits the translated text; shows the source for reference. One undo step per session.
struct AnnotateTranslationEditor: View {
  @ObservedObject var state: AnnotateState
  let id: UUID

  @State private var draft = ""
  @State private var original = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(L10n.AnnotateTranslate.translationTitle)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
      TextEditor(text: $draft)
        .font(.system(size: 13))
        .focused($isFocused)
        .frame(minHeight: 70, maxHeight: 180)
        .scrollContentBackground(.hidden)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))

      Text(L10n.AnnotateTranslate.original)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
      ScrollView {
        Text(original)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 110)

      HStack {
        Spacer()
        Button(L10n.Common.cancel) { close() }
          .keyboardShortcut(.cancelAction)
        Button(L10n.Common.done) {
          commit()
          close()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(14)
    .frame(width: 320)
    .onAppear {
      if let item = state.annotations.first(where: { $0.id == id }),
         case .translation(let block) = item.type {
        draft = block.translatedText
        original = block.sourceText
      }
      isFocused = true
    }
  }

  private func commit() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty,
          let item = state.annotations.first(where: { $0.id == id }),
          case .translation(let block) = item.type,
          block.translatedText != text else { return }
    state.setTranslationText(id: id, text: text)
  }

  private func close() {
    state.translationEditorID = nil
  }
}
