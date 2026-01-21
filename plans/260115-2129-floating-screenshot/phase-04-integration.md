# Phase 04: Integration

## Context

- [Main Plan](./plan.md)
- [Phase 03: Floating Card UI](./phase-03-floating-card-ui.md)
- Existing code: `ScreenCaptureManager.swift`, `ContentView.swift`

## Overview

| Field | Value |
|-------|-------|
| Date | 260115 |
| Description | Connect floating screenshot system to existing capture flow and settings UI |
| Priority | High |
| Status | `pending` |
| Estimated Effort | 2-3 hours |

## Requirements

1. **Capture notification** - ScreenCaptureManager notifies on successful capture
2. **Manager initialization** - FloatingScreenshotManager initialized at app start
3. **Settings UI** - Add floating screenshot settings to ContentView
4. **Wiring** - Connect capture completion to floating screenshot display
5. **Persistence** - Save position preference to UserDefaults

## Architecture

```
Integration Points:

1. ScreenCaptureManager
   └── Add: Combine publisher for capture completion
       └── captureCompletedPublisher: PassthroughSubject<URL, Never>

2. ScreenCaptureViewModel
   ├── Add: FloatingScreenshotManager reference
   ├── Add: Subscribe to captureCompletedPublisher
   └── Add: Settings bindings (position, autoDismiss)

3. ContentView
   └── Add: Floating Screenshot settings section
       ├── Enable/disable toggle
       ├── Position picker
       ├── Auto-dismiss toggle
       └── Auto-dismiss delay slider

4. ZapShotApp (or AppDelegate)
   └── Initialize FloatingScreenshotManager.shared
```

## Related Files

| File | Action | Purpose |
|------|--------|---------|
| `ZapShot/Core/ScreenCaptureManager.swift` | Modify | Add capture publisher |
| `ZapShot/ContentView.swift` | Modify | Add settings section, wire up manager |
| `ZapShot/Features/FloatingScreenshot/FloatingScreenshotManager.swift` | Modify | Add persistence, initialization |

## Implementation Steps

### Step 1: Add capture publisher to ScreenCaptureManager

```swift
// In ScreenCaptureManager.swift

import Combine

// Add property
private let captureCompletedSubject = PassthroughSubject<URL, Never>()
var captureCompletedPublisher: AnyPublisher<URL, Never> {
    captureCompletedSubject.eraseToAnyPublisher()
}

// Modify saveImage method - after successful save, publish URL
private func saveImage(...) -> CaptureResult {
    // ... existing code ...

    if CGImageDestinationFinalize(destination) {
        captureCompletedSubject.send(fileURL)  // Add this line
        return .success(fileURL)
    } else {
        return .failure(.saveFailed("Failed to write image to disk"))
    }
}
```

### Step 2: Add settings persistence to FloatingScreenshotManager

```swift
// In FloatingScreenshotManager.swift

// Add UserDefaults keys
private enum Keys {
    static let enabled = "floatingScreenshot.enabled"
    static let position = "floatingScreenshot.position"
    static let autoDismissEnabled = "floatingScreenshot.autoDismissEnabled"
    static let autoDismissDelay = "floatingScreenshot.autoDismissDelay"
}

// Add enabled property
@Published var isEnabled: Bool = true {
    didSet {
        UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
    }
}

// Modify init to load saved settings
private init() {
    // Load saved settings
    isEnabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true

    if let positionRaw = UserDefaults.standard.string(forKey: Keys.position),
       let savedPosition = FloatingPosition(rawValue: positionRaw) {
        position = savedPosition
    }

    autoDismissEnabled = UserDefaults.standard.object(forKey: Keys.autoDismissEnabled) as? Bool ?? true
    autoDismissDelay = UserDefaults.standard.object(forKey: Keys.autoDismissDelay) as? Double ?? 10

    setupBindings()
}

// Add didSet for persistence
@Published var position: FloatingPosition = .bottomRight {
    didSet {
        UserDefaults.standard.set(position.rawValue, forKey: Keys.position)
    }
}

@Published var autoDismissEnabled: Bool = true {
    didSet {
        UserDefaults.standard.set(autoDismissEnabled, forKey: Keys.autoDismissEnabled)
    }
}

@Published var autoDismissDelay: TimeInterval = 10 {
    didSet {
        UserDefaults.standard.set(autoDismissDelay, forKey: Keys.autoDismissDelay)
    }
}
```

### Step 3: Update ScreenCaptureViewModel

```swift
// In ContentView.swift - ScreenCaptureViewModel

// Add property
private let floatingManager = FloatingScreenshotManager.shared

// Add to init()
init() {
    // ... existing init code ...

    // Subscribe to capture completions
    captureManager.captureCompletedPublisher
        .receive(on: DispatchQueue.main)
        .sink { [weak self] url in
            guard self?.floatingManager.isEnabled == true else { return }
            Task {
                await self?.floatingManager.addScreenshot(url: url)
            }
        }
        .store(in: &cancellables)
}

// Add cancellables property if not exists
private var cancellables = Set<AnyCancellable>()

// Add bindings for settings UI
var floatingEnabled: Bool {
    get { floatingManager.isEnabled }
    set { floatingManager.isEnabled = newValue }
}

var floatingPosition: FloatingPosition {
    get { floatingManager.position }
    set { floatingManager.setPosition(newValue) }
}

var floatingAutoDismiss: Bool {
    get { floatingManager.autoDismissEnabled }
    set { floatingManager.autoDismissEnabled = newValue }
}

var floatingAutoDismissDelay: TimeInterval {
    get { floatingManager.autoDismissDelay }
    set { floatingManager.autoDismissDelay = newValue }
}
```

