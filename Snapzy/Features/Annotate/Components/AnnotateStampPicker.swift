//
//  AnnotateStampPicker.swift
//  Snapzy
//
//  Stamp picker popover (stickers, emoji with search and recents, image files) and the
//  quick-properties controls shared by the Annotate window and the inline overlay.
//

import AppKit
import SwiftUI

// MARK: - Thumbnails

/// Renders a stamp through the same renderer the canvas and exports use.
enum AnnotateStampThumbnail {
  private static let cache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 200
    return cache
  }()

  static func image(for content: StampContent, height: CGFloat, isStickerStyle: Bool = true) -> NSImage {
    let width = (height * content.aspectRatio).rounded(.up)
    let key: String
    switch content {
    case .sticker(let sticker): key = "sticker|\(sticker.rawValue)"
    case .emoji(let emoji): key = "emoji|\(emoji)"
    case .image(let image): key = "image|\(image.id.uuidString)"
    }
    let cacheKey = "\(key)|\(height)|\(isStickerStyle)" as NSString
    if let cached = cache.object(forKey: cacheKey) { return cached }
    let stamp = StampAnnotation(content: content, isStickerStyle: isStickerStyle)
    let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      AnnotateStampRenderer.draw(stamp, in: rect, opacity: 1, context: context)
      return true
    }
    cache.setObject(image, forKey: cacheKey)
    return image
  }
}

struct AnnotateStampThumbnailView: View {
  let content: StampContent
  let height: CGFloat
  var isStickerStyle = true

  var body: some View {
    Image(nsImage: AnnotateStampThumbnail.image(for: content, height: height, isStickerStyle: isStickerStyle))
      .resizable()
      .interpolation(.high)
      .aspectRatio(contentMode: .fit)
      .frame(height: height)
  }
}

// MARK: - Picker button

/// Shows the current stamp; opens the picker.
struct AnnotateStampPickerButton: View {
  @ObservedObject var state: AnnotateState
  @ObservedObject private var store = AnnotateStampStore.shared
  let height: CGFloat
  /// Inline overlay panels float at `.screenSaver`; the open panel must sit above them.
  var openPanelLevel: NSWindow.Level?
  var popoverEdge: Edge = .bottom
  var usesGlassChrome = true

  @State private var showsPopover = false

  var body: some View {
    Button {
      showsPopover.toggle()
    } label: {
      HStack(spacing: 6) {
        AnnotateStampThumbnailView(content: state.quickStampContent, height: height - 6)
          .frame(maxWidth: 64)
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .bold))
          .foregroundColor(.secondary)
      }
      .padding(.horizontal, 7)
      .frame(height: height)
      .modifier(StampButtonChrome(usesGlassChrome: usesGlassChrome, height: height))
    }
    .buttonStyle(.plain)
    .help(L10n.AnnotateStamp.chooseStamp)
    .accessibilityLabel(L10n.AnnotateStamp.chooseStamp)
    .popover(isPresented: $showsPopover, arrowEdge: popoverEdge) {
      AnnotateStampPickerPopover(
        state: state,
        openPanelLevel: openPanelLevel,
        dismiss: { showsPopover = false }
      )
    }
  }
}

private struct StampButtonChrome: ViewModifier {
  let usesGlassChrome: Bool
  let height: CGFloat

  func body(content: Content) -> some View {
    if usesGlassChrome {
      content.liquidGlassControl(isActive: false, cornerRadius: Radius.control(forHeight: height))
    } else {
      content.background(
        RoundedRectangle(cornerRadius: Radius.control(forHeight: height), style: .continuous)
          .fill(Color.primary.opacity(0.06))
      )
    }
  }
}

/// Sticker outline + shadow switch.
struct AnnotateStampStyleToggle: View {
  @ObservedObject var state: AnnotateState
  @ObservedObject private var store = AnnotateStampStore.shared

  var body: some View {
    Toggle(
      L10n.AnnotateStamp.stickerStyle,
      isOn: Binding(
        get: { state.quickStampIsStickerStyle },
        set: { state.setQuickStampStickerStyle($0) }
      )
    )
    .toggleStyle(.switch)
    .controlSize(.mini)
    .font(.system(size: 11, weight: .medium))
    .fixedSize()
    .help(L10n.AnnotateStamp.stickerStyleHelp)
  }
}

