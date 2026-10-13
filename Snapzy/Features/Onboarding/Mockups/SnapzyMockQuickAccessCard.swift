//
//  SnapzyMockQuickAccessCard.swift
//  Snapzy
//
//  100% faithful Quick Access Card component matching Snapzy's actual QuickAccessCardView:
//  Compact proportioned sizing (168 × 106pt), 13pt corner radius, default center actions (Copy, Save)
//  and default corner actions (Delete, Dismiss, Annotate, Pin).
//

import SwiftUI

struct SnapzyMockQuickAccessCard: View {
  var isPinned: Bool = false
  var isVideo: Bool = false
  var durationText: String = "00:03"
  var onCopy: (() -> Void)? = nil
  var onSave: (() -> Void)? = nil
  var onAnnotate: (() -> Void)? = nil
  var onTogglePin: (() -> Void)? = nil
  var onDismiss: (() -> Void)? = nil

  @State private var isHovering = false
  @State private var hoveredButton: String? = nil

  // Compact balanced sizing: 144 × 90pt (ratio 1.6:1, matching QuickAccessLayout perfectly)
  private let cardWidth: CGFloat = 144
  private let cardHeight: CGFloat = 90
  private let cornerRadius: CGFloat = 11

  var body: some View {
    ZStack(alignment: .center) {
      // 1. Captured Thumbnail Layer (with slight blur when hovered)
      thumbnailLayer
        .blur(radius: isHovering ? 2.5 : 0)

      // 2. Pin indicator badge in top-left when pinned and not hovering
      if isPinned && !isHovering {
        pinBadge
      }

      // 3. Hover Action Overlay with default Snapzy actions
      if isHovering {
        hoverOverlay
          .transition(.opacity.combined(with: .scale(scale: 0.96)))
      }

      // 4. Subtle swipe hint when not hovered
      if !isHovering {
        VStack {
          Spacer()
          HStack(spacing: 2.5) {
            Image(systemName: "chevron.right")
              .font(.system(size: 6.5, weight: .bold))
            Text(L10n.Onboarding.mockSwipeToDismiss)
              .font(.system(size: 7, weight: .medium))
          }
          .foregroundStyle(Color.white.opacity(0.75))
          .padding(.horizontal, 5)
          .padding(.vertical, 1.5)
          .background(Capsule().fill(Color.black.opacity(0.44)))
          .padding(.bottom, 4.5)
        }
      }
    }
    .frame(width: cardWidth, height: cardHeight)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(
          LinearGradient(
            colors: [Color.white.opacity(0.35), Color.white.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 0.75
        )
    )
    .shadow(color: Color.black.opacity(0.32), radius: 14, x: 0, y: 6)
    .shadow(color: Color.black.opacity(0.10), radius: 3, x: 0, y: 1.5)
    .scaleEffect(isHovering ? 1.02 : 1.0)
    .onHover { hovering in
      withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) {
        isHovering = hovering
      }
    }
    .onTapGesture {
      onAnnotate?()
    }
  }

  // MARK: - Thumbnail Layer

  private var thumbnailLayer: some View {
    ZStack {
      if isVideo {
        videoThumbnail
      } else {
        noteThumbnail
      }
    }
    .frame(width: cardWidth, height: cardHeight)
  }

