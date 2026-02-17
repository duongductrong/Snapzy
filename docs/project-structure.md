# Project Architecture & Guidelines (Pragmatic Flattened)

**Context:** macOS Application (SwiftUI + AppKit)
**Style:** Feature-Based, Pragmatic Flattened
**Version:** 2.0 (Nested Support)

## 1. Directory Philosophy

We adopt a **Pragmatic Flattened Structure**. Simplicity is priority, but organization is key when complexity grows.

- **Rule 1: Feature Root Visibility.** Main Views and ViewModels must reside at the root of the Feature folder for instant access.
- **Rule 2: Limited Nesting.** Inside a Feature, you may create **one level** of subfolders only for `Components`, `Managers`, or `Services` if necessary.
- **Rule 3: Service Expansion.** Global Services are single files by default. If a Service grows complex, convert it into a folder containing the main service and its helpers.

---

## 2. Directory Structure Tree

```text
App/
  App.swift                       // @main
  AppCoordinator.swift            // Window & Navigation Logic
  AppEnvironment.swift            // DI Container

Features/
  [FeatureName]/                  // e.g., "Capture"
    CaptureView.swift             // MAIN Entry View (Keep at Root)
    CaptureViewModel.swift        // MAIN State (Keep at Root)

    Components/                   // [Optional] Sub-views specific to this feature
      CaptureButton.swift
      SelectionOverlay.swift
    Managers/                     // [Optional] Logic controllers
      SelectionManager.swift
    Services/                     // [Optional] Local services
      OCRService.swift

Services/                         // Global System Services
  PermissionService.swift         // Simple Service (Single File)

  Windowing/                      // Complex Service (Folder)
    WindowService.swift           // Main Interface
    WindowLayoutStrategy.swift    // Helper Logic
    WindowOverlayConfig.swift     // Configuration models

Shared/
  Components/                     // Reusable UI (Buttons, Tooltips)
  Bridging/                       // AppKit Wrappers (NSViewRepresentable)
  Extensions/                     // Swift Extensions
  Styles/                         // Design System tokens

Resources/
  Assets.xcassets
  Info.plist
```

## 3. Implementation Rules (Pragmatic Flattened)

### A. Feature Organization (1-Level Nesting)

Inside `Features/[FeatureName]/`:

- **Root Level (Mandatory):** MUST contain the primary `[Feature]View.swift` and `[Feature]ViewModel.swift`. Do not hide the entry points inside subfolders.
- **Nested Level (Allowed):** You are explicitly allowed to create specific folders **only** for:
  - `Components/`: Smaller sub-views used only in this feature.
  - `Managers/`: Logic classes (e.g., `CaptureSessionManager`).
  - `Services/`: Services scoped strictly to this feature.
  - `Models/`: Data structures (if numerous).

### B. Service Scalability (Adaptive)

- **Default (Simple):** Create a service as a single file in the root `Services/` folder (e.g., `Services/HapticService.swift`).
- **Expansion (Complex):** If a Service logic becomes complex (e.g., > 300 lines or requires multiple helpers):
  1. Create a folder named after the domain (e.g., `Services/Windowing/`).
  2. Place the main service file inside (`Windowing/WindowService.swift`).
  3. Place helper files side-by-side (`Windowing/WindowLayoutStrategy.swift`).

### C. Naming & Colocation

- **Strict Prefixes:** Even inside nested folders, maintain strict naming to ensure clarity.
  - `Features/Capture/Components/CaptureToolbar.swift` (Clear context)
  - `Features/Capture/Managers/CaptureLogic.swift`
- **Visibility:** Main components must remain visible at the top level of the feature folder.

### D. The Coordinator Pattern

The `App/AppCoordinator.swift` remains the single source of truth for:

- **Window Management:** Opening/Closing `NSWindow` and `NSPanel`.
- **Menu Bar:** Toggling the `NSStatusBar` item.
- **Z-Ordering:** Handling `NSWindow.Level` (e.g., keeping the overlay above other apps).

---

## 4. Workflow for AI

When generating code or refactoring:

1.  **Identify Context:** Determine if the code is a primary feature entry point or a supporting component.
2.  **Placement Logic:**
    - **Main View/VM:** Place directly in `Features/[Name]/` (Root).
    - **Helper/Sub-component:** Place in `Features/[Name]/Components/`.
    - **Logic/Manager:** Place in `Features/[Name]/Managers/`.
3.  **Service Handling:**
    - **Simple:** Generate as a single file in `Services/`.
    - **Complex:** Generate a folder in `Services/` and split files for readability.
4.  **Refactor Trigger:**
    - If a Feature Root exceeds ~7 files, propose moving helpers into `Components` or `Managers`.
    - If a Service file exceeds ~300 lines, propose splitting it into a Service Folder.
