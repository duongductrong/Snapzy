//
//  PreferencesHistoryMiniature.swift
//  Snapzy
//
//  Flat 1:1 miniatures of the two shipping history surfaces, drawn from HistoryHangingView and
//  HistoryFloatingContentView compact mode: real geometry, real controls, real filename and time
//  formats, no invented artwork.
//

import SwiftUI

// MARK: - Sample Captures

/// One entry of the history store, rendered by both display styles.
struct HistoryMiniatureCapture: Identifiable, Equatable {
  enum Kind {
    case screenshot
    case video
    case gif
  }

  enum Scene {
    case fileBrowser
    case codeEditor
    case notes
    case settingsPane
    case chatLog
    case terminal
  }

  let id: Int
  let scene: Scene
  let kind: Kind
  let capturedAt: Date
  let durationText: String?

  /// Filenames are named exactly like `CaptureOutputNaming` names real files.
  private static let shotName: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "'Snapzy_'yyyy-MM-dd_HH-mm-ss-SSS"
    return formatter
  }()

  private static let recordingName: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "'Snapzy_Recording_'yyyy-MM-dd_HH-mm-ss"
    return formatter
  }()

  var fileName: String {
    switch kind {
    case .screenshot: Self.shotName.string(from: capturedAt) + ".png"
    case .video: Self.recordingName.string(from: capturedAt) + ".mp4"
    case .gif: Self.shotName.string(from: capturedAt) + ".gif"
    }
  }

  /// Rendered the way the real cards render time: a localised clock on the shelf, a localised
  /// relative phrase in the carousel.
  var clockText: String {
    capturedAt.formatted(date: .omitted, time: .shortened)
  }

  var relativeText: String {
    HistoryFormatterCache.relativeFull.localizedString(for: capturedAt, relativeTo: Date())
  }

  private static let referenceDate = Date()

  private static func ago(_ seconds: TimeInterval) -> Date {
    referenceDate.addingTimeInterval(-seconds)
  }

  /// The fractional parts keep the millisecond stamp distinct, the way real captures differ.
  static let samples: [HistoryMiniatureCapture] = [
    HistoryMiniatureCapture(id: 0, scene: .fileBrowser, kind: .screenshot, capturedAt: ago(210.371), durationText: nil),
    HistoryMiniatureCapture(id: 1, scene: .codeEditor, kind: .screenshot, capturedAt: ago(540.628), durationText: nil),
    HistoryMiniatureCapture(id: 2, scene: .chatLog, kind: .screenshot, capturedAt: ago(2100.154), durationText: nil),
    HistoryMiniatureCapture(id: 3, scene: .notes, kind: .video, capturedAt: ago(11_400.842), durationText: "00:24"),
    HistoryMiniatureCapture(
      id: 4,
      scene: .settingsPane,
      kind: .screenshot,
      capturedAt: ago(16_200.409),
      durationText: nil
    ),
    HistoryMiniatureCapture(id: 5, scene: .terminal, kind: .gif, capturedAt: ago(93_000.913), durationText: "00:06"),
  ]

  var symbolName: String {
    switch kind {
    case .screenshot: "photo"
    case .video: "film"
    case .gif: "photo.stack"
    }
  }
}

// MARK: - Miniature Screenshot

