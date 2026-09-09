//
//  SnapzyMockQuickAccessView.swift
//  Snapzy
//
//  Step 2 interactive mockup: Natural Desktop Staging with authentic
//  floating Quick Access card, hover action buttons, pin badge, and swipe indicators.
//

import SwiftUI

struct SnapzyMockQuickAccessView: View {
  @ObservedObject var state: SnapzyOnboardingState
  @State private var feedbackMessage: String? = nil

  var body: some View {
    ZStack(alignment: .top) {
      // 1. macOS Desktop Wallpaper Canvas
      SnapzyMockWallpaper(app: .notes).equatable()

      // 2. Apple Notes Window in Background
      VStack(spacing: 0) {
        Spacer(minLength: 16)

        SnapzyMockNotesWindow().equatable()
          .frame(maxWidth: 470)
          .padding(.horizontal, 24)

        Spacer(minLength: 16)
      }
      .padding(.top, 28) // Room for Menu Bar

      // 3. macOS Menu Bar & Camera Notch
      SnapzyMockMenuBar(app: .notes).equatable()

      // 4. Natural Desktop Staging: Floating Quick Access Card in bottom-left
      VStack {
        Spacer()

        HStack {
          SnapzyMockQuickAccessCard(
            isPinned: state.isCardPinned,
            onCopy: {
              triggerFeedback("Copied to Clipboard (⌘C)")
            },
            onSave: {
              triggerFeedback("Saved to Desktop (⌘S)")
            },
            onAnnotate: {
              triggerFeedback("Opening Editor (⌘E)")
            },
            onTogglePin: {
              withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
                state.isCardPinned.toggle()
              }
              triggerFeedback(state.isCardPinned ? "Pinned on Screen (⌘P)" : "Unpinned")
            },
            onDismiss: {
              triggerFeedback("Dismissed card")
            }
          )
          .padding(.leading, 24)
          .padding(.bottom, 22)

          Spacer()
        }
      }

      // 5. Toast Feedback Overlay
      if let feedback = feedbackMessage {
        VStack {
          Spacer()
          HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(Color.green)
            Text(feedback)
              .font(.system(size: 11.5, weight: .semibold))
              .foregroundStyle(Color.white)
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background {
            SnapzyGlassSurface(
              shape: Capsule(style: .continuous),
              substrate: SnapzySurfaceGlass.baseDarkness,
              tint: 0.10
            )
          }
          .clipShape(Capsule(style: .continuous))
          .shadow(color: Color.black.opacity(0.35), radius: 12, y: 6)
          .padding(.bottom, 16)
          .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func triggerFeedback(_ message: String) {
    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      feedbackMessage = message
      state.simulateQuickAccessAction(message)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
      withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
        if self.feedbackMessage == message {
          self.feedbackMessage = nil
        }
      }
    }
  }
}
