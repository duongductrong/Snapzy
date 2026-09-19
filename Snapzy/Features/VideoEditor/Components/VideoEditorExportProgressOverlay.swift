//
//  VideoEditorExportProgressOverlay.swift
//  Snapzy
//
//  Modal overlay showing save/export progress as a circular ring on a glass card.
//

import SwiftUI

/// Modal overlay displayed while the editor saves, exports, or uploads a video.
///
/// Monochrome by design: grays and labels everywhere, with the system accent reserved for the
/// single progress ring. The card surface is the shared Liquid Glass composite, so macOS 26+
/// renders native glass and macOS 13–15 fall back to the layered material automatically.
/// Entry/exit motion is owned by the call site (`VideoEditorMainView`).
struct ExportProgressOverlay: View {
  @ObservedObject var state: VideoEditorState

  /// Spring for progress updates, kept below 14 so it also runs on macOS 13.
  private static let motion = Animation.spring(response: 0.4, dampingFraction: 0.85)

  var body: some View {
    ZStack {
      Rectangle()
        .fill(Color.black.opacity(0.4))
        .ignoresSafeArea()

      card
    }
  }

  private var card: some View {
    VStack(spacing: 20) {
      progressRing

      VStack(spacing: 6) {
        Text(state.progressOperation.title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.primary)

        Text(state.exportStatusMessage)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .padding(28)
    .frame(width: 264)
    .liquidGlassSurface(shape: Radius.rect(Radius.panel))
    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
  }

  // MARK: - Progress Ring

  private var progressRing: some View {
    ZStack {
      Circle()
        .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 6))

      Circle()
        .trim(from: 0, to: max(0.02, CGFloat(state.exportProgress)))
        .stroke(
          ZoomColors.primary,
          style: StrokeStyle(lineWidth: 6, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .animation(Self.motion, value: state.exportProgress)
    }
    .frame(width: 64, height: 64)
    .overlay {
      percentLabel
    }
  }

  private var percentLabel: some View {
    Text("\(Int((state.exportProgress * 100).rounded()))%")
      .font(.system(size: 14, weight: .semibold, design: .rounded))
      .monospacedDigit()
      .foregroundColor(.primary)
      .modifier(NumericTextTransitionModifier())
      .animation(Self.motion, value: state.exportProgress)
  }
}

// MARK: - Numeric Text Transition (macOS 13 compat)

/// Cross-fades digits on macOS 14+ via `.contentTransition(.numericText())`,
/// plain render on macOS 13 where the transition is unavailable.
private struct NumericTextTransitionModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 14.0, *) {
      content.contentTransition(.numericText())
    } else {
      content
    }
  }
}

// MARK: - Preview

#Preview {
  ExportProgressOverlay(
    state: {
      let state = VideoEditorState(url: URL(fileURLWithPath: "/tmp/test.mov"))
      state.isExporting = true
      state.exportProgress = 0.65
      state.exportStatusMessage = L10n.VideoEditor.exporting
      return state
    }()
  )
}