/// Flat miniature of a captured window — chrome, sidebars, text and code lines, no invented artwork.
struct HistoryMiniatureThumb: View {
  let capture: HistoryMiniatureCapture

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      content(in: size)
        .frame(width: size.width, height: size.height)
    }
  }

  @ViewBuilder
  private func content(in size: CGSize) -> some View {
    switch capture.scene {
    case .fileBrowser:
      fileBrowser(size)
    case .codeEditor:
      codeEditor(size)
    case .notes:
      notes(size)
    case .settingsPane:
      settingsPane(size)
    case .chatLog:
      chatLog(size)
    case .terminal:
      terminal(size)
    }
  }

  // MARK: Scenes

  private func fileBrowser(_ size: CGSize) -> some View {
    let bar = titleBar(size, background: Color(white: 0.96))
    let sidebarWidth = size.width * 0.34

    return ZStack(alignment: .topLeading) {
      Color(white: 0.99)

      HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: size.height * 0.035) {
          ForEach(0 ..< 5, id: \.self) { row in
            barRow(width: sidebarWidth * (row == 1 ? 0.78 : 0.62), color: Color(white: 0.55))
          }
        }
        .padding(.top, size.height * 0.26)
        .padding(.leading, size.width * 0.03)
        .frame(width: sidebarWidth, alignment: .leading)
        .background(Color(white: 0.945))

        VStack(alignment: .leading, spacing: size.height * 0.05) {
          ForEach(0 ..< 5, id: \.self) { row in
            HStack(spacing: size.width * 0.02) {
              Image(systemName: row < 2 ? "folder.fill" : "doc.text.fill")
                .font(.system(size: size.height * 0.055))
                .foregroundStyle(row < 2 ? Color.blue : Color(white: 0.62))
                .frame(width: size.width * 0.055)

              barRow(width: size.width * (row == 2 ? 0.30 : 0.22), color: Color(white: 0.62))
              barRow(width: size.width * 0.14, color: Color(white: 0.80))
            }
          }
        }
        .padding(.top, size.height * 0.26)
        .padding(.leading, size.width * 0.04)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }

      bar
    }
  }

  private func codeEditor(_ size: CGSize) -> some View {
    let lineColors: [Color] = [.blue, .orange, .purple, .green, .blue, .gray, .orange, .green]

    return ZStack(alignment: .topLeading) {
      Color(white: 0.13)

      VStack(alignment: .leading, spacing: size.height * 0.035) {
        HStack(spacing: size.width * 0.02) {
          RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color(white: 0.32))
            .frame(width: size.width * 0.18, height: size.height * 0.09)
          RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color(white: 0.22))
            .frame(width: size.width * 0.14, height: size.height * 0.09)
        }
        .padding(.bottom, size.height * 0.03)

        ForEach(0 ..< 8, id: \.self) { row in
          HStack(spacing: size.width * 0.02) {
            barRow(width: size.width * 0.035, color: Color(white: 0.34))
            barRow(
              width: size.width * (row.isMultiple(of: 3) ? 0.34 : 0.48) * (row.isMultiple(of: 2) ? 1 : 0.7),
              color: lineColors[row % lineColors.count].opacity(0.75)
            )
          }
          .padding(.leading, size.width * (row == 3 || row == 4 ? 0.05 : 0))
        }
      }
      .padding(size.height * 0.08)

      Rectangle()
        .fill(Color(white: 0.20))
        .frame(width: size.width * 0.05, height: size.height)
    }
  }

  private func notes(_ size: CGSize) -> some View {
    ZStack(alignment: .topLeading) {
      Color.white

      VStack(alignment: .leading, spacing: size.height * 0.05) {
        barRow(width: size.width * 0.42, height: size.height * 0.075, color: Color(white: 0.22))
          .padding(.bottom, size.height * 0.03)

        ForEach(0 ..< 6, id: \.self) { row in
          barRow(width: size.width * (row == 5 ? 0.42 : 0.78 - CGFloat(row % 3) * 0.08), color: Color(white: 0.72))
        }
      }
      .padding(size.height * 0.14)

      titleBar(size, background: Color(white: 0.97))
    }
  }

  private func settingsPane(_ size: CGSize) -> some View {
    let sidebarWidth = size.width * 0.36

    return ZStack(alignment: .topLeading) {
      Color(white: 0.95)

      HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: size.height * 0.045) {
          ForEach(0 ..< 6, id: \.self) { row in
            HStack(spacing: size.width * 0.02) {
              RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(row == 2 ? Color.accentColor : Color(white: 0.66))
                .frame(width: size.height * 0.06, height: size.height * 0.06)
              barRow(width: sidebarWidth * 0.60, color: Color(white: 0.58))
            }
          }
        }
        .padding(.top, size.height * 0.28)
        .padding(.leading, size.width * 0.03)
        .frame(width: sidebarWidth, alignment: .topLeading)
        .background(Color(white: 0.92))

        VStack(alignment: .leading, spacing: size.height * 0.06) {
          ForEach(0 ..< 4, id: \.self) { row in
            HStack(spacing: 0) {
              barRow(width: size.width * 0.20, color: Color(white: 0.55))
              Spacer(minLength: 0)
              RoundedRectangle(cornerRadius: size.height * 0.035, style: .continuous)
                .fill(row < 2 ? Color.accentColor : Color(white: 0.78))
                .frame(width: size.width * 0.09, height: size.height * 0.07)
                .overlay(
                  Circle()
                    .fill(Color.white)
                    .frame(width: size.height * 0.055, height: size.height * 0.055)
                    .offset(x: row < 2 ? size.width * 0.018 : -size.width * 0.018)
                )
            }
            .padding(.horizontal, size.width * 0.03)
            .padding(.vertical, size.height * 0.035)
            .background(
              RoundedRectangle(cornerRadius: size.height * 0.06, style: .continuous)
                .fill(Color.white)
            )
          }
        }
        .padding(.top, size.height * 0.28)
        .padding(.horizontal, size.width * 0.03)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }

      titleBar(size, background: Color(white: 0.93))
    }
  }

  private func chatLog(_ size: CGSize) -> some View {
    let widths: [CGFloat] = [0.44, 0.30, 0.52, 0.26, 0.40]

    return ZStack(alignment: .topLeading) {
      Color(white: 0.98)

      VStack(spacing: size.height * 0.045) {
        ForEach(0 ..< widths.count, id: \.self) { row in
          let isOutgoing = row.isMultiple(of: 2)

          HStack(spacing: 0) {
            if isOutgoing {
              Spacer(minLength: 0)
            }
            RoundedRectangle(cornerRadius: size.height * 0.055, style: .continuous)
              .fill(isOutgoing ? Color.accentColor : Color(white: 0.88))
              .frame(width: size.width * widths[row], height: size.height * 0.13)
            if !isOutgoing {
              Spacer(minLength: 0)
            }
          }
        }
      }
      .padding(.top, size.height * 0.24)
      .padding(.horizontal, size.width * 0.05)

      titleBar(size, background: Color(white: 0.95))
    }
  }

  private func terminal(_ size: CGSize) -> some View {
    VStack(alignment: .leading, spacing: size.height * 0.05) {
      ForEach(0 ..< 6, id: \.self) { row in
        HStack(spacing: size.width * 0.015) {
          if row.isMultiple(of: 2) {
            barRow(width: size.width * 0.06, color: Color(red: 0.30, green: 0.78, blue: 0.42))
          }
          barRow(
            width: size.width * (row == 4 ? 0.22 : 0.46 - CGFloat(row % 3) * 0.06),
            color: Color(white: row.isMultiple(of: 2) ? 0.72 : 0.44)
          )
        }
      }
    }
    .padding(.top, size.height * 0.24)
    .padding(.horizontal, size.width * 0.045)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(white: 0.11))
    .overlay(alignment: .topLeading) {
      titleBar(size, background: Color(white: 0.16))
    }
  }

  // MARK: Shared chrome

  private func titleBar(_ size: CGSize, background: Color) -> some View {
    HStack(spacing: size.width * 0.018) {
      Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: size.height * 0.035)
      Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: size.height * 0.035)
      Circle().fill(Color(red: 0.16, green: 0.80, blue: 0.25)).frame(width: size.height * 0.035)
      Spacer(minLength: 0)
    }
    .padding(.leading, size.width * 0.03)
    .frame(height: size.height * 0.18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(background)
  }

  private func barRow(width: CGFloat, height: CGFloat? = nil, color: Color) -> some View {
    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
      .fill(color)
      .frame(width: width, height: height ?? 3)
  }
}

