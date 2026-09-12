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
      onOpenAll: { [weak self] in
        for url in links {
          NSWorkspace.shared.open(url)
        }
        DiagnosticLogger.shared.log(.info, .ocr, "OCR link prompt opened all links", context: ["count": "\(links.count)"])
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
    newPanel.isMovable = true
    newPanel.isMovableByWindowBackground = true
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
  let onOpenAll: () -> Void
  let onClose: () -> Void
  let onHoverChange: (Bool) -> Void

  @State private var appeared = false
  @State private var isHoveringClose = false

  var body: some View {
    VStack(alignment: .center, spacing: 6) {
      // Drag Handle Pill
      Capsule()
        .fill(Color.primary.opacity(0.18))
        .frame(width: 28, height: 3.5)

      VStack(alignment: .leading, spacing: 10) {
        // MARK: - Header
        HStack(alignment: .center, spacing: 10) {
          // Icon Badge
          ZStack {
            Circle()
              .fill(
                LinearGradient(
                  colors: [Color.blue.opacity(0.2), Color.cyan.opacity(0.15)],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
            Image(systemName: "link")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(
                LinearGradient(
                  colors: [Color.blue, Color.cyan],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
          }
          .frame(width: 28, height: 28)

          // Title & Subtitle
          VStack(alignment: .leading, spacing: 1) {
            Text(title)
              .font(.system(size: 13, weight: .semibold))
              .foregroundColor(.primary)

            Text(subtitle)
              .font(.system(size: 11, weight: .regular))
              .foregroundColor(.secondary)
              .lineLimit(1)
          }

          Spacer(minLength: 6)

          // Open All button if multiple links
          if links.count > 1 {
            Button(action: onOpenAll) {
              HStack(spacing: 4) {
                Text(L10n.OCR.openAllLinks)
                  .font(.system(size: 11, weight: .medium))
                Image(systemName: "arrow.up.right")
                  .font(.system(size: 9, weight: .bold))
              }
              .foregroundStyle(Color.accentColor)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(
                Capsule(style: .continuous)
                  .fill(Color.accentColor.opacity(0.12))
              )
            }
            .buttonStyle(.plain)
            .help(L10n.OCR.openAllLinks)
          }

          // Close button
          Button(action: onClose) {
            Image(systemName: "xmark")
              .font(.system(size: 10, weight: .bold))
              .foregroundColor(isHoveringClose ? .primary : .secondary)
              .frame(width: 20, height: 20)
              .background(
                Circle()
                  .fill(isHoveringClose ? Color.primary.opacity(0.1) : Color.clear)
              )
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .onHover { hovering in
            isHoveringClose = hovering
          }
          .accessibilityLabel(L10n.Common.close)
        }

        // MARK: - Link Rows
        VStack(spacing: 6) {
          ForEach(links, id: \.absoluteString) { link in
            OCRLinkRowCard(link: link, onOpen: { onOpen(link) })
          }
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .padding(.bottom, 12)
    .frame(width: OCRLinkPromptManager.panelWidth, alignment: .leading)
    .background(.regularMaterial, in: Radius.rect(Radius.panel))
    .overlay(
      Radius.rect(Radius.panel)
        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
    )
    .scaleEffect(appeared ? 1.0 : 0.96)
    .opacity(appeared ? 1.0 : 0.0)
    .onAppear {
      withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
        appeared = true
      }
    }
    .onHover(perform: onHoverChange)
  }

  private var title: String {
    links.count == 1
      ? L10n.OCR.linkDetectedTitle
      : L10n.OCR.linksDetectedTitle(links.count)
  }

  private var subtitle: String {
    if links.count == 1, let first = links.first {
      return OCRLinkDetector.displayString(for: first)
    }
    return L10n.PreferencesCapture.ocrLinkDetectionDescription
  }
}

private struct OCRLinkRowCard: View {
  let link: URL
  let onOpen: () -> Void

  @State private var isHoveringRow = false
  @State private var isHoveringCopy = false
  @State private var isHoveringOpen = false
  @State private var isCopied = false

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "globe")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(isHoveringRow ? Color.accentColor : Color.secondary)

      Text(OCRLinkDetector.displayString(for: link))
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.primary)
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer(minLength: 4)

      HStack(spacing: 4) {
        // Copy Button
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(link.absoluteString, forType: .string)
          withAnimation(.easeInOut(duration: 0.15)) {
            isCopied = true
          }
          AppToastManager.shared.show(
            message: L10n.OCR.linkCopiedToast,
            style: .success,
            position: .bottomCenter,
            duration: 1.5,
            variant: .compact
          )
          Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
              withAnimation(.easeInOut(duration: 0.15)) {
                isCopied = false
              }
            }
          }
        } label: {
          Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(isCopied ? .green : (isHoveringCopy ? .primary : .secondary))
            .frame(width: 22, height: 22)
            .background(
              Radius.controlRect(forHeight: 22)
                .fill(isHoveringCopy ? Color.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
          isHoveringCopy = hovering
        }
        .help(L10n.OCR.copyLink)

        // Open Button
        Button(action: onOpen) {
          HStack(spacing: 3) {
            Text(L10n.Common.open)
              .font(.system(size: 11, weight: .medium))
            Image(systemName: "arrow.up.right")
              .font(.system(size: 9, weight: .bold))
          }
          .foregroundColor(isHoveringOpen ? .white : Color.primary.opacity(0.85))
          .padding(.horizontal, 7)
          .padding(.vertical, 3.5)
          .background(
            Capsule(style: .continuous)
              .fill(isHoveringOpen ? Color.accentColor : Color.primary.opacity(0.08))
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
          isHoveringOpen = hovering
        }
        .help(L10n.OCR.openLinkAccessibility(link.absoluteString))
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      Radius.rect(Radius.tile)
        .fill(isHoveringRow ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
    )
    .overlay(
      Radius.rect(Radius.tile)
        .strokeBorder(isHoveringRow ? Color.accentColor.opacity(0.25) : Color.clear, lineWidth: 0.5)
    )
    .contentShape(Rectangle())
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.12)) {
        isHoveringRow = hovering
      }
    }
  }
}
