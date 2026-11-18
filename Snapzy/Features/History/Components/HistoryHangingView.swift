import AppKit
import SwiftUI

struct HistoryHangingView: View {
  @ObservedObject var manager: HistoryHangingManager
  let size: CGSize
  let cableLayout: HistoryHangingCableLayout
  @ObservedObject private var history = HistoryFloatingManager.shared
  @ObservedObject private var store = CaptureHistoryStore.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var filter: CaptureHistoryType?

  private var records: [CaptureHistoryRecord] {
    HistoryHangingLayout.visibleRecords(store.records, filter: filter,
                                        maximum: history.maxDisplayedItems, width: size.width)
  }

  var body: some View {
    VStack(spacing: Spacing.sm) {
      ZStack(alignment: .top) {
        gallery
        if records.isEmpty {
          emptyState
            .frame(height: max(1, size.height - HistoryHangingLayout.toolbarHeight - Spacing.md - Spacing.sm
                - cableLayout.maximumAttachmentHeight - Spacing.lg), alignment: .top)
            .padding(.top, cableLayout.maximumAttachmentHeight + Spacing.lg)
        }
      }
      .frame(maxHeight: .infinity)
      toolbar
        .frame(maxWidth: 680)
        .frame(height: HistoryHangingLayout.toolbarHeight)
        .padding(.horizontal, Spacing.lg)
    }
    .padding(.bottom, Spacing.md)
    .frame(width: size.width, height: size.height, alignment: .top)
    .offset(y: manager.isRevealed ? 0 : -size.height)
    .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86), value: manager.isRevealed)
    .frame(width: size.width, height: size.height)
    .clipped()
    .onAppear { filter = history.defaultFilter }
    .onChange(of: history.defaultFilter) { filter = $0 }
    .onChange(of: records.map(\.id)) { _ in manager.dismissPreview() }
    .onChange(of: filter) { _ in manager.dismissPreview() }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("history.hanging")
  }

  private var toolbar: some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "photo.on.rectangle.angled")
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(Color.accentColor)
      Text(L10n.HistoryHanging.shelfTitle)
        .font(Typography.labelMedium)
        .lineLimit(1)
      Text(verbatim: "\(records.count)")
        .font(Typography.labelSmall)
        .monospacedDigit()
        .foregroundStyle(LiquidGlassTokens.inkMuted)
      Spacer(minLength: Spacing.sm)
      Picker(L10n.PreferencesHistory.defaultFilterTitle, selection: $filter) {
        Text(L10n.PreferencesHistory.defaultFilterAll).tag(CaptureHistoryType?.none)
        Text(L10n.PreferencesHistory.defaultFilterScreenshots).tag(CaptureHistoryType?.some(.screenshot))
        Text(L10n.PreferencesHistory.defaultFilterVideos).tag(CaptureHistoryType?.some(.video))
        Text(L10n.PreferencesHistory.defaultFilterGifs).tag(CaptureHistoryType?.some(.gif))
      }
      .labelsHidden()
      .frame(maxWidth: 140)
      .accessibilityIdentifier("history.hanging.filter")
      HangingIconButton(symbol: "square.grid.2x2", title: L10n.HistoryHanging.browseAll, action: manager.browseAll)
        .accessibilityIdentifier("history.hanging.browse")
      HangingIconButton(
        symbol: manager.keepOpen ? "pin.fill" : "pin",
        title: manager.keepOpen ? L10n.HistoryHanging.autoHide : L10n.HistoryHanging.keepOpen,
        isActive: manager.keepOpen,
        action: manager.toggleKeepOpen
      )
      .accessibilityIdentifier("history.hanging.keepOpen")
      HangingIconButton(symbol: "xmark", title: L10n.HistoryHanging.close, action: manager.hide)
        .accessibilityIdentifier("history.hanging.close")
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .modifier(HangingSurface(radius: Radius.panel))
  }

  private var gallery: some View {
    GeometryReader { geometry in
      let row = HistoryHangingRowLayout(width: geometry.size.width)
      let imageHeight = HistoryHangingLayout.thumbnailHeight(
        galleryHeight: geometry.size.height, anchorDepth: cableLayout.maximumAttachmentHeight,
        compact: size.height < 260
      )
      ZStack(alignment: .topLeading) {
        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
          let x = row.center(at: index, count: records.count) - row.cardWidth / 2
          let y = cableLayout.attachmentHeight(at: x + row.cardWidth / 2)
          HangingCaptureCard(record: record, index: index, width: row.cardWidth,
                             imageHeight: imageHeight, compact: size.height < 260,
                             anchor: CGRect(x: x, y: y, width: row.cardWidth, height: imageHeight + 80),
                             manager: manager)
            .compositingGroup()
            .transition(cardTransition(at: index))
            .offset(x: x, y: y)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
      .animation(reduceMotion ? nil : .spring(response: 0.68, dampingFraction: 0.8), value: records.map(\.id))
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("history.hanging.gallery")
  }

  private func cardTransition(at index: Int) -> AnyTransition {
    guard !reduceMotion else { return .identity }
    return .asymmetric(
      insertion: .modifier(active: HangingCardArrival(progress: 1), identity: HangingCardArrival(progress: 0))
        .animation(.spring(response: 0.72, dampingFraction: 0.64)),
      removal: .modifier(active: HangingCardDeparture(progress: 1, direction: index.isMultiple(of: 2) ? 1 : -1),
                         identity: HangingCardDeparture(progress: 0, direction: index.isMultiple(of: 2) ? 1 : -1))
        .animation(.easeIn(duration: 0.68))
    )
  }

  private var emptyState: some View {
    ViewThatFits(in: .vertical) {
      VStack(spacing: Spacing.md) {
        Image(systemName: "photo.on.rectangle.angled")
          .font(.system(size: 34, weight: .ultraLight))
          .foregroundStyle(LiquidGlassTokens.inkMuted)
        Text(L10n.HistoryHanging.emptyTitle)
          .font(.system(size: 16, weight: .semibold))
        emptyDescription
          .font(Typography.body)
      }
      VStack(spacing: Spacing.xs) {
        Text(L10n.HistoryHanging.emptyTitle)
          .font(Typography.labelMedium)
        emptyDescription
          .font(Typography.labelSmall)
      }
    }
    .padding(.horizontal, Spacing.lg)
    .frame(maxWidth: 400)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("history.hanging.empty")
  }

  private var emptyDescription: some View {
    Text(UserDefaults.standard.snapzyHistoryEnabled
      ? L10n.HistoryHanging.emptyDescription : L10n.HistoryHanging.historyDisabled)
      .foregroundStyle(LiquidGlassTokens.inkBody)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
  }
}

private struct HangingCaptureCard: View {
  let record: CaptureHistoryRecord
  let index: Int
  let width: CGFloat
  let imageHeight: CGFloat
  let compact: Bool
  let anchor: CGRect
  @ObservedObject var manager: HistoryHangingManager
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var thumbnail: NSImage?
  @State private var hovering = false
  @State private var pointerTilt = 0.0

  private var pinned: Bool {
    manager.pinnedIDs.contains(record.id)
  }

  private var restingAngle: Double {
    [-2.4, 1.8, -1.2, 2.5, -1.7][index % 5]
  }

  var body: some View {
    VStack(spacing: 0) {
      HangingClip(isActive: pinned)
        .frame(width: 24, height: 28, alignment: .top)
        .zIndex(1)
      photoCard
        .padding(.top, -6)
    }
    .frame(width: width)
    .rotationEffect(.degrees(reduceMotion ? 0 : (hovering ? pointerTilt : restingAngle)), anchor: .top)
    .scaleEffect(hovering && !reduceMotion ? 1.035 : 1, anchor: .top)
    .offset(y: manager.isRevealed || reduceMotion ? 0 : -260)
    .animation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.62)
      .delay(manager.isRevealed ? Double(min(index, 6)) * 0.025 : 0), value: manager.isRevealed)
    .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.56), value: hovering)
    .animation(reduceMotion ? nil : LiquidGlassTokens.hoverSpring, value: pointerTilt)
    .zIndex(hovering ? 2 : 0)
    .onContinuousHover { phase in
      switch phase {
      case .active(let point):
        manager.preview(record, anchor: anchor)
        hovering = true
        pointerTilt = Double((point.x / width - 0.5) * 3)
      case .ended:
        hovering = false
        pointerTilt = 0
        manager.dismissPreview(for: record.id)
      }
    }
    .task(id: record) {
      let image = await HistoryThumbnailGenerator.shared.loadThumbnailImage(for: record)
      guard !Task.isCancelled else { return }
      thumbnail = image
    }
    .contextMenu { HistoryContextMenu(record: record) }
  }

  private var photoCard: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Group {
        if record.fileExists {
          imageButton
            .onDrag { NSItemProvider(object: record.fileURL as NSURL) }
        } else {
          imageButton.disabled(true)
        }
      }
      if !compact {
        HStack(spacing: Spacing.xs) {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: record.fileName)
              .font(Typography.labelMedium)
              .lineLimit(1)
              .truncationMode(.middle)
            Text(record.capturedAt, style: .time)
              .font(Typography.labelSmall)
              .foregroundStyle(LiquidGlassTokens.inkMuted)
          }
          Spacer(minLength: 0)
          HangingIconButton(symbol: "doc.on.doc", title: L10n.Common.copy, isOnCard: true) { manager.copy(record) }
            .disabled(!record.fileExists)
            .accessibilityIdentifier("history.hanging.copy.\(record.id.uuidString)")
          if record.captureType == .screenshot {
            HangingIconButton(
              symbol: pinned ? "pin.fill" : "pin",
              title: pinned ? L10n.HistoryHanging.unpinImage : L10n.HistoryHanging.pinImage,
              isActive: pinned,
              isOnCard: true
            ) { manager.pin(record) }
              .disabled(!record.fileExists)
              .accessibilityIdentifier("history.hanging.pin.\(record.id.uuidString)")
          }
        }
      }
    }
    .padding(Spacing.sm)
    .padding(.top, Spacing.xs)
    .background(Color(nsColor: .windowBackgroundColor), in: Radius.rect(Radius.card))
    .overlay(Radius.rect(Radius.card).strokeBorder(
      pinned ? Color.accentColor.opacity(0.8) : Color.primary.opacity(hovering ? 0.18 : 0.07),
      lineWidth: pinned ? Size.strokeSelected : Size.strokeDefault
    ))
    .shadow(color: .black.opacity(hovering ? 0.24 : 0.16), radius: hovering ? 14 : 8, y: hovering ? 10 : 6)
  }

  private var imageButton: some View {
    Button { manager.open(record) } label: {
      ZStack {
        Radius.rect(Radius.tile).fill(Color.primary.opacity(0.045))
        if let thumbnail {
          Image(nsImage: thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(Spacing.xs)
        } else {
          Image(systemName: record.fileExists ? record.captureType.systemIconName : "photo.badge.exclamationmark")
            .font(.system(size: 28, weight: .ultraLight))
            .foregroundStyle(LiquidGlassTokens.inkMuted)
        }
        if record.captureType != .screenshot {
          Image(systemName: record.captureType == .video ? "play.fill" : "photo.stack")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
            .padding(Spacing.md)
            .background(.black.opacity(0.45), in: Circle())
        }
      }
      .frame(height: imageHeight)
      .clipShape(Radius.rect(Radius.tile))
      .contentShape(Radius.rect(Radius.tile))
    }
    .buttonStyle(.plain)
    .help(record.fileExists ? L10n.Common.edit : L10n.HistoryHanging.missingFile)
    .accessibilityLabel(record.fileName)
    .accessibilityIdentifier("history.hanging.card.\(record.id.uuidString)")
  }
}