// MARK: - Hanging Shelf

/// 1:1 miniature of `HistoryHangingView` — sagging cable, 184pt cards on 24pt spacing, clip
/// ornament, meta row, 44pt toolbar — uniformly scaled so it reads at desktop proportions.
struct HistoryHangingMiniature: View {
  let captures: [HistoryMiniatureCapture]
  let scale: CGFloat

  private func s(_ value: CGFloat) -> CGFloat {
    value * scale
  }

  private func f(_ value: CGFloat) -> CGFloat {
    max(8.5, value * scale)
  }

  private var cardWidth: CGFloat {
    s(184)
  }

  private var cardSpacing: CGFloat {
    s(24)
  }

  private var cableDepth: CGFloat {
    s(56)
  }

  private var imageHeight: CGFloat {
    s(112)
  }

  private var galleryHeight: CGFloat {
    cableDepth + cardHeight + s(12)
  }

  /// Gallery + toolbar + the trailing gap the real shelf window leaves under the toolbar.
  private var shelfHeight: CGFloat {
    galleryHeight + s(8) + s(44) + s(16)
  }

  private var cardHeight: CGFloat {
    s(28) - s(6) + s(4) + imageHeight + s(8) + s(30) + s(8)
  }

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let shown = Array(captures.prefix(capacity(for: width)))

