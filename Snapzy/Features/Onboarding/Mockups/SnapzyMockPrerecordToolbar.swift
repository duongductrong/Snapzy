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
  var onCapture: (() -> Void)? = nil
  var onCancel: (() -> Void)? = nil

  @State private var hoveredItem: String? = nil
  @State private var isRecordHovered = false

  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      // Curved hint arrow pointing to the Record button
      SnapzyCurvedHintArrow(
        text: "Click Record to start (3s demo)",
        orientation: .curveDownToTarget,
        icon: "record.circle"
      )
      .padding(.trailing, 2)

      // Toolbar floating HUD
      HStack(spacing: 4) {
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
        HStack(spacing: 3) {
          Text("Options")
            .font(.system(size: 11, weight: .regular))
          Image(systemName: "chevron.down")
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(Color.primary.opacity(0.6))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
          RoundedRectangle(cornerRadius: 5)
            .fill(hoveredItem == "options" ? Color.primary.opacity(0.10) : Color.clear)
        )
        .onHover { h in hoveredItem = h ? "options" : nil }

        // Record Button Group: [● Record MP4] [▾]
        HStack(spacing: 1) {
          Button(action: onRecord) {
            HStack(spacing: 4) {
              Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)

              Text("Record MP4")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
              RoundedRectangle(cornerRadius: 6)
                .fill(isRecordHovered ? Color.red.opacity(0.18) : Color.primary.opacity(0.08))
            )
            .overlay(
              RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isRecordHovered ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1)
            )
          }
          .buttonStyle(.plain)
          .onHover { h in isRecordHovered = h }

          Image(systemName: "chevron.down")
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(Color.primary.opacity(0.6))
            .padding(.horizontal, 3)
            .padding(.vertical, 4)
        }
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 5.5)
      .background {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
      }
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
      )
      .shadow(color: Color.black.opacity(0.28), radius: 16, y: 6)
      .shadow(color: Color.black.opacity(0.10), radius: 4, y: 2)
    }
  }

  private func iconButton(id: String, icon: String, isSelected: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(isSelected ? Color(red: 0.16, green: 0.50, blue: 0.98) : Color.primary.opacity(0.85))
        .frame(width: 22, height: 22)
        .background(
          RoundedRectangle(cornerRadius: 5)
            .fill(hoveredItem == id ? Color.primary.opacity(0.10) : Color.clear)
        )
    }
    .buttonStyle(.plain)
    .onHover { h in hoveredItem = h ? id : nil }
  }

  private var divider: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.16))
      .frame(width: 1, height: 16)
      .padding(.horizontal, 2)
  }
}
