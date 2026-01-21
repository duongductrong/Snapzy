# Phase 03: Floating Card UI

## Context

- [Main Plan](./plan.md)
- [Phase 02: Screenshot Stack Manager](./phase-02-screenshot-stack-manager.md)
- [Research: SwiftUI Cards](./research/researcher-02-swiftui-cards.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 260115 |
| Description | SwiftUI views for floating screenshot cards with hover interactions |
| Priority | High |
| Status | `pending` |
| Estimated Effort | 3-4 hours |

## Requirements

1. **FloatingCardView** - single card with thumbnail, hover buttons
2. **FloatingStackView** - container for multiple cards
3. **Hover interaction** - buttons appear on hover, centered vertically
4. **Animations** - smooth entry/exit, hover transitions
5. **Visual design** - rounded corners, subtle shadow, clean appearance
6. **Action buttons** - copy, open in Finder, dismiss

## Architecture

```
FloatingStackView
├── VStack of FloatingCardView items
├── Observes FloatingScreenshotManager.items
├── Entry animation for new cards
└── Exit animation for removed cards

FloatingCardView
├── Image thumbnail (aspect fit)
├── Hover overlay with action buttons
├── Dismiss button (always visible, corner)
├── Card styling (rounded, shadow)
└── State:
    ├── isHovering: Bool
    └── Animation triggers

ActionButton
├── Icon-only circular button
├── Copy, Finder, Dismiss actions
└── Tooltip on hover
```

## Related Files

| File | Action | Purpose |
|------|--------|---------|
| `ZapShot/Features/FloatingScreenshot/FloatingCardView.swift` | Create | Single card component |
| `ZapShot/Features/FloatingScreenshot/FloatingStackView.swift` | Create | Stack container |
| `ZapShot/Features/FloatingScreenshot/CardActionButton.swift` | Create | Reusable button |

## Implementation Steps

### Step 1: Create CardActionButton

```swift
// CardActionButton.swift
import SwiftUI

struct CardActionButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isHovering ? Color.white.opacity(0.3) : Color.black.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help(tooltip)
    }
}
```

### Step 2: Create FloatingCardView

```swift
// FloatingCardView.swift
import SwiftUI

struct FloatingCardView: View {
    let item: ScreenshotItem
    let onCopy: () -> Void
    let onOpenFinder: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false
    @State private var appeared = false

    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 112
    private let cornerRadius: CGFloat = 10

    var body: some View {
        ZStack(alignment: .center) {
            // Thumbnail
            Image(nsImage: item.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
                .cornerRadius(cornerRadius)

            // Hover overlay with buttons
            if isHovering {
                hoverOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Dismiss button (always visible, top-right)
            dismissButton
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.1))
        )
        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.8)
        .offset(y: appeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }

    private var hoverOverlay: some View {
        ZStack {
            // Dimming overlay
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.4))

            // Action buttons (vertical, centered)
            VStack(spacing: 12) {
                CardActionButton(icon: "doc.on.doc", tooltip: "Copy to Clipboard") {
                    onCopy()
                }

                CardActionButton(icon: "folder", tooltip: "Show in Finder") {
                    onOpenFinder()
                }
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
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0.6)
                .padding(6)
            }
            Spacer()
        }
    }
}
```

### Step 3: Create FloatingStackView

```swift
// FloatingStackView.swift
import SwiftUI

struct FloatingStackView: View {
    @ObservedObject var manager: FloatingScreenshotManager

    private let spacing: CGFloat = 8
    private let padding: CGFloat = 10

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(manager.items) { item in
                FloatingCardView(
                    item: item,
                    onCopy: {
                        manager.copyToClipboard(id: item.id)
                        showCopiedFeedback()
                    },
                    onOpenFinder: {
                        manager.openInFinder(id: item.id)
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            manager.removeScreenshot(id: item.id)
                        }
                    }
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .scale(scale: 0.8))
                    )
                )
            }
        }
        .padding(padding)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.items.count)
    }

    private func showCopiedFeedback() {
        // Optional: Play sound or show brief visual feedback
        NSSound(named: "Pop")?.play()
    }
}
```

### Step 4: Update FloatingPanelController to use FloatingStackView

Add method to show stack view with manager binding.

```swift
// In FloatingPanelController.swift - add method
func showStackView(manager: FloatingScreenshotManager) {
    let stackView = FloatingStackView(manager: manager)
    // Calculate initial size
    let cardHeight: CGFloat = 120
    let spacing: CGFloat = 8
    let padding: CGFloat = 12
    let width: CGFloat = 220
    let itemCount = max(1, manager.items.count)
    let height = CGFloat(itemCount) * cardHeight + CGFloat(itemCount - 1) * spacing + padding * 2

    show(stackView, size: CGSize(width: width, height: height))
}
```

## Design Specifications

| Element | Value |
|---------|-------|
| Card width | 200px |
| Card height | 112px |
| Corner radius | 10px |
| Shadow | black 25%, radius 8, y-offset 4 |
| Spacing between cards | 8px |
| Container padding | 10px |
| Button size | 32x32 (action), 20x20 (dismiss) |
| Hover overlay | black 40% |

## Todo List

- [ ] Implement `CardActionButton.swift`
- [ ] Implement `FloatingCardView.swift`
- [ ] Implement `FloatingStackView.swift`
- [ ] Update `FloatingPanelController` with stack view method
- [ ] Test hover reveals buttons
- [ ] Test animations smooth on add/remove
- [ ] Test button actions trigger correctly
- [ ] Test visual appearance matches spec
- [ ] Test accessibility (keyboard nav if applicable)

## Success Criteria

1. Cards display thumbnail correctly (aspect fill, clipped)
2. Hover reveals action buttons with smooth animation
3. Dismiss button always partially visible, fully visible on hover
4. Copy button copies full image to clipboard
5. Finder button opens file in Finder
6. New cards animate in from bottom
7. Removed cards animate out with scale/fade
8. Stack reflows smoothly when cards added/removed

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Hover not detected (NSPanel issue) | Medium | High | Ensure `acceptsMouseMovedEvents = true` on panel |
| Animation jank with many cards | Low | Medium | Limit to 5 cards, use `LazyVStack` if needed |
| Button clicks don't register | Medium | High | Use `.buttonStyle(.plain)`, test in NSPanel context |
| Image aspect ratio distortion | Low | Low | Use `.aspectRatio(contentMode: .fill)` with `.clipped()` |