      VStack(spacing: s(8)) {
        gallery(shown: shown, width: width)

        HistoryShelfToolbarMiniature(count: shown.count, scale: scale)
          .frame(maxWidth: s(680))
          .frame(height: s(44))
      }
      .padding(.bottom, s(16))
      .frame(width: width, height: proxy.size.height, alignment: .top)
    }
    .frame(height: shelfHeight)
  }

  /// `HistoryHangingRowLayout` capacity math, in scaled units.
  private func capacity(for width: CGFloat) -> Int {
    let fittedCardWidth = min(cardWidth, max(1, width - s(48)))
    let fitted = Int((width - s(48) + cardSpacing) / (fittedCardWidth + cardSpacing))
    return max(1, min(fitted, captures.count))
  }

  private func gallery(shown: [HistoryMiniatureCapture], width: CGFloat) -> some View {
    let fittedCardWidth = min(cardWidth, max(1, width - s(48)))
    let rowWidth = CGFloat(shown.count) * fittedCardWidth
      + CGFloat(max(shown.count - 1, 0)) * cardSpacing
    let startX = max(0, (width - rowWidth) / 2)

    return ZStack(alignment: .topLeading) {
      cable(width: width)

      ForEach(Array(shown.enumerated()), id: \.element.id) { index, capture in
        let centerX = startX + CGFloat(index) * (fittedCardWidth + cardSpacing) + fittedCardWidth / 2
        let t = min(max(centerX / max(width, 1), 0), 1)

        HistoryHangingCardMiniature(
          capture: capture,
          index: index,
          width: fittedCardWidth,
          imageHeight: imageHeight,
          scale: scale
        )
        .frame(width: fittedCardWidth, alignment: .top)
        .offset(x: centerX - fittedCardWidth / 2, y: 4 * cableDepth * t * (1 - t))
        .zIndex(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func cable(width: CGFloat) -> some View {
    HistoryMiniatureCable(depth: cableDepth)
      .stroke(Color.black.opacity(0.28), style: StrokeStyle(lineWidth: max(1.2, s(2.5)), lineCap: .round))
      .frame(width: width, height: 1)
      .offset(y: 0.75)
      .overlay(
        HistoryMiniatureCable(depth: cableDepth)
          .stroke(Color.white.opacity(0.82), style: StrokeStyle(lineWidth: max(0.9, s(1.25)), lineCap: .round))
      )
  }
}

struct HistoryMiniatureCable: Shape {
  let depth: CGFloat

  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: .zero)
      path.addQuadCurve(
        to: CGPoint(x: rect.width, y: 0),
        control: CGPoint(x: rect.midX, y: depth * 2)
      )
    }
  }
}

struct HistoryHangingCardMiniature: View {
  let capture: HistoryMiniatureCapture
  let index: Int
  let width: CGFloat
  let imageHeight: CGFloat
  let scale: CGFloat

  private static let restingAngles: [Double] = [-2.4, 1.8, -1.2, 2.5, -1.7]

  private func s(_ value: CGFloat) -> CGFloat {
    value * scale
  }

  private func f(_ value: CGFloat) -> CGFloat {
    max(8.5, value * scale)
  }

  /// The real shelf only prints the filename strip when the card is near full size — judged in
  /// unscaled points, because the whole shelf is a uniformly scaled miniature.
  private var showsMeta: Bool {
    width / scale >= 150
  }

