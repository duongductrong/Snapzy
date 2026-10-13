import SwiftUI

struct PinZoomModeComparisonPreview: View {
  let selectedMode: QuickAccessPinZoomMode
  let onSelect: (QuickAccessPinZoomMode) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var stage = 0

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      demo(mode: .windowFollowsImage)
      demo(mode: .fixedViewport)
    }
    .padding(12)
    .frame(maxWidth: 520)
    .frame(maxWidth: .infinity, alignment: .center)
    .task(id: reduceMotion) { await play() }
  }

  private func demo(mode: QuickAccessPinZoomMode) -> some View {
    let isSelected = selectedMode == mode

    return Button {
      onSelect(mode)
    } label: {
      ZStack {
      PinZoomDiagram(mode: mode, stage: stage, reduceMotion: reduceMotion)
        .frame(height: 152)
        .frame(maxWidth: .infinity)
        // The moving diagram repeats the labelled modes and adjacent picker; keep it decorative.
        .accessibilityHidden(true)
    }
    .frame(height: 189)
    .overlay(alignment: .topLeading) {
      HStack(spacing: 5) {
        Text(mode.title)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.primary)
          .lineLimit(2)
          .minimumScaleFactor(0.78)
          .accessibilityAddTraits(isSelected ? .isSelected : [])

        Spacer(minLength: 0)

        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 30, alignment: .topLeading)
    }
    .padding(8)
    .frame(maxWidth: .infinity)
    .background(
      Color(nsColor: .windowBackgroundColor).opacity(isSelected ? 0.72 : 0.46),
      in: Radius.rect(Radius.tile)
    )
    .overlay(
      Radius.rect(Radius.tile)
        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
    )
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityValue(mode.title)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  @MainActor private func play() async {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      stage = reduceMotion ? 2 : 0
    }

    guard !reduceMotion else { return }

    while !Task.isCancelled {
      for nextStage in [1, 2, 3, 4, 0] {
        do {
          try await Task.sleep(for: .milliseconds(700))
        } catch {
          return
        }

        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
          stage = nextStage
        }
      }

      do {
        try await Task.sleep(for: .milliseconds(150))
      } catch {
        return
      }
    }
  }
}

private struct PinZoomDiagram: View {
  let mode: QuickAccessPinZoomMode
  let stage: Int
  let reduceMotion: Bool

  var body: some View {
    GeometryReader { proxy in
      let available = proxy.size
      let initialWidth = min(available.width * 0.9, available.height * 0.8)
      let initialHeight = initialWidth * 0.65
      let isFixed = mode == .fixedViewport
      let availableWindowScale = min(
        available.width * 0.98 / initialWidth,
        available.height * 0.9 / initialHeight
      )
      let maximumWindowScale = min(1.34, availableWindowScale)
      let windowScale = isFixed
        ? 1
        : 1 + (maximumWindowScale - 1) * windowGrowthProgress
      let windowWidth = initialWidth * windowScale
      let windowHeight = initialHeight * windowScale

      ZStack {
        Radius.rect(Radius.tile)
          .fill(Color.primary.opacity(0.045))
          .frame(width: windowWidth, height: windowHeight)
          .overlay {
            if isFixed {
              fixedViewportPage(initialWidth: initialWidth, initialHeight: initialHeight)
            } else {
              PinZoomFakePage()
                .frame(width: initialWidth * 0.92, height: initialHeight)
                .scaleEffect(windowScale, anchor: .center)
            }
          }
          .overlay(Radius.rect(Radius.tile).stroke(Color.primary.opacity(0.28), lineWidth: 1))
          .clipShape(Radius.rect(Radius.tile))
          .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
          .position(x: available.width / 2, y: available.height / 2)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var windowGrowthProgress: CGFloat {
    if reduceMotion { return 1 }

    switch stage {
    case 1: return 1.0 / 3.0
    case 2: return 2.0 / 3.0
    case 3, 4: return 1
    default: return 0
    }
  }

  private func fixedViewportPage(initialWidth: CGFloat, initialHeight: CGFloat) -> some View {
    let pageScale = stage == 0 ? 1.0 : 1.58
    let offset = fixedViewportOffset(initialWidth: initialWidth, initialHeight: initialHeight)

    return PinZoomFakePage()
      .frame(width: initialWidth * 0.94, height: initialHeight * 1.5)
      .scaleEffect(pageScale, anchor: .center)
      .offset(offset)
  }

  private func fixedViewportOffset(initialWidth: CGFloat, initialHeight: CGFloat) -> CGSize {
    switch stage {
    case 2:
      return CGSize(width: -initialWidth * 0.16, height: -initialHeight * 0.2)
    case 3:
      return CGSize(width: initialWidth * 0.14, height: initialHeight * 0.18)
    default:
      return .zero
    }
  }
}

private struct PinZoomFakePage: View {
  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 5) {
          RoundedRectangle(cornerRadius: 3, style: .continuous) // radius-lint:allow — miniature page illustration drawn at thumbnail scale
            .fill(
              LinearGradient(
                colors: [Color.accentColor.opacity(0.84), Color.purple.opacity(0.62)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(height: 23)

          VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2, style: .continuous) // radius-lint:allow — miniature page illustration drawn at thumbnail scale
              .fill(Color.orange.opacity(0.68))
            RoundedRectangle(cornerRadius: 2, style: .continuous) // radius-lint:allow — miniature page illustration drawn at thumbnail scale
              .fill(Color.teal.opacity(0.56))
          }
          .frame(width: 22, height: 23)
        }

        HStack(spacing: 4) {
          ForEach(0..<3, id: \.self) { index in
            RoundedRectangle(cornerRadius: 2, style: .continuous) // radius-lint:allow — miniature page illustration drawn at thumbnail scale
              .fill(index == 0 ? Color.blue.opacity(0.25) : Color.primary.opacity(0.08))
              .frame(height: 15)
              .overlay(alignment: .bottomLeading) {
                Capsule()
                  .fill(Color.primary.opacity(0.18))
                  .frame(width: index == 0 ? 13 : 9, height: 2)
                  .padding(3)
              }
          }
        }

        VStack(alignment: .leading, spacing: 3) {
          RoundedRectangle(cornerRadius: 1.5, style: .continuous) // radius-lint:allow — miniature text line drawn at thumbnail scale
            .fill(Color.primary.opacity(0.18)).frame(width: 46, height: 3)
          RoundedRectangle(cornerRadius: 1.5, style: .continuous) // radius-lint:allow — miniature text line drawn at thumbnail scale
            .fill(Color.primary.opacity(0.1)).frame(height: 3)
          RoundedRectangle(cornerRadius: 1.5, style: .continuous) // radius-lint:allow — miniature text line drawn at thumbnail scale
            .fill(Color.primary.opacity(0.1)).frame(width: 34, height: 3)
        }

        Spacer(minLength: 0)
      }
      .padding(6)
    }
    .background(Color(nsColor: .textBackgroundColor))
    .clipShape(Radius.rect(Radius.ornament))
  }
}
