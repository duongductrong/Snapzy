import SwiftUI

public struct FeatureIntroView: View {
  public let screens: [FeatureIntroScreen]
  public let onClose: () -> Void

  @State private var currentIndex: Int = 0

  public init(screens: [FeatureIntroScreen], onClose: @escaping () -> Void) {
    self.screens = screens
    self.onClose = onClose
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Top Bar
      HStack {
        Spacer()
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.secondary)
            .padding(8)
            .background(Circle().fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .padding([.top, .trailing], 12)
      }

      // Carousel
      GeometryReader { geometry in
        ZStack {
          HStack(spacing: 0) {
            ForEach(screens) { screen in
              screenView(for: screen, width: geometry.size.width)
            }
          }
          .frame(width: geometry.size.width, alignment: .leading)
          .offset(x: -CGFloat(currentIndex) * geometry.size.width)
          .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentIndex)
        }
        .gesture(
          DragGesture()
            .onEnded { value in
              if value.translation.width < -20 {
                currentIndex = min(screens.count - 1, currentIndex + 1)
              } else if value.translation.width > 20 {
                currentIndex = max(0, currentIndex - 1)
              }
            }
        )
      }

      // Bottom Pagination & Navigation
      bottomBar
    }
    .frame(width: 320, height: 420)
    .background(.regularMaterial, in: Radius.rect(Radius.panel))
  }

  @ViewBuilder
  private func screenView(for screen: FeatureIntroScreen, width: CGFloat) -> some View {
    VStack(spacing: 20) {
      Spacer(minLength: 10)

      // Illustration
      if let systemImage = screen.systemImage {
        Image(systemName: systemImage)
          .font(.system(size: 64, weight: .light))
          .foregroundColor(.primary)
          .frame(height: 100)
      } else if let customImageName = screen.customImageName {
        if customImageName == "AppIcon" {
          Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
            .resizable()
            .scaledToFit()
            .frame(height: 100)
        } else {
          Image(customImageName)
            .resizable()
            .scaledToFit()
            .frame(height: 100)
        }
      } else if let shortcutKeys = screen.shortcutKeys {
        HStack(spacing: 6) {
          ForEach(shortcutKeys.indices, id: \.self) { index in
            Text(shortcutKeys[index])
              .font(.system(size: 24, weight: .medium, design: .rounded))
              .frame(width: 44, height: 44)
              .background(Color.primary.opacity(0.1))
              .cornerRadius(Radius.tile)
              .overlay(
                Radius.rect(Radius.tile)
                  .stroke(Color.primary.opacity(0.1), lineWidth: 1)
              )
          }
        }
        .frame(height: 100)
      } else {
        Spacer().frame(height: 100)
      }

      // Text Content
      VStack(spacing: 12) {
        Text(LocalizedStringKey(screen.title), tableName: tableName(for: screen.title))
          .font(.system(size: 20, weight: .bold))
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
          .fixedSize(horizontal: false, vertical: true)

        if screen.id == "welcome_intro" {
          let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
          Text(String(format: NSLocalizedString(screen.description, tableName: tableName(for: screen.description), comment: ""), version))
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 48)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text(LocalizedStringKey(screen.description), tableName: tableName(for: screen.description))
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 48)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      
      if let nextTitle = screen.nextActionTitle {
        Spacer().frame(height: 16)
        Button(action: {
          currentIndex = min(screens.count - 1, currentIndex + 1)
        }) {
          Text(LocalizedStringKey(nextTitle), tableName: tableName(for: nextTitle))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
      } else if let actionTitle = screen.actionTitle {
        Spacer().frame(height: 16)
        Button(action: {
          screen.action?()
          onClose()
        }) {
          Text(LocalizedStringKey(actionTitle), tableName: tableName(for: actionTitle))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .transition(.opacity)
      }

      Spacer(minLength: 20)
    }
    .frame(width: width)
  }


  private func tableName(for key: String) -> String {
    if key.hasPrefix("whats-new") {
      return "WhatsNew"
    }
    return "Common"
  }

  private var bottomBar: some View {
    HStack {
      // Previous Button
      Button(action: {
        currentIndex = max(0, currentIndex - 1)
      }) {
        Image(systemName: "chevron.left")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(currentIndex > 0 ? .primary : .clear)
          .padding(8)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.leftArrow, modifiers: [])
      .disabled(currentIndex == 0)

      Spacer()

      // Dots
      HStack(spacing: 0) {
        ForEach(0..<screens.count, id: \.self) { index in
          Circle()
            .fill(index == currentIndex ? Color.accentColor : Color.primary.opacity(0.15))
            .frame(width: index == currentIndex ? 8 : 6, height: index == currentIndex ? 8 : 6)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onTapGesture {
              currentIndex = index
            }
            .animation(.spring(), value: currentIndex)
        }
      }

      Spacer()

      // Next Button
      Button(action: {
        currentIndex = min(screens.count - 1, currentIndex + 1)
      }) {
        Image(systemName: "chevron.right")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(currentIndex < screens.count - 1 ? .primary : .clear)
          .padding(8)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.rightArrow, modifiers: [])
      .disabled(currentIndex == screens.count - 1)
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 20)
    .frame(height: 40)
  }
}