  var body: some View {
    VStack(spacing: 0) {
      HistoryMiniatureClip(scale: scale)
        .frame(width: s(24), height: s(28), alignment: .top)
        .zIndex(1)

      photoCard
        .padding(.top, s(-6))
    }
    .frame(width: width)
    .rotationEffect(.degrees(Self.restingAngles[index % Self.restingAngles.count]), anchor: .top)
  }

  private var photoCard: some View {
    VStack(alignment: .leading, spacing: s(8)) {
      HistoryMiniatureThumb(capture: capture)
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(s(4))
        .frame(height: imageHeight)
        .background(
          Radius.rect(s(Radius.tile)).fill(Color.primary.opacity(0.045))
        )
        .clipShape(Radius.rect(s(Radius.tile)))
        .overlay(alignment: .center) {
          if capture.kind != .screenshot {
            Image(systemName: capture.kind == .video ? "play.fill" : "photo.stack")
              .font(.system(size: f(18)))
              .foregroundStyle(.white)
              .padding(s(16))
              .background(.black.opacity(0.45), in: Circle())
          }
        }

      if showsMeta {
        HStack(spacing: s(4)) {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: capture.fileName)
              .font(.system(size: f(11), weight: .medium))
              .lineLimit(1)
              .truncationMode(.middle)
            Text(verbatim: capture.clockText)
              .font(.system(size: f(10)))
              .foregroundStyle(LiquidGlassTokens.inkMuted)
          }

          Spacer(minLength: 0)

          cardIcon("doc.on.doc")
          if capture.kind == .screenshot {
            cardIcon("pin")
          }
        }
      }
    }
    .padding(s(8))
    .padding(.top, s(4))
    .background(
      Color(nsColor: .windowBackgroundColor), in: Radius.rect(s(Radius.card))
    )
    .overlay(
      Radius.rect(s(Radius.card))
        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.16), radius: s(8), y: s(6))
  }

  private func cardIcon(_ symbol: String) -> some View {
    Image(systemName: symbol)
      .font(.system(size: f(12)))
      .foregroundStyle(LiquidGlassTokens.inkPrimary)
      .frame(width: s(28), height: s(28))
      .background(Circle().fill(Color.primary.opacity(0.06)))
  }
}

struct HistoryMiniatureClip: View {
  let scale: CGFloat

  private func s(_ value: CGFloat) -> CGFloat {
    value * scale
  }

  var body: some View {
    ZStack(alignment: .top) {
      Capsule()
        .strokeBorder(Color(white: 0.68), lineWidth: max(1, s(2)))
        .frame(width: s(10), height: s(16))

      Radius.rect(s(Radius.ornament))
        .fill(Color(white: 0.74))
        .frame(width: s(22), height: s(14))
        .overlay(alignment: .top) {
          Capsule()
            .fill(Color.white.opacity(0.8))
            .frame(width: s(15), height: 1)
            .padding(.top, s(2))
        }
        .overlay {
          Circle()
            .fill(Color.black.opacity(0.2))
            .frame(width: s(4), height: s(4))
        }
        .padding(.top, s(10))
    }
    .shadow(color: Color.black.opacity(0.2), radius: s(2), y: s(2))
  }
}

/// Expanded state of the real shelf toolbar: identity, title, count, filter, browse, pin, close.
struct HistoryShelfToolbarMiniature: View {
  let count: Int
  let scale: CGFloat

  private func s(_ value: CGFloat) -> CGFloat {
    value * scale
  }

  private func f(_ value: CGFloat) -> CGFloat {
    max(8.5, value * scale)
  }