struct HistoryHangingCableView: View {
  @ObservedObject var manager: HistoryHangingManager
  let layout: HistoryHangingCableLayout
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let cable = HangingCable(depth: manager.isRevealed ? layout.depth : 0)
    ZStack {
      cable.stroke(.black.opacity(0.28), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .offset(y: 0.75)
      cable.stroke(
        LinearGradient(colors: [.white.opacity(0.7), .gray.opacity(0.9), .white.opacity(0.8)],
                       startPoint: .top, endPoint: .bottom),
        style: StrokeStyle(lineWidth: 1.25, lineCap: .round)
      )
    }
    .frame(width: layout.frame.width, height: layout.frame.height)
    .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86), value: manager.isRevealed)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct HangingCardArrival: ViewModifier {
  let progress: CGFloat

  func body(content: Content) -> some View {
    content
      .rotationEffect(.degrees(-14 * progress), anchor: .top)
      .scaleEffect(1 - 0.08 * progress, anchor: .top)
      .offset(x: -18 * progress, y: -96 * progress)
      .opacity(1 - min(1, max(0, progress)))
  }
}

private struct HangingCardDeparture: ViewModifier {
  let progress: CGFloat
  let direction: CGFloat

  func body(content: Content) -> some View {
    content
      .rotationEffect(.degrees(direction * 22 * progress), anchor: .top)
      .offset(x: direction * 24 * progress, y: 190 * progress)
      .scaleEffect(1 - 0.06 * progress, anchor: .top)
      .opacity(1 - progress)
      .blur(radius: 1.5 * progress)
      .allowsHitTesting(progress == 0)
      .accessibilityHidden(progress > 0)
  }
}

