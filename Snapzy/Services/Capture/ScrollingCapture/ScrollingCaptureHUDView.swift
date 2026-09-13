//
//  ScrollingCaptureHUDView.swift
//  Snapzy
//
//  SwiftUI content for the scrolling capture control HUD.
//  Chrome-free: the capsule glass buttons float on their own so the HUD never reads
//  as a second panel next to the preview rail.
//

import SwiftUI

struct ScrollingCaptureHUDView: View {
  @ObservedObject var model: ScrollingCaptureSessionModel
  let onStart: () -> Void
  let onDone: () -> Void
  let onCancel: () -> Void
  let onToggleAutoScroll: () -> Void

  var body: some View {
    actionButtons
      .fixedSize(horizontal: true, vertical: false)
      .animation(LiquidGlassTokens.settleSpring, value: model.phase)
  }

  // MARK: - Actions

  @ViewBuilder
  private var actionButtons: some View {
    switch model.phase {
    case .ready:
      HStack(spacing: 8) {
        Button(L10n.Common.cancel, action: onCancel)
          .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))

        Button(L10n.ScrollingCapture.startCapture, action: onStart)
          .buttonStyle(.liquidGlass(emphasis: .primary, capsule: true))
          .disabled(!model.canStartCapture)
      }
      .liquidGlassGroup(spacing: 8)

    case .capturing, .finalizing, .saving:
      HStack(spacing: 8) {
        Button(L10n.Common.cancel, action: onCancel)
          .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))
          .disabled(!model.canCancelSession)

        Button(action: onToggleAutoScroll) {
          Label(
            model.isAutoScrolling ? L10n.ScrollingCapture.stopAutoScroll : L10n.ScrollingCapture.autoScroll,
            systemImage: model.isAutoScrolling ? "stop.fill" : "play.fill"
          )
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.liquidGlass(
          emphasis: model.isAutoScrolling ? .primary : .secondary,
          capsule: true
        ))
        .disabled(!model.canToggleAutoScroll)

        Button(L10n.Common.done, action: onDone)
          .buttonStyle(.liquidGlass(emphasis: .primary, capsule: true))
          .disabled(!model.canFinishCapture)
      }
      .liquidGlassGroup(spacing: 8)
    }
  }
}