  var body: some View {
    HStack(spacing: s(8)) {
      Image(systemName: "photo.on.rectangle.angled")
        .font(.system(size: f(16), weight: .medium))
        .foregroundStyle(Color.accentColor)

      Text(L10n.HistoryHanging.shelfTitle)
        .font(.system(size: f(11), weight: .medium))
        .lineLimit(1)

      Text(verbatim: "\(count)")
        .font(.system(size: f(10)))
        .monospacedDigit()
        .foregroundStyle(LiquidGlassTokens.inkMuted)

      Spacer(minLength: s(8))

      filterChip

      toolbarIcon("square.grid.2x2")
      toolbarIcon("pin")
      toolbarIcon("xmark")
    }
    .padding(.horizontal, s(16))
    .padding(.vertical, s(8))
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      SnapzyGlassSurface(
        shape: Radius.rect(s(Radius.panel)),
        substrate: SnapzySurfaceGlass.baseDarkness,
        tint: 0.10
      )
    )
    .clipShape(Radius.rect(s(Radius.panel)))
    .shadow(color: Color.black.opacity(0.28), radius: s(12), y: s(6))
  }

  private var filterChip: some View {
    HStack(spacing: s(5)) {
      Text(L10n.PreferencesHistory.defaultFilterAll)
        .font(.system(size: f(11), weight: .medium))
        .lineLimit(1)

      Image(systemName: "chevron.up.chevron.down")
        .font(.system(size: f(8), weight: .semibold))
        .foregroundStyle(LiquidGlassTokens.inkMuted)
    }
    .padding(.horizontal, s(9))
    .padding(.vertical, s(5))
    .background(
      RoundedRectangle(cornerRadius: max(4, s(10)), style: .continuous)
        .fill(Color.primary.opacity(0.08))
    )
  }

  private func toolbarIcon(_ symbol: String) -> some View {
    Image(systemName: symbol)
      .font(.system(size: f(12), weight: .medium))
      .foregroundStyle(LiquidGlassTokens.inkPrimary)
      .frame(width: s(28), height: s(28))
  }
}

// MARK: - Traditional Panel

/// 1:1 miniature of the compact floating panel — filter pills over a dark scrim, a control row and
/// the 196pt carousel that clips at the panel edge — scaled to the display proportions it has on a
/// real desktop (920pt of a 1440pt screen), so it never swamps the mock.
struct HistoryTraditionalPanelMiniature: View {
  let captures: [HistoryMiniatureCapture]
  let scale: CGFloat

  private func s(_ value: CGFloat) -> CGFloat {
    value * scale
  }

  private func f(_ value: CGFloat) -> CGFloat {
    max(8.5, value * scale)
  }

  private var cardWidth: CGFloat {
    s(196)
  }

  private var cardPitch: CGFloat {
    s(196 + 26)
  }

  private var innerWidth: CGFloat {
    s(920) - s(44)
  }

  private var selectedIndex: Int {
    min(2, max(0, captures.count - 1))
  }

  /// The real compact panel centres the picked card and lets its neighbours run off the edges.
  /// Offsets (which never grow a frame) keep the row inside an exactly-clipped viewport.
  private var rowStart: CGFloat {
    (innerWidth - cardWidth) / 2 - CGFloat(selectedIndex) * cardPitch
  }

  var body: some View {
    VStack(spacing: s(18)) {
      header

      ZStack(alignment: .topLeading) {
        ForEach(Array(captures.enumerated()), id: \.element.id) { index, capture in
          HistoryCarouselCardMiniature(capture: capture, isSelected: index == selectedIndex, scale: scale)
            .frame(width: cardWidth, alignment: .top)
            .offset(x: rowStart + CGFloat(index) * cardPitch)
        }
      }
      .frame(width: innerWidth, height: s(232), alignment: .topLeading)
      .clipped()
    }
    .padding(.horizontal, s(22))
    .padding(.vertical, s(18))
    .frame(width: s(920), height: s(316), alignment: .top)
    .background(Color.black.opacity(0.46), in: Radius.rect(s(30)))
    .environment(\.colorScheme, .dark)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(Color.white.opacity(0.34))
        .frame(height: 1)
        .padding(.horizontal, s(14))
    }
    .overlay(
      Radius.rect(s(30))
        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
    )
    .shadow(color: Color.black.opacity(0.34), radius: s(20), y: s(10))
  }

  private var header: some View {
    ZStack {
      HStack(spacing: s(10)) {
        pill(L10n.PreferencesHistory.defaultFilterAll, isSelected: true)
        pill(L10n.PreferencesHistory.defaultFilterScreenshots, isSelected: false)
        pill(L10n.PreferencesHistory.defaultFilterVideos, isSelected: false)
        pill(L10n.PreferencesHistory.defaultFilterGifs, isSelected: false)
      }
      .frame(maxWidth: .infinity)

      HStack(spacing: s(8)) {
        Spacer()
        control("trash")
        control("arrow.up.forward.app")
        control("pin")
        control("xmark")
      }
    }
    .frame(height: s(30))
  }

  private func pill(_ title: String, isSelected: Bool) -> some View {
    Text(title)
      .font(.system(size: f(12), weight: .semibold))
      .lineLimit(1)
      .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.78))
      .padding(.horizontal, s(12))
      .padding(.vertical, s(7))
      .background(
        Capsule(style: .continuous)
          .fill(isSelected ? Color.accentColor.opacity(0.90) : Color.white.opacity(0.10))
      )
      .overlay(
        Capsule(style: .continuous)
          .strokeBorder(Color.white.opacity(isSelected ? 0.24 : 0.12), lineWidth: 0.5)
      )
  }

  private func control(_ symbol: String) -> some View {
    Image(systemName: symbol)
      .font(.system(size: f(10.5), weight: .semibold))
      .foregroundStyle(Color.white.opacity(0.88))
      .frame(width: s(30), height: s(30))
      .background(Circle().fill(Color.white.opacity(0.10)))
      .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
  }
}

