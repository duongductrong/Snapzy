//
//  SnapzyMockPrerecordToolbar.swift
//  Snapzy
//
//  100% faithful replica of Snapzy's Apple-style RecordingToolbarView for Step 2 onboarding.
//  Layout: [✕] | [📷] | [Area ▾] | [🎙 🔊] | [Options ▾] | [● Record MP4 ▾]
//

import SwiftUI

struct SnapzyMockPrerecordToolbar: View {
  let onRecord: () -> Void
  var onCapture: (() -> Void)?
  var onCancel: (() -> Void)?

  @State private var hoveredItem: String? = nil
  @State private var isRecordHovered = false

  var body: some View {
    VStack(alignment: .trailing, spacing: SnapzySpace.xs) {
      // Curved hint arrow pointing to the Record button
      SnapzyCurvedHintArrow(
        text: L10n.Onboarding.mockRecordHint,
        orientation: .curveDownToTarget,
        arrowAlignment: .trailing,
        color: .white
      )
      .padding(.trailing, 2)

      // Toolbar floating HUD
      HStack(spacing: SnapzySpace.xs) {
        // Close button
        iconButton(id: "cancel", icon: "xmark") {
          onCancel?()
        }

        divider

        // Camera snapshot
        iconButton(id: "camera", icon: "camera") {
          onCapture?()
        }

        divider

        // Capture area toggle
        HStack(spacing: 2) {
          iconButton(id: "area", icon: "rectangle.dashed", isSelected: true) {}
          iconButton(id: "fullscreen", icon: "display", isSelected: false) {}
        }

        divider

        // Audio controls
        HStack(spacing: 2) {
          iconButton(id: "mic", icon: "mic.fill", isSelected: true) {}
          iconButton(id: "audio", icon: "speaker.wave.2.fill", isSelected: true) {}
        }

        divider

        // Options dropdown
        HStack(spacing: SnapzySpace.xxs) {
          Text(L10n.RecordingToolbar.options)
            .font(.system(size: 11, weight: .regular))
          Image(systemName: "chevron.down")
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(SnapzyGlassInk.muted)
        }
        .padding(.horizontal, SnapzySpace.sm)
        .padding(.vertical, SnapzySpace.xs)
        .background(
          Radius.rect(Radius.controlXS)
            .fill(hoveredItem == "options" ? SnapzyGlassInk.fillHover : Color.clear)
        )
        .onHover { h in hoveredItem = h ? "options" : nil }

        // Record Button Group: [● Record MP4] [▾]
        HStack(spacing: 1) {
          Button(action: onRecord) {
            HStack(spacing: SnapzySpace.xs) {
              Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)

              Text(L10n.Onboarding.mockRecordMp4)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(SnapzyGlassInk.primary)
            }
            .padding(.horizontal, SnapzySpace.md)
            .padding(.vertical, 4.5)
            .background(
              Radius.rect(Radius.controlM)
                .fill(isRecordHovered ? Color.red.opacity(0.18) : SnapzyGlassInk.fillRaised)
            )
            .overlay(
              Radius.rect(Radius.controlM)
                .strokeBorder(isRecordHovered ? Color.red.opacity(0.4) : Color.clear,
                              lineWidth: 1)
            )
          }
          .buttonStyle(.plain)
          .onHover { h in isRecordHovered = h }

          Image(systemName: "chevron.down")
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(SnapzyGlassInk.muted)
            .padding(.horizontal, SnapzySpace.xxs)
            .padding(.vertical, SnapzySpace.xs)
        }
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 5.5)
      .background {
        SnapzyGlassSurface(
          shape: Radius.rect(Radius.controlL),
          substrate: SnapzySurfaceGlass.baseDarkness,
          tint: 0.12
        )
      }
      .clipShape(Radius.rect(Radius.controlL))
      .shadow(color: SnapzyGlassShadow.controlColor, radius: SnapzyGlassShadow.controlRadius,
              y: SnapzyGlassShadow.controlY)
      .shadow(color: Color.black.opacity(0.10), radius: SnapzySpace.xs, y: 2)
    }
  }

  private func iconButton(id: String, icon: String, isSelected: Bool = false,
                          action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(isSelected ? SnapzyMockPalette.toggleAccent : SnapzyGlassInk.body)
        .frame(width: 22, height: 22)
        .background(
          Radius.rect(Radius.controlXS)
            .fill(hoveredItem == id ? SnapzyGlassInk.fillHover : Color.clear)
        )
    }
    .buttonStyle(.plain)
    .onHover { h in hoveredItem = h ? id : nil }
  }

  private var divider: some View {
    Rectangle()
      .fill(SnapzyGlassInk.hairlineStrong)
      .frame(width: 1, height: 16)
      .padding(.horizontal, 2)
  }
}
