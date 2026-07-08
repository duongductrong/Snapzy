//
//  OCRLinkPromptManager.swift
//  Snapzy
//
//  Floating prompt shown after OCR capture when the recognized text contains
//  web links, offering to open them (CleanShot-style). Unlike AppToastManager
//  the panel accepts mouse input so the links are clickable.
//

import AppKit
import SwiftUI

@MainActor
final class OCRLinkPromptManager {
  static let shared = OCRLinkPromptManager()

  private static let autoDismissDelay: TimeInterval = 10
  fileprivate static let panelWidth: CGFloat = 380
  /// Sits above the bottom-center toast slot so a "Copied to Clipboard"
  /// success toast and this prompt never overlap.
  private static let bottomMargin: CGFloat = 100

  private var panel: NSPanel?
  private var dismissTask: Task<Void, Never>?
  private var activePresentationID = UUID()

  private init() {}

  func show(links: [URL]) {
    guard !links.isEmpty, let screen = targetScreen() else { return }

    dismissTask?.cancel()
    dismissTask = nil
    panel?.orderOut(nil)
    panel = nil

    let presentationID = UUID()
    activePresentationID = presentationID

    let content = OCRLinkPromptView(
      links: links,
      onOpen: { [weak self] url in
        NSWorkspace.shared.open(url)
        DiagnosticLogger.shared.log(.info, .ocr, "OCR link prompt opened link", context: ["host": url.host ?? ""])
        self?.dismiss(presentationID: presentationID)
      },
      onClose: { [weak self] in
        self?.dismiss(presentationID: presentationID)
      },
      onHoverChange: { [weak self] hovering in
        self?.setHoverPaused(hovering, presentationID: presentationID)
      }
    )

    let hostingView = NSHostingView(rootView: content)
    let fittingSize = hostingView.fittingSize
    let size = CGSize(width: Self.panelWidth, height: max(52, fittingSize.height))

    let visibleFrame = screen.visibleFrame
    let frame = CGRect(
      x: visibleFrame.midX - size.width / 2,
      y: visibleFrame.minY + Self.bottomMargin,
      width: size.width,
      height: size.height
    )

    let newPanel = NSPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    newPanel.level = .statusBar
    newPanel.isOpaque = false
    newPanel.backgroundColor = .clear
    newPanel.hasShadow = true
    newPanel.hidesOnDeactivate = false
    newPanel.ignoresMouseEvents = false
    newPanel.becomesKeyOnlyIfNeeded = true
    newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    newPanel.contentView = hostingView
    newPanel.alphaValue = 0
    newPanel.orderFrontRegardless()
    panel = newPanel

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      newPanel.animator().alphaValue = 1
    }

    scheduleAutoDismiss(presentationID: presentationID)
    DiagnosticLogger.shared.log(
      .info,
      .ocr,
      "OCR link prompt shown",
      context: ["linkCount": "\(links.count)"]
    )
  }

  private func scheduleAutoDismiss(presentationID: UUID) {
    dismissTask?.cancel()
    dismissTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: UInt64(Self.autoDismissDelay * 1_000_000_000))
        self?.dismiss(presentationID: presentationID)
      } catch {
        // Cancelled — a newer presentation or hover pause took over.
      }
    }
  }

  private func setHoverPaused(_ paused: Bool, presentationID: UUID) {
    guard presentationID == activePresentationID else { return }
    if paused {
      dismissTask?.cancel()
      dismissTask = nil
    } else {
      scheduleAutoDismiss(presentationID: presentationID)
    }
  }

  private func dismiss(presentationID: UUID) {
    guard presentationID == activePresentationID else { return }
    dismissTask?.cancel()
    dismissTask = nil

    guard let panel else { return }
    self.panel = nil
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.16
      panel.animator().alphaValue = 0
    }, completionHandler: {
      panel.orderOut(nil)
    })
  }

  private func targetScreen() -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    if let hovered = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
      return hovered
    }
    return NSScreen.main ?? NSScreen.screens.first
  }
}

// MARK: - View

private struct OCRLinkPromptView: View {
  let links: [URL]
  let onOpen: (URL) -> Void
  let onClose: () -> Void
  let onHoverChange: (Bool) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "link.circle.fill")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(
          LinearGradient(
            colors: [Color.blue, Color.cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .frame(width: 23, height: 23)

      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(Color(nsColor: AppToastStyle.info.textColor))

        ForEach(links, id: \.absoluteString) { link in
          OCRLinkRowButton(link: link) {
            onOpen(link)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .bold))
          .foregroundColor(Color(nsColor: AppToastStyle.info.textColor).opacity(0.55))
          .frame(width: 20, height: 20)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(L10n.Common.close)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(width: OCRLinkPromptManager.panelWidth, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: AppToastStyle.info.backgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color(nsColor: AppToastStyle.info.borderColor), lineWidth: 0.5)
    )
    .onHover(perform: onHoverChange)
  }

  private var title: String {
    links.count == 1
      ? L10n.OCR.linkDetectedTitle
      : L10n.OCR.linksDetectedTitle(links.count)
  }
}

private struct OCRLinkRowButton: View {
  let link: URL
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Text(OCRLinkDetector.displayString(for: link))
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
          .truncationMode(.middle)

        Image(systemName: "arrow.up.right")
          .font(.system(size: 9, weight: .bold))
          .opacity(0.7)
      }
      .foregroundColor(isHovering ? Color.cyan : Color(nsColor: AppToastStyle.info.textColor).opacity(0.85))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color(nsColor: AppToastStyle.info.textColor).opacity(isHovering ? 0.14 : 0.07))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovering = hovering
    }
    .help(link.absoluteString)
    .accessibilityLabel(L10n.OCR.openLinkAccessibility(link.absoluteString))
  }
}
