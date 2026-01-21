# Phase 5: Post-Recording Flow

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** Phase 1 (ScreenRecorderManager), Phase 4 (Active State)
- **Research:** [UX Patterns Report](./research/researcher-02-ux-patterns-report.md)

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Priority | P1 - High |
| Status | pending |
| Effort | 2-3 hours |

After recording stops: generate video thumbnail, show floating card with Copy/Save actions, click opens VideoEditorStub.

## Key Insights
1. Reuse `FloatingCardView` pattern but route to VideoEditorStub instead of Annotate
2. Generate thumbnail from first frame using AVAssetImageGenerator
3. Copy action copies file URL to clipboard (not video data - too large)
4. VideoEditorStub is placeholder view for future editing features

## Requirements

### Functional
- [x] Generate thumbnail from recorded video
- [x] Show floating thumbnail card after recording
- [x] Copy button copies video file URL to clipboard
- [x] Save button saves to Desktop (or configured location)
- [x] Click thumbnail opens VideoEditorStub
- [x] Auto-dismiss after timeout (optional)

### Non-Functional
- Thumbnail generation < 1 second
- Card matches screenshot card aesthetic
- Play icon overlay on thumbnail

## Architecture

```
Recording Stops
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│            VideoThumbnailGenerator                       │
│  + generateThumbnail(from: URL) async -> NSImage?       │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│              FloatingVideoCardView                       │
│  - thumbnail: NSImage                                    │
│  - videoURL: URL                                         │
│  - Actions: Copy, Save, Dismiss                          │
│  - Click -> VideoEditorStub                              │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│               VideoEditorStubView                        │
│  - Placeholder for future video editing                  │
│  - Shows video player + "Coming Soon" message            │
└─────────────────────────────────────────────────────────┘
```

## Related Code Files
| File | Purpose |
|------|---------|
| `ZapShot/Features/FloatingScreenshot/FloatingCardView.swift` | Pattern for video card |
| `ZapShot/Features/FloatingScreenshot/ThumbnailGenerator.swift` | Reference for thumbnail |
| `ZapShot/Features/Annotate/Window/AnnotateWindowController.swift` | Pattern for editor window |

## Code Draft

### VideoThumbnailGenerator.swift

```swift
//
//  VideoThumbnailGenerator.swift
//  ZapShot
//
//  Generates thumbnail images from video files
//

import AVFoundation
import AppKit

struct VideoThumbnailGenerator {

  /// Generate thumbnail from video at URL
  /// - Parameter url: Video file URL
  /// - Returns: Thumbnail image or nil if failed
  static func generateThumbnail(from url: URL) async -> NSImage? {
    let asset = AVAsset(url: url)
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true
    imageGenerator.maximumSize = CGSize(width: 360, height: 225)

    let time = CMTime(seconds: 0.5, preferredTimescale: 600)

    do {
      let cgImage = try await imageGenerator.image(at: time).image
      return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    } catch {
      // Fallback: try first frame
      do {
        let cgImage = try await imageGenerator.image(at: .zero).image
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
      } catch {
        print("Failed to generate video thumbnail: \(error)")
        return nil
      }
    }
  }
}
```

### FloatingVideoCardView.swift

```swift
//
//  FloatingVideoCardView.swift
//  ZapShot
//
//  Floating card for video recordings with Copy/Save actions
//

import SwiftUI

struct FloatingVideoCardView: View {
  let videoURL: URL
  let thumbnail: NSImage
  let onDismiss: () -> Void

  @State private var isHovering = false

  private let cardWidth: CGFloat = 180
  private let cardHeight: CGFloat = 112.5
  private let cornerRadius: CGFloat = 10

  var body: some View {
    ZStack(alignment: .center) {
      // Thumbnail with play overlay
      ZStack {
        Image(nsImage: thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: cardWidth, height: cardHeight)
          .clipped()
          .blur(radius: isHovering ? 2 : 0)

        // Play icon
        if !isHovering {
          Image(systemName: "play.circle.fill")
            .font(.system(size: 36))
            .foregroundColor(.white.opacity(0.85))
            .shadow(radius: 4)
        }
      }
      .cornerRadius(cornerRadius)

      // Hover overlay
      if isHovering {
        hoverOverlay
          .transition(.opacity.combined(with: .scale(scale: 0.95)))
      }

      // Dismiss button
      if isHovering {
        dismissButton
          .transition(.opacity)
      }
    }
    .frame(width: cardWidth, height: cardHeight)
    .background(
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.black.opacity(0.1))
    )
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius)
        .stroke(Color.white.opacity(0.2), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.2)) {
        isHovering = hovering
      }
    }
    .onTapGesture(count: 2) {
      openVideoEditor()
    }
  }

  private var hoverOverlay: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.black.opacity(0.4))

      VStack(spacing: 8) {
        Button("Copy") { copyToClipboard() }
          .buttonStyle(CardTextButtonStyle())

        Button("Save") { saveToDesktop() }
          .buttonStyle(CardTextButtonStyle())
      }
    }
  }

  private var dismissButton: some View {
    VStack {
      HStack {
        Spacer()
        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.black.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .padding(6)
      }
      Spacer()
    }
  }

  private func copyToClipboard() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([videoURL as NSURL])
  }

  private func saveToDesktop() {
    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    let filename = videoURL.lastPathComponent
    let destination = desktop.appendingPathComponent(filename)

    do {
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.copyItem(at: videoURL, to: destination)
      NSWorkspace.shared.selectFile(destination.path, inFileViewerRootedAtPath: "")
    } catch {
      print("Failed to save video: \(error)")
    }
  }

  private func openVideoEditor() {
    VideoEditorController.shared.open(videoURL: videoURL)
  }
}

// Reuse or create simple button style
private struct CardTextButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .foregroundColor(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 6)
      .background(Color.white.opacity(configuration.isPressed ? 0.3 : 0.2))
      .cornerRadius(6)
  }
}
```

