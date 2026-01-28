# Phase 2: Wallpaper Sidebar Section

**Date:** 2026-01-28
**Status:** Pending
**Priority:** High
**Estimated:** 1.5 hours

## Context Links

- [Main Plan](./plan.md)
- [Phase 1: State Model](./phase-01-state-model-updates.md)

## Overview

Add `VideoWallpaperSection` to `VideoBackgroundSidebarView` that displays system wallpapers and allows custom wallpaper selection. Follow existing patterns from `SidebarWallpaperSection` in Annotate feature.

## Key Insights

1. `SidebarWallpaperSection` uses `@StateObject private var systemManager = SystemWallpaperManager.shared`
2. Grid layout uses `GridConfig.backgroundColumns` (4 columns)
3. System wallpapers loaded via `.task { await systemManager.loadSystemWallpapers() }`
4. Custom wallpapers stored in `@State private var customWallpapers: [URL]`
5. Auto-padding applied when selecting wallpaper: `if state.padding <= 0 { state.padding = 24 }`

## Requirements

- [ ] Create `VideoSystemWallpaperButton` component
- [ ] Create `VideoCustomWallpaperButton` component
- [ ] Create `VideoAddWallpaperButton` component
- [ ] Create `VideoWallpaperSection` view
- [ ] Integrate section into `VideoBackgroundSidebarView`

## Related Code Files

| File | Purpose | Action |
|------|---------|--------|
| `/ClaudeShot/Features/VideoEditor/Views/VideoEditorSidebarComponents.swift` | Sidebar components | Add wallpaper buttons |
| `/ClaudeShot/Features/VideoEditor/Views/VideoBackgroundSidebarView.swift` | Sidebar view | Add wallpaper section |
| `/ClaudeShot/Features/Annotate/Views/AnnotateSidebarSections.swift` | Reference pattern | Read only |

## Implementation Steps

### Step 1: Add Wallpaper Button Components

**File:** `/ClaudeShot/Features/VideoEditor/Views/VideoEditorSidebarComponents.swift`

Add after `VideoSliderRow` (after line 86):

```swift
// MARK: - System Wallpaper Button

struct VideoSystemWallpaperButton: View {
  let item: SystemWallpaperManager.WallpaperItem
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      AsyncImage(url: item.thumbnailURL ?? item.fullImageURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        case .failure:
          Rectangle().fill(Color.gray.opacity(0.3))
        case .empty:
          Rectangle().fill(Color.gray.opacity(0.2))
        @unknown default:
          Rectangle().fill(Color.gray.opacity(0.2))
        }
      }
      .frame(height: Size.swatchHeightLg)
      .clipped()
      .cornerRadius(Size.radiusMd)
      .sidebarItemStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Custom Wallpaper Button

struct VideoCustomWallpaperButton: View {
  let url: URL
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        case .failure:
          Rectangle().fill(Color.gray.opacity(0.3))
        case .empty:
          Rectangle().fill(Color.gray.opacity(0.2))
        @unknown default:
          Rectangle().fill(Color.gray.opacity(0.2))
        }
      }
      .frame(height: Size.swatchHeightLg)
      .clipped()
      .cornerRadius(Size.radiusMd)
      .sidebarItemStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Add Wallpaper Button

struct VideoAddWallpaperButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      RoundedRectangle(cornerRadius: Size.radiusMd)
        .fill(SidebarColors.itemDefault)
        .frame(height: Size.swatchHeightLg)
        .overlay(
          Image(systemName: "plus")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(SidebarColors.labelSecondary)
        )
        .overlay(
          RoundedRectangle(cornerRadius: Size.radiusMd)
            .stroke(SidebarColors.border, lineWidth: Size.strokeDefault)
        )
    }
    .buttonStyle(.plain)
  }
}
```

### Step 2: Add Wallpaper Section to Sidebar

**File:** `/ClaudeShot/Features/VideoEditor/Views/VideoBackgroundSidebarView.swift`

Add import and state at top of struct (after line 12):

```swift
@StateObject private var systemManager = SystemWallpaperManager.shared
@State private var customWallpapers: [URL] = []
```

Add wallpaper section in body after `gradientSection` (after line 18):

```swift
wallpaperSection
```

Add wallpaper section computed property (after `gradientSection` property, around line 76):

```swift
// MARK: - Wallpaper Section

private var wallpaperSection: some View {
  VStack(alignment: .leading, spacing: Spacing.sm) {
    VideoSidebarSectionHeader(title: "Wallpapers")

    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.backgroundColumns), spacing: GridConfig.gap) {
      // System wallpapers
      ForEach(systemManager.systemWallpapers) { item in
        VideoSystemWallpaperButton(
          item: item,
          isSelected: isSystemWallpaperSelected(item)
        ) {
          selectSystemWallpaper(item)
        }
      }

      // Custom wallpapers
      ForEach(customWallpapers, id: \.self) { url in
        VideoCustomWallpaperButton(
          url: url,
          isSelected: isWallpaperUrlSelected(url)
        ) {
          selectCustomWallpaper(url)
        }
      }

      // Add button
      VideoAddWallpaperButton {
        addCustomWallpaper()
      }
    }

    // Loading indicator
    if systemManager.isLoading {
      HStack {
        ProgressView()
          .scaleEffect(0.6)
        Text("Loading wallpapers...")
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
      }
    }
  }
  .task {
    await systemManager.loadSystemWallpapers()
  }
}

// MARK: - Wallpaper Helpers

private func isSystemWallpaperSelected(_ item: SystemWallpaperManager.WallpaperItem) -> Bool {
  if case .wallpaper(let url) = state.backgroundStyle {
    return url == item.fullImageURL
  }
  return false
}

private func isWallpaperUrlSelected(_ url: URL) -> Bool {
  if case .wallpaper(let selectedUrl) = state.backgroundStyle {
    return selectedUrl == url
  }
  return false
}

private func selectSystemWallpaper(_ item: SystemWallpaperManager.WallpaperItem) {
  if state.backgroundPadding <= 0 {
    state.backgroundPadding = 24
  }
  state.backgroundStyle = .wallpaper(item.fullImageURL)
}

private func selectCustomWallpaper(_ url: URL) {
  if state.backgroundPadding <= 0 {
    state.backgroundPadding = 24
  }
  state.backgroundStyle = .wallpaper(url)
}

private func addCustomWallpaper() {
  let panel = NSOpenPanel()
  panel.allowedContentTypes = [.image]
  panel.allowsMultipleSelection = false

  if panel.runModal() == .OK, let url = panel.url {
    customWallpapers.append(url)
    selectCustomWallpaper(url)
  }
}
```

Add AppKit import at top of file:

```swift
import AppKit
```

## Success Criteria

- [ ] System wallpapers display in grid
- [ ] Wallpaper thumbnails load asynchronously
- [ ] Selection highlights correctly
- [ ] Custom wallpaper picker opens file dialog
- [ ] Padding auto-applies on wallpaper selection
- [ ] Loading indicator shows during wallpaper fetch

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| AsyncImage performance | Medium | Low | Thumbnails are small; system caches |
| File access denied | Low | Medium | SystemWallpaperManager handles gracefully |
| Memory with many wallpapers | Low | Low | AsyncImage manages memory automatically |
