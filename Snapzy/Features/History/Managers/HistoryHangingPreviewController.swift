import AppKit
import SwiftUI

@MainActor
final class HistoryHangingPreviewController {
  private var panel: HistoryHangingPreviewPanel?
  private var previewTask: Task<Void, Never>?
  private var requestID: UUID?

  var isVisible: Bool {
    panel?.isVisible == true
  }

  private(set) var recordID: UUID?

  /// Keep teardown nonisolated for back-deployed macOS runtimes.
  deinit {
    previewTask?.cancel()
    let panel = panel
    Task { @MainActor in panel?.close() }
  }

  func request(_ record: CaptureHistoryRecord, anchor: CGRect, shelfFrame: CGRect, screen: NSScreen) {
    dismiss()
    let requestID = UUID()
    self.requestID = requestID
    previewTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: 280_000_000)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      let image = await HistoryThumbnailGenerator.shared.loadPreviewImage(for: record)
      guard !Task.isCancelled, let self, self.requestID == requestID, let image else { return }
      // Decoding releases its scope before this final existence check.
      guard SandboxFileAccessManager.shared.withScopedAccess(to: record.fileURL, {
        record.fileExists
      }) else { return }
      previewTask = nil
      show(image, record: record, anchor: anchor, shelfFrame: shelfFrame, screen: screen)
    }
  }

  func dismiss() {
    previewTask?.cancel()
    previewTask = nil
    requestID = nil
    recordID = nil
    panel?.close()
    panel = nil
  }

  nonisolated static func previewFrame(
    visibleFrame: CGRect, shelfFrame: CGRect, anchor: CGRect, imageSize: CGSize
  ) -> CGRect {
    guard visibleFrame.width > 0, visibleFrame.height > 0,
          imageSize.width.isFinite, imageSize.height.isFinite,
          imageSize.width > 0, imageSize.height > 0
    else { return CGRect(origin: visibleFrame.origin, size: .zero) }

    let maxWidth = min(600, visibleFrame.width)
    let maxHeight = min(420, visibleFrame.height)
    let horizontalChrome = Spacing.md * 2
    let verticalChrome = horizontalChrome + Spacing.sm + 16
    let scale = min(
      1,
      max(0, maxWidth - horizontalChrome) / imageSize.width,
      max(0, maxHeight - verticalChrome) / imageSize.height
    )
    let size = CGSize(
      width: min(maxWidth, max(160, ceil(imageSize.width * scale) + horizontalChrome)),
      height: min(maxHeight, ceil(imageSize.height * scale) + verticalChrome)
    )
    let x = min(max(anchor.midX - size.width / 2, visibleFrame.minX), visibleFrame.maxX - size.width)
    var y = shelfFrame.minY - 8 - size.height
    let above = shelfFrame.maxY + 8
    if y < visibleFrame.minY, above + size.height <= visibleFrame.maxY {
      y = above
    }
    y = min(max(y, visibleFrame.minY), visibleFrame.maxY - size.height)
    return CGRect(origin: CGPoint(x: x, y: y), size: size)
  }

  private func show(
    _ image: NSImage, record: CaptureHistoryRecord, anchor: CGRect, shelfFrame: CGRect, screen: NSScreen
  ) {
    let frame = Self.previewFrame(
      visibleFrame: screen.visibleFrame, shelfFrame: shelfFrame, anchor: anchor, imageSize: image.size
    )
    guard frame.width > 0, frame.height > 0 else { return }
    let panel = HistoryHangingPreviewPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.title = "Snapzy History Preview"
    panel.identifier = NSUserInterfaceItemIdentifier("SnapzyHistoryPreview")
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.acceptsMouseMovedEvents = false
    panel.hasShadow = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.animationBehavior = .none
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    panel.appearance = ThemeManager.shared.nsAppearance
    let hosting = NSHostingView(rootView: HistoryHangingPreviewView(
      image: image, fileName: record.fileName, size: frame.size
    ))
    hosting.sizingOptions = []
    hosting.frame = CGRect(origin: .zero, size: frame.size)
    panel.contentView = hosting
    panel.setFrame(frame, display: false)
    self.panel = panel
    recordID = record.id
    CaptureChromeWindowRegistry.configureAppWindow(panel)

    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    panel.alphaValue = reduceMotion ? 1 : 0
    panel.orderFrontRegardless()
    if !reduceMotion {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.12
        panel.animator().alphaValue = 1
      }
    }
  }
}

private final class HistoryHangingPreviewPanel: NSPanel {
  deinit {}

  override var canBecomeKey: Bool {
    false
  }

  override var canBecomeMain: Bool {
    false
  }

  override func close() {
    CaptureChromeWindowRegistry.shared.unregister(self)
    super.close()
  }
}

private struct HistoryHangingPreviewView: View {
  let image: NSImage
  let fileName: String
  let size: CGSize
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(spacing: Spacing.sm) {
      Image(nsImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
      Text(verbatim: fileName)
        .font(Typography.labelSmall)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(height: 16)
    }
    .padding(Spacing.md)
    .frame(width: size.width, height: size.height)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(Radius.rect(Radius.card))
    .preferredColorScheme(theme.systemAppearance)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: fileName))
    .accessibilityIdentifier("history.hanging.preview")
  }
}