extension AnnotateState {
  /// Slider bindings: one undo step per drag (see `AnnotateStampStore.shouldRecordSliderUndo`).
  var quickStampSizeBinding: Binding<CGFloat> {
    Binding(
      get: { [weak self] in self?.quickStampSize ?? AnnotateStampStore.defaultSize },
      set: { [weak self] value in self?.setQuickStampSize(value) }
    )
  }

  var quickStampOpacityBinding: Binding<CGFloat> {
    Binding(
      get: { [weak self] in self?.quickStampOpacity ?? 1 },
      set: { [weak self] value in self?.setQuickStampOpacity(value) }
    )
  }

  func setQuickStampSliderEditing(_ isEditing: Bool) {
    AnnotateStampStore.shared.setSliderEditing(isEditing)
  }
}

// MARK: - Popover

private enum StampPickerTab: Hashable {
  case stickers, emoji, image
}

struct AnnotateStampPickerPopover: View {
  @ObservedObject var state: AnnotateState
  @ObservedObject private var store = AnnotateStampStore.shared
  var openPanelLevel: NSWindow.Level?
  let dismiss: () -> Void

  @State private var tab: StampPickerTab = .stickers
  @State private var query = ""

  private static let width: CGFloat = 352

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("", selection: $tab) {
        Text(L10n.AnnotateStamp.stickers).tag(StampPickerTab.stickers)
        Text(L10n.AnnotateStamp.emoji).tag(StampPickerTab.emoji)
        Text(L10n.AnnotateStamp.image).tag(StampPickerTab.image)
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      if tab == .emoji {
        searchField
      }

      ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 12) {
          switch tab {
          case .stickers:
            recentSection
            stickersContent
          case .emoji:
            emojiContent
          case .image:
            imageContent
          }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: 340)
    }
    .padding(12)
    .frame(width: Self.width)
    .onAppear {
      if case .emoji = state.quickStampContent { tab = .emoji }
      if case .image = state.quickStampContent { tab = .image }
    }
  }

  // MARK: Sections

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundColor(.secondary)
  }

  @ViewBuilder
  private var recentSection: some View {
    if !store.recents.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        sectionTitle(L10n.AnnotateStamp.recent)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(store.recents, id: \.recentKey) { content in
              stampCell(content, height: 30, minWidth: 34)
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  private var stickersContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        sectionTitle(L10n.AnnotateStamp.badges)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 6)], alignment: .leading, spacing: 6) {
          ForEach(StampSticker.badges) { sticker in
            stampCell(.sticker(sticker), height: 32, minWidth: 98)
          }
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        sectionTitle(L10n.AnnotateStamp.icons)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
          ForEach(StampSticker.icons) { sticker in
            stampCell(.sticker(sticker), height: 34, minWidth: 40)
          }
        }
      }
    }
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)
      TextField(L10n.AnnotateStamp.searchEmoji, text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 12))
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 8)
    .frame(height: 26)
    .background(
      RoundedRectangle(cornerRadius: Radius.control(forHeight: 26), style: .continuous)
        .fill(Color.primary.opacity(0.06))
    )
  }

  private static let emojiColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 9)

  @ViewBuilder
  private var emojiContent: some View {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      let recentEmoji = store.recents.filter {
        if case .emoji = $0 { return true }
        return false
      }
      if !recentEmoji.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          sectionTitle(L10n.AnnotateStamp.recent)
          emojiGrid(recentEmoji.compactMap {
            if case .emoji(let emoji) = $0 { return emoji }
            return nil
          })
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        sectionTitle(L10n.AnnotateStamp.popular)
        emojiGrid(AnnotateEmojiCatalog.popular)
      }
      VStack(alignment: .leading, spacing: 6) {
        sectionTitle(L10n.AnnotateStamp.allEmoji)
        emojiGrid(AnnotateEmojiCatalog.allEmoji)
      }
    } else {
      let results = AnnotateEmojiCatalog.search(trimmed)
      if results.isEmpty {
        Text(L10n.AnnotateStamp.noResults)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, minHeight: 120)
      } else {
        emojiGrid(results.map(\.emoji))
      }
    }
  }

  private func emojiGrid(_ emoji: [String]) -> some View {
    LazyVGrid(columns: Self.emojiColumns, spacing: 2) {
      ForEach(Array(emoji.enumerated()), id: \.offset) { _, value in
        EmojiCell(emoji: value, isSelected: state.quickStampContent == .emoji(value)) {
          pick(.emoji(value))
        }
      }
    }
  }

  private var imageContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.AnnotateStamp.imageHint)
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if case .image = store.current {
        stampCell(store.current, height: 96, minWidth: 96)
      }

      Button(L10n.AnnotateStamp.chooseImage) {
        chooseImage()
      }
      .controlSize(.regular)
    }
  }

  // MARK: Cells

  private func stampCell(_ content: StampContent, height: CGFloat, minWidth: CGFloat) -> some View {
    StickerCell(
      content: content,
      height: height,
      minWidth: minWidth,
      isSelected: state.quickStampContent == content,
      help: Self.title(for: content)
    ) {
      pick(content)
    }
  }

  private static func title(for content: StampContent) -> String {
    switch content {
    case .sticker(let sticker): return sticker.displayName
    case .emoji(let emoji): return AnnotateEmojiCatalog.name(for: emoji)
    case .image: return L10n.AnnotateStamp.image
    }
  }

  private func pick(_ content: StampContent) {
    state.chooseStamp(content)
    dismiss()
  }

  private func chooseImage() {
    let level = openPanelLevel
    dismiss()
    // Let the popover close before the modal open panel takes over.
    DispatchQueue.main.async {
      guard let image = AnnotateStampStore.shared.chooseImageFile(panelLevel: level) else { return }
      state.chooseStamp(.image(image))
    }
  }
}