private struct HangingCable: Shape {
  var depth: CGFloat

  var animatableData: CGFloat {
    get { depth }
    set { depth = newValue }
  }

  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: .zero)
      path.addQuadCurve(to: CGPoint(x: rect.width, y: 0),
                        control: CGPoint(x: rect.midX, y: depth * 2))
    }
  }
}

private struct HangingClip: View {
  let isActive: Bool

  var body: some View {
    ZStack(alignment: .top) {
      Capsule()
        .strokeBorder(.linearGradient(colors: [.white, .gray, .white.opacity(0.8)],
                                      startPoint: .leading, endPoint: .trailing), lineWidth: 2)
        .frame(width: 10, height: 16)
      Radius.rect(Radius.ornament)
        .fill(.linearGradient(colors: [.init(white: 0.88), .init(white: 0.48), .init(white: 0.78)],
                              startPoint: .leading, endPoint: .trailing))
        .frame(width: 22, height: 14)
        .overlay(alignment: .top) {
          Capsule().fill(.white.opacity(0.8)).frame(width: 15, height: 1).padding(.top, 2)
        }
        .overlay {
          Circle().fill(isActive ? Color.accentColor : .black.opacity(0.2)).frame(width: 4, height: 4)
        }
        .padding(.top, 10)
    }
    .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
    .accessibilityHidden(true)
  }
}