  private var noteThumbnail: some View {
    ZStack {
      Color(white: 0.96)

      VStack(alignment: .leading, spacing: 2.5) {
        // Mini note bar
        HStack(spacing: 2) {
          Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.33)).frame(width: 3, height: 3)
          Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 3, height: 3)
          Circle().fill(Color(red: 0.15, green: 0.79, blue: 0.25)).frame(width: 3, height: 3)

          Spacer()

          Text("Notes • 420 × 160")
            .font(.system(size: 5.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.black.opacity(0.40))
        }
        .padding(.bottom, 0.5)

        // Note excerpt lines
        Text("At the top, he sat in the keeper’s chair—the one he’d occupied during countless storms...")
          .font(.system(size: 6.5, weight: .regular))
          .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.17))
          .lineSpacing(1.2)
          .lineLimit(2)

        Spacer(minLength: 0)

        // Vector Annotation Mark on Thumbnail
        HStack {
          Image(systemName: "arrow.up.right")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(Color(red: 0.95, green: 0.20, blue: 0.20))

          Spacer()

          RoundedRectangle(cornerRadius: 1.5)
            .strokeBorder(Color(red: 0.95, green: 0.20, blue: 0.20), lineWidth: 0.75)
            .frame(width: 30, height: 10)
        }
      }
      .padding(7)
    }
  }

  private var videoThumbnail: some View {
    ZStack {
      Color(red: 0.94, green: 0.95, blue: 0.96)

      // Mini Finder preview
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 2) {
          Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.33)).frame(width: 3, height: 3)
          Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 3, height: 3)
          Circle().fill(Color(red: 0.15, green: 0.79, blue: 0.25)).frame(width: 3, height: 3)

          Spacer()

          Text("Finder • 440 × 260")
            .font(.system(size: 5.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.black.opacity(0.40))
        }

        HStack(spacing: 3) {
          VStack(alignment: .leading, spacing: 1.5) {
            RoundedRectangle(cornerRadius: 1).fill(Color.blue.opacity(0.7)).frame(width: 16, height: 2.5)
            RoundedRectangle(cornerRadius: 1).fill(Color.black.opacity(0.15)).frame(width: 20, height: 2.5)
            RoundedRectangle(cornerRadius: 1).fill(Color.black.opacity(0.15)).frame(width: 18, height: 2.5)
          }
          .padding(3)
          .background(RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.05)))

          Spacer()
        }

        Spacer(minLength: 0)
      }
      .padding(7)

      // Center Play Overlay
      Circle()
        .fill(Color.black.opacity(0.45))
        .frame(width: 22, height: 22)
        .overlay(
          Image(systemName: "play.fill")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(Color.white)
            .offset(x: 1)
        )

      // Bottom-right duration badge
      VStack {
        Spacer()
        HStack {
          Spacer()
          Text(durationText)
            .font(.system(size: 7, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 4.5)
            .padding(.vertical, 1.5)
            .background(
              RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.72))
            )
            .padding(5)
        }
      }
    }
  }

  // MARK: - Pin Badge

  private var pinBadge: some View {
    VStack {
      HStack {
        Image(systemName: "pin.fill")
          .font(.system(size: 7, weight: .bold))
          .foregroundStyle(Color.orange)
          .frame(width: 14, height: 14)
          .background(
            Circle()
              .fill(Color.black.opacity(0.65))
              .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5))
          )
          .padding(5)

        Spacer()
      }
      Spacer()
    }
  }

  // MARK: - Hover Overlay with Default Actions

  private var hoverOverlay: some View {
    ZStack {
      // Dimming backdrop matching real QuickAccessCardView (black.opacity(0.42))
      Color.black.opacity(0.44)

      // Center Slots: Copy & Save (matching QuickAccessActionSlot.centerSlots defaults)
      VStack(spacing: 5) {
        centerTextButton(
          id: "copy",
          title: "Copy",
          shortcut: "⌘C"
        ) {
          onCopy?()
        }

        centerTextButton(
          id: "save",
          title: "Save",
          shortcut: "⌘S"
        ) {
          onSave?()
        }
      }

      // Corner Slots: Delete, Dismiss, Annotate, Pin (matching QuickAccessActionSlot.cornerSlots defaults)
      VStack {
        HStack {
          cornerIconButton(icon: "trash", tooltip: "Delete") {
            onDismiss?()
          }

          Spacer()

          cornerIconButton(icon: "xmark", tooltip: "Dismiss") {
            onDismiss?()
          }
        }

        Spacer()

        HStack {
          cornerIconButton(
            icon: isVideo ? "scissors" : "pencil.and.outline",
            tooltip: isVideo ? "Edit Video (⌘E)" : "Annotate (⌘E)"
          ) {
            onAnnotate?()
          }

          Spacer()

          cornerIconButton(
            icon: isPinned ? "pin.slash.fill" : "pin.fill",
            tooltip: isPinned ? "Unpin" : "Pin (⌘P)",
            tint: isPinned ? Color.orange : Color.white
          ) {
            onTogglePin?()
          }
        }
      }
      .padding(4.5)
    }
    .frame(width: cardWidth, height: cardHeight)
  }

  // MARK: - Button Helpers

  private func centerTextButton(
    id: String,
    title: String,
    shortcut: String,
    action: @escaping () -> Void
  ) -> some View {
    let isBtnHovered = hoveredButton == id

    return Button(action: action) {
      HStack(spacing: 3.5) {
        Text(title)
          .font(.system(size: 9, weight: .medium))
          .lineLimit(1)

        Text(shortcut)
          .font(.system(size: 7, weight: .semibold, design: .monospaced))
          .foregroundStyle(Color.white.opacity(0.65))
          .lineLimit(1)
      }
      .foregroundStyle(Color.white)
      .padding(.horizontal, 9)
      .padding(.vertical, 3.5)
      .background(
        Capsule()
          .fill(isBtnHovered ? Color.white.opacity(0.35) : Color.black.opacity(0.65))
          .overlay(
            Capsule()
              .strokeBorder(Color.white.opacity(isBtnHovered ? 0.40 : 0.15), lineWidth: 0.5)
          )
      )
      .fixedSize()
    }
    .buttonStyle(.plain)
    .help("\(title) (\(shortcut))")
    .onHover { h in
      withAnimation(.easeInOut(duration: 0.12)) {
        hoveredButton = h ? id : nil
      }
    }
  }

  private func cornerIconButton(
    icon: String,
    tooltip: String,
    tint: Color = .white,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 7.5, weight: .bold))
        .foregroundStyle(tint.opacity(0.90))
        .frame(width: 15, height: 15)
        .background(
          Circle()
            .fill(Color.black.opacity(0.65))
            .overlay(
              Circle()
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5)
            )
        )
    }
    .buttonStyle(.plain)
    .help(tooltip)
  }
}
