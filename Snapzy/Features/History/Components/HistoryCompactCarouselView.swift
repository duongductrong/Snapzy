//
//  HistoryCompactCarouselView.swift
//  Snapzy
//
//  Draggable compact carousel with trackpad gesture support
//

import AppKit
import SwiftUI

struct HistoryCompactCarouselView: View {
  let records: [CaptureHistoryRecord]
  let selectedId: UUID?
  let selectionRevealTrigger: Int
  @Binding var scrollOffset: CGFloat
  let onSelect: (CaptureHistoryRecord) -> Void

  @State private var dragTranslation: CGFloat = 0
  @State private var isHoveringZone = false
  @State private var isDraggingContent = false
  @AppStorage(PreferencesKeys.historyBackgroundStyle) private var backgroundStyle: HistoryBackgroundStyle = .defaultStyle

  private let cardWidth: CGFloat = 196
  private let cardSpacing: CGFloat = 26
  private let horizontalPadding: CGFloat = 4

  var body: some View {
    GeometryReader { geometry in
      let metrics = Metrics(
        viewportWidth: geometry.size.width,
        contentWidth: contentWidth
      )
      let visibleOffset = clampedOffset(scrollOffset - dragTranslation, metrics: metrics)
      let centeredOffset = max((metrics.viewportWidth - metrics.contentWidth) / 2, 0)

      LazyHStack(spacing: cardSpacing) {
        ForEach(records) { record in
          HistoryCardView(
            record: record,
            isSelected: selectedId == record.id,
            onTap: { onSelect(record) },
            reservedScrollAxis: metrics.isScrollable ? .horizontal : nil,
            backgroundStyle: backgroundStyle
          )
          .equatable()
          .frame(width: cardWidth)
          .contextMenu {
            HistoryContextMenu(record: record)
          }
        }
      }
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, 6)
      .offset(x: metrics.isScrollable ? -visibleOffset : centeredOffset)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .contentShape(Rectangle())
      .simultaneousGesture(carouselDragGesture(metrics: metrics))
      .background(
        HistoryCompactTrackpadScrollObserver(isEnabled: metrics.isScrollable) { delta in
          scrollOffset = clampedOffset(scrollOffset - delta, metrics: metrics)
        }
      )
      .clipped()
      .onAppear {
        clampScrollOffsetIfNeeded(metrics: metrics)
        updateCursor(for: metrics)
      }
      .onDisappear {
        isDraggingContent = false
        isHoveringZone = false
        dragTranslation = 0
        NSCursor.arrow.set()
      }
      .onHover { hovering in
        isHoveringZone = hovering
        updateCursor(for: metrics)
      }
      .onChange(of: metrics.viewportWidth) { _ in
        clampScrollOffsetIfNeeded(metrics: metrics)
        updateCursor(for: metrics)
      }
      .onChange(of: metrics.contentWidth) { _ in
        clampScrollOffsetIfNeeded(metrics: metrics)
        updateCursor(for: metrics)
      }
      .onChange(of: records.map(\.id)) { _ in
        clampScrollOffsetIfNeeded(metrics: metrics)
      }
      .onChange(of: selectionRevealTrigger) { _ in
        revealSelectedRecordIfNeeded(metrics: metrics)
      }
    }
  }

  private var contentWidth: CGFloat {
    guard !records.isEmpty else { return 0 }
    let cardCount = CGFloat(records.count)
    let spacingCount = CGFloat(max(records.count - 1, 0))
    return (cardCount * cardWidth) + (spacingCount * cardSpacing) + (horizontalPadding * 2)
  }

  private func carouselDragGesture(metrics: Metrics) -> some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { value in
        guard metrics.isScrollable else { return }
        dragTranslation = value.translation.width
        isDraggingContent = true
        updateCursor(for: metrics)
      }
      .onEnded { value in
        guard metrics.isScrollable else {
          dragTranslation = 0
          isDraggingContent = false
          updateCursor(for: metrics)
          return
        }

        scrollOffset = clampedOffset(scrollOffset - value.translation.width, metrics: metrics)
        dragTranslation = 0
        isDraggingContent = false
        updateCursor(for: metrics)
      }
  }

  private func revealSelectedRecordIfNeeded(metrics: Metrics) {
    guard metrics.isScrollable else {
      scrollOffset = 0
      return
    }

    guard let selectedId,
      let selectedIndex = records.firstIndex(where: { $0.id == selectedId })
    else {
      scrollOffset = clampedOffset(scrollOffset, metrics: metrics)
      return
    }

    let selectedLeading = horizontalPadding + (CGFloat(selectedIndex) * (cardWidth + cardSpacing))
    let selectedTrailing = selectedLeading + cardWidth
    let visibleLeading = scrollOffset
    let visibleTrailing = scrollOffset + metrics.viewportWidth

    if selectedLeading < visibleLeading {
      scrollOffset = clampedOffset(selectedLeading, metrics: metrics)
    } else if selectedTrailing > visibleTrailing {
      scrollOffset = clampedOffset(selectedTrailing - metrics.viewportWidth, metrics: metrics)
    } else {
      scrollOffset = clampedOffset(scrollOffset, metrics: metrics)
    }
  }

  private func clampScrollOffsetIfNeeded(metrics: Metrics) {
    guard metrics.isScrollable else {
      scrollOffset = 0
      return
    }

    scrollOffset = clampedOffset(scrollOffset, metrics: metrics)
  }

  private func clampedOffset(_ offset: CGFloat, metrics: Metrics) -> CGFloat {
    min(max(offset, 0), metrics.maxScrollOffset)
  }

  private func updateCursor(for metrics: Metrics) {
    guard metrics.isScrollable else {
      NSCursor.arrow.set()
      return
    }

    if isDraggingContent {
      NSCursor.closedHand.set()
    } else if isHoveringZone {
      NSCursor.openHand.set()
    } else {
      NSCursor.arrow.set()
    }
  }
}

