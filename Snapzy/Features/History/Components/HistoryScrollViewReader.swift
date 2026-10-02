//
//  HistoryScrollViewReader.swift
//  Snapzy
//
//  Reads the underlying NSScrollView of a SwiftUI ScrollView
//  to expose offset, content size, and programmatic scroll.
//

import Combine
import SwiftUI

/// Controls and observes an underlying `NSScrollView`.
final class HistoryScrollController: ObservableObject {
  var scrollView: NSScrollView?

  @Published var offset: CGFloat = 0
  @Published var contentHeight: CGFloat = 0
  @Published var visibleHeight: CGFloat = 0

  var maxOffset: CGFloat {
    max(0, contentHeight - visibleHeight)
  }

  var isScrollable: Bool {
    contentHeight > visibleHeight
  }

  func scrollTo(offset: CGFloat) {
    guard let scrollView = scrollView,
          let documentView = scrollView.documentView else { return }
    let clamped = max(0, min(offset, maxOffset))
    documentView.scroll(NSPoint(x: 0, y: clamped))
  }
}

/// Place this view inside a `ScrollView` to bridge its underlying `NSScrollView`.
struct HistoryScrollViewReader: NSViewRepresentable {
  @ObservedObject var controller: HistoryScrollController

  func makeNSView(context: Context) -> NSView {
    let view = ScrollViewReaderView()
    view.onScrollViewFound = { scrollView in
      context.coordinator.setup(scrollView: scrollView)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    if let scrollView = controller.scrollView {
      context.coordinator.configureClipping(for: scrollView)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject {
    let parent: HistoryScrollViewReader

    init(_ parent: HistoryScrollViewReader) {
      self.parent = parent
    }

    func setup(scrollView: NSScrollView) {
      configureClipping(for: scrollView)
      guard parent.controller.scrollView !== scrollView else { return }
      NotificationCenter.default.removeObserver(self)
      parent.controller.scrollView = scrollView
      scrollView.contentView.postsBoundsChangedNotifications = true
      scrollView.contentView.postsFrameChangedNotifications = true
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(boundsDidChange),
        name: NSView.boundsDidChangeNotification,
        object: scrollView.contentView
      )
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(boundsDidChange),
        name: NSView.frameDidChangeNotification,
        object: scrollView.contentView
      )
      if let documentView = scrollView.documentView {
        documentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(boundsDidChange),
          name: NSView.frameDidChangeNotification,
          object: documentView
        )
      }
      updateScrollInfo()
    }

    func configureClipping(for scrollView: NSScrollView) {
      scrollView.clipsToBounds = false
      scrollView.contentView.clipsToBounds = false
    }

    @objc func boundsDidChange() {
      updateScrollInfo()
    }

    func updateScrollInfo() {
      guard let scrollView = parent.controller.scrollView,
            let documentView = scrollView.documentView else { return }
      let bounds = scrollView.contentView.bounds
      parent.controller.offset = bounds.origin.y
      parent.controller.visibleHeight = bounds.height
      parent.controller.contentHeight = documentView.frame.height
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }
  }
}

// MARK: - Private

private final class ScrollViewReaderView: NSView {
  var onScrollViewFound: ((NSScrollView) -> Void)?

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    findAndReport()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    findAndReport()
  }

  private func findAndReport() {
    guard onScrollViewFound != nil else { return }
    var current: NSView? = self
    while let superview = current?.superview {
      if let scrollView = superview as? NSScrollView {
        onScrollViewFound?(scrollView)
        onScrollViewFound = nil
        return
      }
      current = superview
    }
  }
}