### Step 4: Add settings UI to ContentView

```swift
// In ContentView.swift - add new section in settingsSection

// Add after existing settings, before Keyboard Shortcuts

Divider()

// Floating Screenshot Settings
Text("Floating Preview")
    .font(.headline)

Toggle("Show floating preview after capture", isOn: Binding(
    get: { viewModel.floatingEnabled },
    set: { viewModel.floatingEnabled = $0 }
))

if viewModel.floatingEnabled {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Text("Position:")
                .font(.body)

            Picker("", selection: Binding(
                get: { viewModel.floatingPosition },
                set: { viewModel.floatingPosition = $0 }
            )) {
                Text("Top Left").tag(FloatingPosition.topLeft)
                Text("Top Right").tag(FloatingPosition.topRight)
                Text("Bottom Left").tag(FloatingPosition.bottomLeft)
                Text("Bottom Right").tag(FloatingPosition.bottomRight)
            }
            .pickerStyle(.menu)
            .frame(width: 140)
        }

        Toggle("Auto-dismiss cards", isOn: Binding(
            get: { viewModel.floatingAutoDismiss },
            set: { viewModel.floatingAutoDismiss = $0 }
        ))

        if viewModel.floatingAutoDismiss {
            HStack {
                Text("Dismiss after:")
                Slider(
                    value: Binding(
                        get: { viewModel.floatingAutoDismissDelay },
                        set: { viewModel.floatingAutoDismissDelay = $0 }
                    ),
                    in: 3...30,
                    step: 1
                )
                .frame(width: 120)
                Text("\(Int(viewModel.floatingAutoDismissDelay))s")
                    .frame(width: 30)
            }
        }
    }
    .padding(.leading, 4)
}
```

### Step 5: Initialize panel on first screenshot

```swift
// In FloatingScreenshotManager.swift

func addScreenshot(url: URL) async {
    guard isEnabled else { return }  // Check enabled

    guard let thumbnail = await ThumbnailGenerator.generate(from: url) else { return }

    let item = ScreenshotItem(url: url, thumbnail: thumbnail)

    // Remove oldest if at max
    if items.count >= maxVisibleItems {
        if let oldestId = items.first?.id {
            removeScreenshot(id: oldestId)
        }
    }

    // Show panel if this is first item
    let wasEmpty = items.isEmpty

    items.append(item)

    if wasEmpty {
        panelController.showStackView(manager: self)
    }

    // Start auto-dismiss timer
    if autoDismissEnabled {
        startDismissTimer(for: item.id)
    }
}
```

## Todo List

- [ ] Add `captureCompletedPublisher` to `ScreenCaptureManager`
- [ ] Add persistence to `FloatingScreenshotManager`
- [ ] Add `cancellables` and subscription to `ScreenCaptureViewModel`
- [ ] Add floating settings bindings to `ScreenCaptureViewModel`
- [ ] Add "Floating Preview" settings section to `ContentView`
- [ ] Test end-to-end: capture triggers floating card
- [ ] Test settings persistence across app restart
- [ ] Test enable/disable toggle
- [ ] Test position picker changes card position
- [ ] Test auto-dismiss settings work correctly

## Success Criteria

1. Capturing screenshot automatically shows floating card
2. Disabling floating preview stops cards from appearing
3. Position setting moves cards to correct corner
4. Auto-dismiss setting controls card timeout behavior
5. All settings persist across app restarts
6. Multiple rapid captures stack correctly
7. No crashes or memory leaks in normal usage

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Combine subscription leak | Medium | Medium | Store in cancellables, use weak self |
| Settings not persisting | Low | Low | Test UserDefaults read/write |
| Race condition on rapid captures | Medium | Low | Main actor serialization |
| Panel not showing on first capture | Medium | High | Check `wasEmpty` logic, ensure showStackView called |
| UI bindings not updating | Medium | Medium | Use proper Binding wrappers with get/set |

## Testing Checklist

- [ ] Fullscreen capture shows floating card
- [ ] Area capture shows floating card
- [ ] Keyboard shortcut capture shows floating card
- [ ] Disable setting prevents cards
- [ ] Each position option works correctly
- [ ] Auto-dismiss removes cards after delay
- [ ] Slider changes auto-dismiss timing
- [ ] Settings persist after quit/relaunch
- [ ] Copy button copies to clipboard
- [ ] Finder button reveals file
- [ ] Dismiss button removes card
- [ ] 5+ captures shows only 5 cards (oldest removed)