private struct StickerCell: View {
  let content: StampContent
  let height: CGFloat
  let minWidth: CGFloat
  let isSelected: Bool
  let help: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      AnnotateStampThumbnailView(content: content, height: height)
        .frame(minWidth: minWidth, minHeight: height + 8)
        .padding(.horizontal, 2)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous) // radius-lint:allow — picker cell
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(isHovered ? 0.07 : 0))
        )
        .scaleEffect(isHovered ? 1.04 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(help)
    .accessibilityLabel(help)
  }
}

private struct EmojiCell: View {
  let emoji: String
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Text(emoji)
        .font(.system(size: 22))
        .frame(width: 34, height: 32)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous) // radius-lint:allow — picker cell
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(isHovered ? 0.07 : 0))
        )
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(AnnotateEmojiCatalog.name(for: emoji))
  }
}

// MARK: - Quick properties bar

/// Stamp controls for the Annotate window's quick properties bar.
struct AnnotateStampQuickControls: View {
  @ObservedObject var state: AnnotateState
  @ObservedObject private var store = AnnotateStampStore.shared
  let sliderWidth: CGFloat
  let groupSpacing: CGFloat

  var body: some View {
    HStack(spacing: 12) {
      QuickPropertiesGroup(title: L10n.Annotate.stampTool, spacing: groupSpacing) {
        AnnotateStampPickerButton(state: state, height: QuickPropertiesMetrics.toolRow)
      }

      QuickPropertiesGroup(title: L10n.Common.size, spacing: groupSpacing) {
        HStack(spacing: 6) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
          Slider(
            value: state.quickStampSizeBinding.stepped(by: 1, in: AnnotateStampStore.sizeRange),
            in: AnnotateStampStore.sizeRange,
            onEditingChanged: state.setQuickStampSliderEditing
          )
          .frame(width: sliderWidth)
          .controlSize(.small)
          Text("\(Int(state.quickStampSize.rounded()))")
            .font(Typography.labelSmall)
            .foregroundColor(SidebarColors.labelSecondary)
            .lineLimit(1)
            .monospacedDigit()
            .frame(width: 28, alignment: .trailing)
        }
      }

      QuickPropertiesGroup(title: L10n.AnnotateStamp.opacity, spacing: groupSpacing) {
        HStack(spacing: 6) {
          Image(systemName: "circle.lefthalf.filled")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
          Slider(
            value: state.quickStampOpacityBinding.stepped(by: 0.01, in: AnnotateStampStore.opacityRange),
            in: AnnotateStampStore.opacityRange,
            onEditingChanged: state.setQuickStampSliderEditing
          )
          .frame(width: sliderWidth)
          .controlSize(.small)
          Text("\(Int((state.quickStampOpacity * 100).rounded()))%")
            .font(Typography.labelSmall)
            .foregroundColor(SidebarColors.labelSecondary)
            .lineLimit(1)
            .monospacedDigit()
            .frame(width: 38, alignment: .trailing)
        }
      }

      AnnotateStampStyleToggle(state: state)
    }
  }
}