struct HistoryCarouselCardMiniature: View {
  let capture: HistoryMiniatureCapture
  let isSelected: Bool
  let scale: CGFloat

  private func s(_ value: CGFloat) -> CGFloat {
    value * scale
  }

  private func f(_ value: CGFloat) -> CGFloat {
    max(8, value * scale)
  }

  private var cardShape: RoundedRectangle {
    Radius.rect(s(Radius.card))
  }

  var body: some View {
    VStack(spacing: s(10)) {
      preview

      if isSelected {
        HStack(spacing: s(4)) {
          Image(systemName: "arrow.uturn.backward")
            .font(.system(size: f(11), weight: .semibold))
          Text(L10n.Common.restore)
            .font(.system(size: f(11), weight: .semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, s(12))
        .padding(.vertical, s(6))
        .background(Capsule(style: .continuous).fill(Color.accentColor))
        .padding(.top, s(-2))
      }

      Text(verbatim: capture.relativeText)
        .font(.system(size: f(12.5), weight: isSelected ? .semibold : .medium))
        .foregroundStyle(Color.white.opacity(0.82))
        .frame(maxWidth: .infinity, alignment: .center)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .scaleEffect(isSelected ? 1.02 : 1)
  }

  private var preview: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottomTrailing) {
        cardShape.fill(Color.white.opacity(0.08))

        HistoryMiniatureThumb(capture: capture)

        if let duration = capture.durationText {
          VStack {
            HStack {
              Text(verbatim: duration)
                .font(.system(size: f(10.5), weight: .semibold))
                .padding(.horizontal, s(8))
                .padding(.vertical, s(4))
                .background(Color.black.opacity(0.68))
                .foregroundStyle(.white)
                .clipShape(Capsule(style: .continuous))
              Spacer()
            }
            Spacer()
          }
          .padding(s(10))
        }

        Image(systemName: capture.symbolName)
          .font(.system(size: f(11), weight: .semibold))
          .foregroundStyle(Color.primary.opacity(0.78))
          .frame(width: s(30), height: s(30))
          .background(.regularMaterial, in: Circle())
          .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
          .padding(s(10))

        Image(systemName: "trash")
          .font(.system(size: f(26 * 0.42), weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.92))
          .frame(width: s(26), height: s(26))
          .background(Color.black.opacity(0.48), in: Circle())
          .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
          .padding(s(8))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      }
      .clipShape(cardShape)
      .overlay(
        cardShape.stroke(
          isSelected ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.10),
          lineWidth: isSelected ? max(1.5, s(3)) : 1
        )
      )
      .shadow(
        color: Color.black.opacity(isSelected ? 0.28 : 0.16),
        radius: isSelected ? s(18) : s(3),
        y: isSelected ? s(8) : s(2)
      )
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .aspectRatio(16.0 / 10.0, contentMode: .fit)
  }
}