private struct HangingIconButton: View {
  let symbol: String
  let title: String
  var isActive = false
  var isOnCard = false
  let action: () -> Void
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      if isOnCard {
        icon
          .background(
            isActive ? SidebarColors.itemSelected : (hovering ? SidebarColors.itemHover : .clear),
            in: Circle()
          )
          .contentShape(Circle())
      } else {
        icon
          .contentShape(Radius.controlRect(forHeight: ControlMetrics.toolbarButton))
          .liquidGlassChrome(
            shape: Radius.controlRect(forHeight: ControlMetrics.toolbarButton),
            isVisible: hovering || isActive
          )
      }
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(reduceMotion ? nil : LiquidGlassTokens.hoverSpring, value: hovering)
    .help(title)
    .accessibilityLabel(title)
  }

  private var icon: some View {
    Image(systemName: symbol)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(isEnabled ? (isActive ? Color.accentColor : LiquidGlassTokens.inkPrimary) : LiquidGlassTokens
        .inkFaint)
      .frame(width: ControlMetrics.toolbarButton, height: ControlMetrics.toolbarButton)
  }
}

private struct HangingSurface: ViewModifier {
  let radius: CGFloat
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  func body(content: Content) -> some View {
    if reduceTransparency {
      content.background(Color(nsColor: .windowBackgroundColor), in: Radius.rect(radius))
    } else {
      content.liquidGlassSurface(shape: Radius.rect(radius), layer: .backdrop)
    }
  }
}