### VideoEditorStubView.swift

```swift
//
//  VideoEditorStubView.swift
//  ZapShot
//
//  Placeholder view for future video editing features
//

import AVKit
import SwiftUI

struct VideoEditorStubView: View {
  let videoURL: URL

  var body: some View {
    VStack(spacing: 20) {
      // Video player
      VideoPlayer(player: AVPlayer(url: videoURL))
        .frame(minWidth: 640, minHeight: 360)
        .cornerRadius(8)

      // Coming soon message
      VStack(spacing: 8) {
        Image(systemName: "film.stack")
          .font(.system(size: 32))
          .foregroundColor(.secondary)

        Text("Video Editor Coming Soon")
          .font(.headline)

        Text("For now, you can preview your recording here.\nUse Copy or Save from the floating thumbnail.")
          .font(.caption)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding()

      // Actions
      HStack(spacing: 16) {
        Button("Reveal in Finder") {
          NSWorkspace.shared.selectFile(videoURL.path, inFileViewerRootedAtPath: "")
        }

        Button("Save to Desktop") {
          saveToDesktop()
        }
        .buttonStyle(.borderedProminent)
      }
      .padding(.bottom)
    }
    .padding()
    .frame(minWidth: 700, minHeight: 500)
  }

  private func saveToDesktop() {
    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    let destination = desktop.appendingPathComponent(videoURL.lastPathComponent)

    do {
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.copyItem(at: videoURL, to: destination)
    } catch {
      print("Failed to save: \(error)")
    }
  }
}
```

### VideoEditorController.swift

```swift
//
//  VideoEditorController.swift
//  ZapShot
//
//  Controller for video editor window
//

import AppKit
import SwiftUI

@MainActor
final class VideoEditorController {
  static let shared = VideoEditorController()

  private var window: NSWindow?

  func open(videoURL: URL) {
    // Close existing window
    window?.close()

    let content = VideoEditorStubView(videoURL: videoURL)
    let hostingView = NSHostingView(rootView: content)

    let newWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )

    newWindow.title = "Video Recording"
    newWindow.contentView = hostingView
    newWindow.center()
    newWindow.makeKeyAndOrderFront(nil)

    window = newWindow
    NSApp.activate(ignoringOtherApps: true)
  }
}
```

## Implementation Steps

### Step 1: Create VideoThumbnailGenerator.swift
- [ ] Create `ZapShot/Features/Recording/VideoThumbnailGenerator.swift`
- [ ] Implement async thumbnail generation with AVAssetImageGenerator

### Step 2: Create FloatingVideoCardView.swift
- [ ] Create `ZapShot/Features/Recording/FloatingVideoCardView.swift`
- [ ] Add thumbnail display with play overlay
- [ ] Add Copy/Save actions on hover
- [ ] Route double-click to VideoEditorController

### Step 3: Create VideoEditorStubView.swift
- [ ] Create `ZapShot/Features/Recording/VideoEditorStubView.swift`
- [ ] Add VideoPlayer for preview
- [ ] Add "Coming Soon" placeholder text
- [ ] Add Save/Reveal actions

### Step 4: Create VideoEditorController.swift
- [ ] Create `ZapShot/Features/Recording/VideoEditorController.swift`
- [ ] Manage editor window lifecycle

### Step 5: Integrate with recording flow
- [ ] After stopRecording(), generate thumbnail
- [ ] Show FloatingVideoCardView via FloatingPanelController
- [ ] Handle card dismiss/timeout

## Todo
- [ ] Create VideoThumbnailGenerator.swift
- [ ] Create FloatingVideoCardView.swift
- [ ] Create VideoEditorStubView.swift
- [ ] Create VideoEditorController.swift
- [ ] Integrate post-recording flow
- [ ] Test Copy/Save actions

## Success Criteria
1. Thumbnail generated from video within 1 second
2. Floating card appears after recording stops
3. Card shows play icon overlay
4. Copy copies file URL to clipboard
5. Save copies to Desktop and reveals in Finder
6. Double-click opens VideoEditorStub window
7. Video plays in editor stub

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Thumbnail gen fails | Low | Medium | Show placeholder icon |
| Large file copy slow | Medium | Low | Show progress indicator |

## Security Considerations
- Video files in temp directory - clean up on app quit
- No sensitive data in clipboard (just file reference)

## Next Steps
This completes MVP. Future enhancements:
- Video trimming in editor
- Add annotations overlay
- Custom export formats
- Cloud upload integration

## Unresolved Questions
1. Auto-dismiss timeout for card? 5s? 10s? Never?
2. Should we clean up temp video files after save?
3. Max video file size before warning user?