private extension HistoryCompactCarouselView {
  struct Metrics: Equatable {
    let viewportWidth: CGFloat
    let contentWidth: CGFloat

    var maxScrollOffset: CGFloat {
      max(contentWidth - viewportWidth, 0)
    }

    var isScrollable: Bool {
      maxScrollOffset > 1
    }
  }
}

private struct HistoryCompactTrackpadScrollObserver: NSViewRepresentable {
  let isEnabled: Bool
  let onScroll: (CGFloat) -> Void

  func makeNSView(context: Context) -> HistoryCompactTrackpadScrollView {
    let view = HistoryCompactTrackpadScrollView()
    view.isEnabled = isEnabled
    view.onScroll = onScroll
    return view
  }

  func updateNSView(_ nsView: HistoryCompactTrackpadScrollView, context: Context) {
    nsView.isEnabled = isEnabled
    nsView.onScroll = onScroll
  }

  static func dismantleNSView(_ nsView: HistoryCompactTrackpadScrollView, coordinator: ()) {
    nsView.cleanup()
  }
}

private final class HistoryCompactTrackpadScrollView: NSView {
  var isEnabled = false
  var onScroll: ((CGFloat) -> Void)?

  private var monitor: Any?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    installMonitorIfNeeded()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func cleanup() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
  }

  private func installMonitorIfNeeded() {
    guard monitor == nil else { return }

    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self else { return event }
      return self.handleScrollEvent(event) ? nil : event
    }
  }

  private func handleScrollEvent(_ event: NSEvent) -> Bool {
    guard isEnabled, let window, event.window === window else { return false }
    guard !event.modifierFlags.contains(.command) else { return false }

    let location = convert(event.locationInWindow, from: nil)
    guard bounds.contains(location) else { return false }

    let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 18
    let dominantDelta = abs(event.scrollingDeltaX) > 0.5
      ? CGFloat(event.scrollingDeltaX)
      : CGFloat(event.scrollingDeltaY)
    let delta = dominantDelta * multiplier

    guard abs(delta) > 0.5 else { return false }
    onScroll?(delta)
    return true
  }
}
