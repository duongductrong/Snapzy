# Project Architecture & Guidelines (Flattened Structure)

**Context:** macOS Application (SwiftUI + AppKit)
**Style:** Feature-Based, Flattened, Colocated

## 1. Directory Philosophy

We adopt a **Flattened Structure** to minimize folder clicking depth.

- **Rule 1: No Folder Nesting inside Features.** All files related to a feature (View, VM, Logic) sit in the same folder.
- **Rule 2: Strict Naming.** Files must be prefixed with the Feature name to ensure alphabetical sorting keeps them visually grouped.
- **Rule 3: Root Visibility.** Services and Shared components exist at the root level, not hidden inside a `Core` or `UI` folder.

---

## 2. Directory Structure Tree

```text
App/
  App.swift                       // @main
  AppCoordinator.swift            // Window & Navigation Logic
  AppEnvironment.swift            // DI Container

Features/
  [FeatureName]/                  // e.g., "Capture", "Annotate"
    [Feature]View.swift           // MAIN VIEW
    [Feature]ViewModel.swift      // STATE
    [Feature]Logic.swift          // DOMAIN LOGIC (Pipeline, Algorithms)
    [Feature]Components.swift     // SUB-VIEWS specific to this feature

Services/                         // Global System Services
  ScreenCaptureService.swift      // SCKit / CGWindowList
  PermissionService.swift         // TCC / Accessibility
  HotkeyService.swift             // Keyboard events
  StorageService.swift            // Persistence

Shared/
  Components/                     // Reusable UI (Buttons, Tooltips)
  Bridging/                       // AppKit Wrappers (NSViewRepresentable)
  Extensions/                     // Swift Extensions
  Styles/                         // Design System tokens

Resources/
  Assets.xcassets
  Info.plist
```

## 3. Implementation Rules (Flattened)

### A. Feature Colocation (Critical)

Inside `Features/[FeatureName]/`, **DO NOT** create `Views/`, `ViewModels/`, or `Models/` subfolders.

- **Goal:** Keep all related files flat within the feature directory to minimize navigation depth.
- **Good:**
  - `Features/Capture/CaptureView.swift`
  - `Features/Capture/CaptureViewModel.swift`
  - `Features/Capture/CaptureSelectionLogic.swift`
- **Bad:**
  - `Features/Capture/Views/MainView.swift` (Avoid generic names & nesting)

### B. Strict Naming Convention

Because files are flattened, naming is the primary organizational tool.

- **Prefixing:** All files in a feature folder MUST start with the feature name.
  - `[Feature]View.swift`
  - `[Feature]ViewModel.swift`
  - `[Feature]Service.swift` (if specific to that feature)
- **Sorting:** This ensures that `CaptureView` sits right next to `CaptureViewModel` in the file explorer, making context switching instant.

### C. AppKit Bridging & Shared Logic

- **Shared/Bridging:** Place generic, reusable AppKit wrappers here (e.g., `VisualEffectView.swift`, `KeyEventHandler.swift`).
- **Feature-Specific AppKit:** Place feature-specific AppKit code directly in the feature folder (e.g., `Features/Capture/CaptureWindowController.swift`).
- **Services:** Global services (ScreenCapture, Permissions) reside at the root `Services/` folder, not hidden in `Core`.

### D. The Coordinator Pattern

The `App/AppCoordinator.swift` remains the single source of truth for:

- **Window Management:** Opening/Closing `NSWindow` and `NSPanel`.
- **Menu Bar:** Toggling the `NSStatusBar` item.
- **Z-Ordering:** Handling `NSWindow.Level` (e.g., keeping the overlay above other apps).

---

## 4. Workflow for AI

When generating code or refactoring:

1.  **Identify Context:** Determine which **Feature** the code belongs to.
2.  **Locate Folder:** Navigate to `Features/[FeatureName]/`.
3.  **Apply Flat Structure:** Place new files directly in the root of that feature folder. **Do not create subdirectories.**
4.  **Enforce Naming:** Name the file starting with the Feature name (e.g., `SettingsAdvancedView.swift`, not `AdvancedView.swift`).
5.  **Refactor Check:** If a feature folder exceeds 15 files, consult before creating a sub-folder or splitting the feature.
