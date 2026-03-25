# Changelog

All notable changes to Snapzy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).



































## [1.4.6] - 2026-03-25

### Features
-  Enhance video encoding with dynamic bitrate, HEVC/H.264 codec selection, pixel-aligned capture, and diagnostic logging for recording. (482d5cb)

### Chore
- chore: update appcast, cask, and readme for v1.4.5 (2aaf49b)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.4.5] - 2026-03-24

### Features
-  Introduce user-configurable filename templates for screenshots and recordings. (bfc61f3)
-  Add cloud upload feature description and detail its security implementation in documentation. (3ce50c7)

### Chore
- chore: update appcast, cask, and readme for v1.4.4 (458fd17)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.4.4] - 2026-03-24

### Features
-  Refactor zoom segment layout and interaction to ensure a minimum visual width and improve UI adaptation for small blocks. (a82cc47)
-  Align video preview zoom and pan calculations with export output for accuracy and update camera transition duration. (e414f8b)
-  Enhance auto-focus engine with improved path generation, quality metrics, and canonical mouse sample handling. (e31b798)

### Chore
- refactor: Refactor `BlurEffectRenderer` to support separate source and destination regions for blur effects, improve coordinate mapping and clamping, and disable anti-aliasing for pixelated drawing. (00cec7d)
- docs: document screen recording and Smart Camera (follow mouse) pipeline, runtime data layout, and metadata storage. (701c7fb)
- chore: update appcast, cask, and readme for v1.4.3 (daec159)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.4.3] - 2026-03-24

### Features
-  Implement a dedicated save flow for temporary captured videos and GIFs, including dynamic primary action button text. (a88beda)

### Bug Fixes
-  Dynamically set video composition frame duration from source and log detailed recording frame statistics. (2f1a760)
-  Enhance screen capture and recording by improving desktop icon and widget exclusion and preventing self-capture of UI elements. (de2f192)

### Chore
- refactor: improve clarity and conciseness of capture settings UI text for including app windows in captures. (1196918)
- chore: update appcast, cask, and readme for v1.4.2 (b00ed3a)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.4.2] - 2026-03-23

### Features
-  Implement caching for cloud usage data and refactor CloudUsageService with a dedicated worker actor. (b46267b)
-  Add masked endpoint display logic to CloudManager and integrate it into the Preferences view. (46d9cfb)
-  Implement password protection for cloud credentials, including gate and initialization UI. (ff036e8)

### Chore
- chore: update appcast, cask, and readme for v1.4.1 (f2c685e)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.4.1] - 2026-03-23

### Bug Fixes
-  Prevent cloud configuration save if S3 lifecycle rule application fails and refactor S3 lifecycle XML string formatting. (ef90e10)
-  Resolve AWS S3 signature issues by removing manual Content-Length and refining header/URI encoding for signing, and update Keychain identifiers. (e755bac)

### Chore
- refactor: Remove the recent uploads section and its associated record row from the cloud settings view. (586eb16)
- chore: update appcast, cask, and readme for v1.4.0 (e9742ad)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.4.0] - 2026-03-23

### Features
-  Implement LazyView for deferred SwiftUI tab loading and cache cloud configuration details. (ee0acdb)
-  Enhance cloud upload records with content type and thumbnail support, and add advanced filtering, sorting, and display modes to the upload history view. (1de65df)
-  Add cloud usage service to track and display bucket storage, object count, and lifecycle rules. (b57b9e0)
-  Implement cloud object lifecycle management to configure and remove expiration rules for S3 and R2 storage providers. (da8451a)
-  Improve UI of cloud configuration. (53097c7)
-  Remove cloud overwrite confirmation alert and directly trigger cloud upload. (9920096)
-  Ensure removes history records when overwrited upload screenshot (1b7a03f)
-  Implement cloud storage integration with S3/R2 providers, preferences, and overwrite handling for annotated images. (8dcde11)

### Bug Fixes
-  Improve keystroke name resolution in `KeystrokeMonitorService` by using `keyCode`-based mapping for global monitor reliability. (e2c074e)
-  Add support for punctuation, keypad, and navigation keys to `KeyboardShortcutManager`. (0f10b42)

### Chore
- refactor: reorder Share button to appear before the Cloud upload button in AnnotateBottomBarView. (a8633ce)
- refactor: reimplement CloudUploadHistoryStore persistence using SQLite and GRDB, adding a new DatabaseManager and GRDB dependency. (6199fac)
- chore: update appcast, cask, and readme for v1.3.5 (f01f845)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.3.5] - 2026-03-21

### Chore
- refactor: Enhance diagnostic logging with detailed system information, error context, and source location. (e45411d)
- chore: update appcast, cask, and readme for v1.3.4 (9b583c3)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.3.4] - 2026-03-21

### Bug Fixes
-  Update Space key to function in text inputs and provide cursor feedback for pan mode. (4579a65)

### Chore
- docs: Add a comprehensive security policy document and link it from the README. (ce2dfa2)
- docs: update and expand README features list with more detail and relocate requirements. (ccb69dd)
- chore: update appcast, cask, and readme for v1.3.3 (4a45eaa)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.3.3] - 2026-03-21

### Bug Fixes
-  add `ScreenUtility` to accurately determine the active screen for multi-monitor UI positioning and capture operations. (d2ded2b)
-  Write both NSURL and NSImage to the pasteboard for maximum compatibility across applications. (4f3bb18)

### Chore
- chore: update appcast, cask, and readme for v1.3.2 (649c0f4)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.3.2] - 2026-03-21

### Bug Fixes
-  Always display the 'Copy' button in the Quick Access card hover overlay. (c6bbde1)

### Chore
- chore: update appcast, cask, and readme for v1.3.1 (d3b32f8)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.3.1] - 2026-03-20

### Bug Fixes
-  enhance image rendering and screen capture quality with pixel-perfect techniques and dynamic scaling. (6b98c2c)

### Chore
- docs: Add comprehensive documentation detailing the screen capture pipeline, architecture, and post-capture actions. (0c252f2)
- chore: update appcast, cask, and readme for v1.3.0 (0b21b54)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.3.0] - 2026-03-20

### Features
-  Implement canvas panning functionality using the Space key and mouse drag, and refine zoom range options. (696b8c3)
-  Add keyboard shortcuts and trackpad gestures for zoom, expand zoom range, and animate transitions. (e8412ce)
-  Include window shadows in screen capture for macOS 14.0+ by setting `ignoreShadowsSingleWindow` to false. (2c6fbd7)
-  Introduce configurable shortcuts for the annotate editor's copy-and-close and toggle-pin actions, updating UI and event handling. (7fd3e48)

### Chore
- chore: update appcast, cask, and readme for v1.2.6 (c7425ed)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.2.6] - 2026-03-19

### Features
-  Add a warning message about WebP encoding speed in capture settings. (88bdc90)
-  Add .webp, .jpg image format support and format-aware clipboard copying for screenshots and annotations. (8b152dd)

### Chore
- refactor: Migrate WebP encoding from SDWebImageWebPCoder to Swift-WebP for optimized performance using raw pixel data. (e175285)
- chore: update appcast, cask, and readme for v1.2.5 (545848f)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.2.5] - 2026-03-18

### Features
-  add splash screen skip functionality with a "Do not show again" option (c61f67e)

### Chore
- chore: update appcast, cask, and readme for v1.2.4 (1053148)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.2.4] - 2026-03-17

### Bug Fixes
- : centralize sound playback management and solve issue sound playback calls across the application (4c04381)

### Chore
- chore: update appcast, cask, and readme for v1.2.3 (24f5771)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.2.3] - 2026-03-17

### Features
-  Enhance text annotation editing with automatic commit on tool switch or click away, improve text editor sizing, and enable annotation movement in all tool modes. (a07568f)
-  Implement multiline text editing for annotations with dynamic height and word wrapping (edc0dcd)

### Bug Fixes
-  resolve annotation drag/resize state management and updating the active tool upon selection. (07ee6b9)
-  Enhance annotation selection and tool switching UX, improve keyboard shortcut reliability (94d5aef)
-  fix select & deselect textbox (f7d6366)

### Chore
- chore: update appcast, cask, and readme for v1.2.2 (6f4e07d)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.2.2] - 2026-03-16

### Bug Fixes
-  replace AnnotateDragSource with NSFilePromiseProvider for improved drag performance and compatibility (a5db39e)

### Chore
- chore: Update appcast styling to support dark mode. (cc6f159)
- chore: update appcast, cask, and readme for v1.2.1 (c9d5535)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.2.1] - 2026-03-16

### Features
-  Implement window pinning for the Annotate feature with UI, state, and keyboard shortcut (c80faf8)
-  Improve annotation save responsiveness with instant UI updates and background saving, refactor session data to use raw image data (98ae09b)
-  implement annotation session caching and update clipboard actions (df26432)

### Chore
- refactor: Embed HTML release notes generated from changelog directly into appcast.xml for Sparkle updates. (b6e0c2c)
- chore: add unikorn to README (939cc1c)
- docs: Add Product Hunt badge to README (c44cdfe)
- chore: remove duplicate contributor entry from CHANGELOG.md (498bb23)
- chore: update appcast, cask, and readme for v1.2.0 (72c655d)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.2.0] - 2026-03-15

### Features
-  improve mouse event handling with caching, throttling, and animation control. (bee9b8b)
-  Add configurable mouse click highlights and keystroke overlays with preferences persistence. (cbac32c)
-  Add option to display keystrokes as an overlay during recording. (bfbeb25)
-  Enhance mouse click highlighting to track mouse down, up, and drag events with updated visual effects. (26ec799)
-  Implement mouse click highlighting during screen recording with a new toolbar option and dedicated services. (4c30bf0)
-  implement dynamic scaling for QuickAccess card dimensions (5cfaf95)
-  Add uninstallation instructions and update README.md (dce3e9b)

### Bug Fixes
-  read from /dev/tty for curl pipe compatibility (417a9fb)

### Chore
- chore: update default branch on uninstall script (0ef19c3)
- chore: update CHANGELOG.md (c45c565)
- chore: update appcast, cask, and readme for v1.1.0 (2244d1b)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.1.0] - 2026-03-14

### Features
-  improve quick access + capture + consume flow (#18) (2c8d08b)

### Chore
- chore: update appcast, cask, and readme for v1.0.15 (4b5d26c)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.0.15] - 2026-03-14

### Chore
- chore: update appcast, cask, and readme for v1.0.14 (9e24997)

### Contributors
- @github-actions[bot]

## [1.0.14] - 2026-03-14

### Features
-  enhance local update testing with detailed signing process and entitlements handling (95a5139)

### Chore
- chore: update appcast, cask, and readme for v1.0.13 (9ed3218)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.0.13] - 2026-03-14

### Chore
- chore: update appcast, cask, and readme for v1.0.12 (2b57c97)

### Contributors
- @github-actions[bot]

## [1.0.12] - 2026-03-14

### Features
-  improve self-signed certificate trust for code signing. (15a5c4f)
-  Implement detailed update manager lifecycle logging (18d07f7)

### Bug Fixes
-  remove interactive trust setting for self-signed certificate in CI (b8c515a)
-  Add self-signed certificate generation and TCC permission testing scripts (47ffa93)

### Chore
- chore: bump version to v1.0.11 (#22) (07eebc6)
- chore: update appcast, cask, and readme for v1.0.10 (d23f684)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.0.11] - 2026-03-14

### Features
-  improve self-signed certificate trust for code signing. (15a5c4f)
-  Implement detailed update manager lifecycle logging (18d07f7)

### Bug Fixes
-  Add self-signed certificate generation and TCC permission testing scripts (47ffa93)

### Chore
- chore: update appcast, cask, and readme for v1.0.10 (d23f684)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.0.10] - 2026-03-13

### Features
-  Add cache management functionality with size calculation and clearing options (a9413da)

### Chore
- chore: update appcast, cask, and readme for v1.0.9 (3a7c507)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.0.9] - 2026-03-13

### Bug Fixes
- : Enhance code signing process and update entitlements for improved security and functionality (b9ff8f2)

### Chore
- chore: update appcast, cask, and readme for v1.0.8 (f291044)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.0.8] - 2026-03-13

### Features
-  Implement system screenshot shortcut conflict detection and user guidance in onboarding and preferences views (67cb711)
-  Introduce agent guidance documentation for Antigravity and Claude, update funding options, and add an archive file. (f0b78af)
-  add GitHub issue templates, agent guidance files, and an archive file. (98c1aaa)

### Chore
- chore: update appcast, cask, and readme for v1.0.7 (61a4ba3)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.0.7] - 2026-03-11

### Bug Fixes
-  improve screen capture permission handling, and skip strict bundle signature validation in debug builds. (b92fbf6)

### Chore
- chore: update appcast, cask, and readme for v1.0.6 (913a0e3)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.0.6] - 2026-03-11

### Bug Fixes
-  remove the `--options runtime` flag from release codesigning. (f80c523)

### Chore
- chore: update appcast, cask, and readme for v1.0.5 (946582e)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.0.5] - 2026-03-11

### Features
-  introduce agent guidance documents, update gitignore, and enhance Sparkle DMG signing reliability in release workflow. (8db5280)

### Contributors
- @duongductrong

## [1.0.4] - 2026-03-11

### Features
-  enhance release workflow with ad-hoc signing and verification for fallback distribution (4f42ad1)
-  Implement AppIdentityManager and DefaultsDomainMigrationService for bundle identity management and migration (151dbe0)
-  Update DMG background image (cfdeac6)
-  Update DMG creation process with create-dmg and add background image (17f7a65)
-  Add derived data path for Xcode build process (74d94b6)

### Bug Fixes
-  Update bundle identifiers and dispatch queue labels to use the correct namespace (f96151d)
-  Update dispatch queue labels to use the correct Snapzy prefix (8377024)

### Chore
- refactor: Remove DefaultsDomainMigrationService and streamline app initialization (5e4515d)
- chore: update appcast, cask, and readme for v1.0.3 (b26e4b5)

### Contributors
- @duongductrong
- @github-actions[bot]

## [1.0.3] - 2026-03-10

### Features
-  Add installation script and update README with version-specific install instructions (21b6020)
-  Add Homebrew installation instructions and compute SHA256 for DMG in release workflow (1f5aedb)
-  Enhance release workflow with build number extraction, DMG signing, and appcast update automation (e21be0e)

### Bug Fixes
-  Update Sparkle key condition for DMG signing in release workflow (ed2b4a5)

### Contributors
- @duongductrong

## [1.0.2] - 2026-03-10

### Features
-  Add release preparation and publishing workflows for automated versioning and changelog management (5ffe9c3)
-  Add AI agent guidance documentation and a Git author correction script, while streamlining the release workflow by removing pull request creation and merging steps. (1c683ff)
-  introduce AI agent guidance documents, update release workflow with force push, and add a Git author fix script. (e632a83)
-  Add guidance documents for Antigravity and Claude agents, and update the release workflow to use pull requests for version bumps. (3c6e50c)
-  add changelog generation and update script for version entries (58bdc85)
-  update onboarding components to use adaptive dark/light theme colors (148b512)
-  update Xcode version in CI and release workflows, enhance MainActor usage in various classes (dafbfd9)
-  enhance CI and release workflows with improved error handling and environment variable checks (370d18f)
-  enhance sponsor section layout and add color attributes to sponsor links (4a5e42b)
-  update star history section in README for improved link and image sources (e3d4c0e)
-  update license information from MIT to BSD 3-Clause License in README (78bba6e)
-  update documentation for build instructions and licensing flow (53303bb)
-  update macOS requirement from 14.0+ to 13.0+ in documentation (1bbf8a0)
-  add CODE_OF_CONDUCT.md and CONTRIBUTING.md files to establish community guidelines and contribution process (c59d95e)
-  add BSD 3-Clause License file to the repository (0379a01)
-  remove outdated AGENTS.md and CLAUDE.md files; add project build and release workflow documentation (b6b942a)
-  Implement auto-focus functionality with mouse tracking (#1) (556bf83)
-  simplify ESC key handling by removing confirmation dialog and allowing immediate cancel (910aa02)
-  optimize cropping logic in AnnotateCanvasView and simplify TextEditOverlay bounds calculation (a4c2066)
-  enhance tooltip help for annotation tools and update icons for better clarity (27f9c53)
-  implement prefetching of shareable content for improved capture performance (768aa2f)
-  add options to include own application in screenshots and recordings, enhance exclusion logic for capture (8b85f1f)
-  enhance crop toolbar visibility logic and improve layout structure in AnnotateCanvasView (e4e6877)
-  enhance logging for annotation and shortcut management, improve window sizing logic (1795ead)
-  Implement CI and release workflows with version bumping and changelog generation (b02a95e)
-  Enhance area selection process with improved frame synchronization and logging for better debugging (bfdb17f)
-  Enhance annotation state management with quick access item ID and implement image deletion confirmation (a3e1089)
-  Update tab icons in PreferencesView and change picker styles to menu for better UI consistency (599fb88)
-  Implement GIF resizing and export functionality, introducing a dedicated `GIFResizer` service and settings panel. (e392f91)
-  Add save folder permission check and UI to preferences. (409a69b)
-  Add a new filled rectangle annotation tool with corresponding UI, model, rendering, and property support. (219ac93)
-  Refactor recording session timestamp handling to align all media to the first video frame and improve resource cleanup in recording windows. (3cc2cb5)
-  Enable App Sandbox, introduce `SandboxFileAccessManager`, and adapt features for secure file access. (8c2c6a3)
-  add crash report feature to about view (b7c7b31)
-  Implement custom wallpaper removal functionality and add a new method to load current desktop wallpapers. (446d6d1)
-  Add draggable diagnostic log to crash report alert and always display crash report menu item. (3e3ed2e)
-  Introduce flattened project structure documentation, update agent guidance, and remove outdated research and planning documents. (746143a)
-  Implement diagnostic logging and crash reporting with crash detection, user opt-in, and a submission flow. (06a1816)
-  default `rememberLastArea` preference to true when not explicitly set in `ScreenCaptureViewModel`. (243a7e8)
-  Add support for viewing animated GIFs in the video editor with a dedicated view and adapted UI. (8246378)
-  Implement recording output mode selection (video/GIF) in the toolbar and integrate GIF conversion with Quick Access processing. (d332f1a)
-  remove scout reports from local agent settings (86398f7)
-  Improve crop display by rendering only the cropped image and canvas, and refine crop overlay visibility to active editing. (3f1dce4)
-  Implement accurate rendering and clipping for cropped images and drawings, and add agent communication rules and a context compaction workflow. (aa2b41b)
-  add macOS compatibility rule and new workflow for fixing hard issues using subagents. (0b3bc38)
-  automatically configure Polar license provider's sandbox mode based on build configuration and update README formatting. (b95bcc5)
-  Add dynamic log level filtering to the launch script and configure the VS Code task to use debug logging. (c70b911)
-  Add macOS 13 compatibility by updating deployment target, implementing fallback UI for new APIs, and modernizing `onChange` syntax. (a94f0bc)
-  Shift license activation limit enforcement to server-side, removing client-side checks and adding API-level error handling for activation limits. (8979f54)
-  Implement background validation for cached licenses on startup and prompt users to reactivate or quit for invalid licenses. (98c8145)
-  add .agent for agy (1b11c24)
-  Add agent skills, workflows, and license management UI components. (057e4a5)
-  add contact links (Website, GitHub, Report a Bug) to the About settings view. (83f7930)
-  Add website, GitHub, and bug report links to About section and vertically center its content. (ba8d9c2)
-  add yellow rounded border between trim handles and remove overlay from trim handle appearance (261a200)
-  enhance VideoTimelineView with rounded corners and yellow border; clamp trim handles within timeline bounds (2de53a8)
-  sync player mute with export settings and remove mute button from controls (81f29fe)
-  remove vestigial Cloud Upload feature from Quick Access settings (5d81dcc)
-  enhance navigation and structure in onboarding flow with improved back handling and transition animations (4d36013)
-  enhance onboarding flow with skip confirmation screen and keyboard shortcuts (c68ff14)
-  update onboarding restart logic to show onboarding notification (8c4eec5)
-  unify onboarding flow within splash window, implement dark theme styling (ff6cfce)
-  Implement splash screen with animated content and onboarding flow (3d0a77e)
-  Reorganize Preferences Tabs for Improved Usability (17f321a)
-  Add screenshot capture functionality to recording toolbar (ea606bc)
-  Implement Phase 3 Defensive Improvements for Fast Screenshot Feature (43d4325)
-  Enhance animation handling for quick access card insertion and deletion (cccea2b)
-  Refactor area selection and recording overlay windows to use non-activating panels, preventing focus stealing from background applications (cd5657a)
-  Add shortcut mode for annotation tools with configurable modifier and hold duration (458587a)
-  Implement annotation tool context management and enhance keyboard event handling for recording features (da45fcc)
-  Refactor annotation toolbar to use popover style and update layout handling (d1e0802)
-  Enhance snap positioning logic in AnnotationToolbarSnapHelper for improved toolbar alignment (012671f)
-  Extract FirstMouseVisualEffectView and implement AnnotationToolbarContentBuilder for modular toolbar content management (6fba863)
-  Add AnnotationToolbarSnapHelper for improved snap functionality in recording toolbar (34b036b)
-  Implement recording annotation overlay and toolbar (7098439)
-  Override canBecomeKey property in RecordingToolbarWindow for improved window behavior (de2949e)
-  Refactor RecordingStatusBarView and RecordingToolbarView to remove background styling for improved UI consistency feat: Enhance RecordingToolbarWindow with NSVisualEffectView for adaptive background behavior (7faeff7)
-  Update background styling for RecordingStatusBarView and RecordingToolbarView to enhance UI consistency (7d8b4da)
-  Refactor RecordingStatusBarView and StopButtonStyle for improved UI and accessibility (e23ec78)
-  Update toolbar components to enhance hover effects and accessibility features (b30c64a)
-  Add option to exclude desktop widgets during screen capture (7c620e9)
-  Enhance screen capture functionality with desktop icon exclusion (f2dfd13)
-  Add feature to hide desktop icons during screenshot capture (f4eddeb)
-  Improve QuickAccess animations and card dismissal logic for smoother user experience (6b03758)
-  Update app and menubar icons with new designs and sizes (b05c8fa)
-  Add diagonal resize cursors for recording region handles (78830f4)
-  Enhance recording region handles with L-shaped corners and edge lines (f6b53b8)
-  Disable window animations for instant appearance in area selection and recording region overlays (40c5f98)
-  Add option to remember last recording area in preferences (0821b82)
-  Implement recording area persistence with UserDefaults (5153900)
-  Disable focus effect on AnnotateCanvasView for improved user experience (3db563a)
-  Add About section components including credit, feature, and link cards (27067db)
-  Implement customizable single-key shortcuts for annotation tools (d9a63f2)
-  Add confirmation alert for disabling keyboard shortcuts (5e4f7b5)
-  Add support for recording and annotate shortcuts in settings (dab4975)
-  Enhance status bar functionality to manage activation policy for Settings window (a181c49)
-  Implement OCR text recognition feature using Vision framework (fc09a5e)
-  Refactor recording toolbar components to use ObservableObject for state management and implement options popover (c747ec0)
-  Add capture mode toggle for area selection and fullscreen in recording toolbar (4749943)
-  Implement post-capture action handling and update preferences for screenshot and video captures (cd7854c)
-  Enhance DMG build workflow with versioning and release notes input (e552109)
-  Initialize and update crosshair position on area selection activation (831f106)
-  Add build workflow and export options for macOS DMG creation (58b443b)
-  Update app icon and descriptions to reflect new branding as Snapzy (9710b34)
-  Add crosshair indicator for mouse position in area selection overlay (81a6e12)
-  Implement ESC key handling with confirmation dialog for recording cancellation (de2972c)
-  Enhance annotation management with regular app mode handling and improved window behavior (5d1da7a)
-  Enhance crop functionality with improved editing modes, dynamic dimensions, and visual overlays (3c581a3)
-  Enhance crop feature with aspect ratio presets, live dimensions, grid overlay, and improved visuals (4d41cb2)
-  Enhance QuickAccess UI with shadow effects and immediate button feedback (c2e04f6)
-  Implement drag-to-external-app support with QuickAccessDraggableView (2ed3be9)
-  Refine swipe gesture handling for dismiss direction in QuickAccessCardView (e1a6e6e)
-  Implement QuickAccess animations, progress indicators, and sound feedback (94eadfa)
-  Remove disabled photo toolbar button from annotation toolbar (8072ec4)
-  Enhance video compositor with caching for wallpapers and improve slider functionality in UI (4fefdd9)
-  Update export dimension presets and adjust scaling logic for video preview background (cecaed7)
-  Update preview calculations to use export dimensions for WYSIWYG behavior (ce96ebc)
-  Enhance video export dimension handling and UI (2ef74d2)
-  Implement export settings management with UI panel for video editor (cd8910e)
-  Implement non-activating behavior for area selection and recording overlays to prevent focus stealing (21ec0bd)
-  Enhance launch scripts with logging and error handling improvements (9f7a62d)
-  Add right sidebar toggle functionality and update UI state management (0de9a78)
-  Refactor VerticalTabItem layout for improved UI consistency and responsiveness (9a0a50e)
-  Implement caching and performance optimizations for wallpaper rendering in VideoEditor (9efc797)
-  Optimize wallpaper rendering in Annotate feature (c1de0ee)
-  Apply design tokens to VideoDetailsSidebarView for consistency and improved maintainability (b4e0e05)
-  Implement performance optimization plan for area capture (7cf6580)
-  Add build and launch scripts for macOS app (4a846a4)
-  Fix race condition causing menubar icon persistence by adjusting state update timing in ScreenRecordingManager (97aad56)
-  Optimize slider performance with local state and caching for smoother interactions (731fa05)
-  Implement SystemWallpaperManager service and integrate system wallpapers into the annotation sidebar (944b3cc)
-  Implement UX improvements for Annotate sidebar (efc24b1)
-  Add wallpaper presets and integrate them into the annotation background options (9f25200)
-  Refactor AnnotateBottomBarView to streamline preview mode handling and enhance mode toggle functionality (84ad05f)
-  Refactor editor mode handling in annotation features, including mockup and preview modes (39fd1ee)
-  Implement phases 4-6 for Mockup Renderer including UI components, export functionality, and integration/testing (70a4ed2)
-  Implement blur enhancement features including Gaussian blur renderer, performance optimizations, UI integration, and export functionality (37de501)
-  Update slider ranges and enhance text input handling in CompactSliderRow (fec96d5)
-  Comment out ratio section in AnnotateSidebarView for layout adjustments (718964f)
-  Enhance image alignment handling and export functionality in Annotate features (d63873b)
-  Remove font and frame settings from Save button in VideoEditorToolbarView (22257b7)
-  Add implementation plan for Corner Radius and Button ViewModifiers (27f5f13)
-  Implement vertical tab bar for video editor sidebar (c6d271b)
-  Comment out drag handle and spacer in AnnotateBottomBarView for layout adjustments (26ad316)
-  Add NSWindow extensions for custom corner radius and traffic light button positioning (0a0382c)
-  Update status bar icon size for improved visibility in menu bar (6c445a8)
-  Update StatusBarController to use resized app icons for menu bar and add MenubarIcon assets (912618c)
-  Add macOS app icons in various sizes and update Contents.json for asset management (f2e3cae)
-  Refactor updater management to use UpdaterManager singleton for improved update handling (5cd8234)
-  Standardize onboarding persistence and improve window opening mechanism (a5ed78a)
-  Implement StatusBarController for dynamic recording status and click-to-stop functionality (e87072a)
-  Add Delete and Restart buttons to RecordingStatusBarView for enhanced recording control (772580c)
-  Update corner radius and card width for improved QuickAccess layout consistency (7377662)
-  Remove background colors from various video editor views for improved UI consistency (e91a24a)
-  Remove background color from various annotation views for improved UI consistency (203ccb9)
-  Implement window exclusion from screen capture in ScreenRecordingManager (ffa311b)
-  Create dedicated sidebar components for VideoEditor and update VideoBackgroundSidebarView to use them (27e4add)
-  Reduce sizes of gradient preset buttons and adjust grid layout for improved sidebar fit (99b148a)
-  Add Video Editor Background & Padding Feature (fc0cd08)
-  Remove zoom controls from VideoControlsView and implement hover-based zoom placeholder in ZoomTimelineTrack for improved user interaction (5940106)
-  Refactor video info display by creating VideoDetailsSidebarView and integrating it into the main editor layout, replacing the VideoInfoPanel (bd9964b)
-  Refactor ZoomColors to use macOS system colors and enhance UI consistency across video editor components (7405ce1)
-  Improve unsaved changes tracking by refining zoom segment updates and change detection (e714896)
-  Enhance onboarding flow with new CompletionView and improved PermissionsView (395ae8a)
-  Standardize Preferences UI with settingRow helper and icons for improved layout (19548e8)
-  Create AdvancedSettingsView with permissions section and integrate into PreferencesView (1860e43)
-  Implement microphone capture functionality with toggle in recording toolbar (63d6152)
-  Adjust crop rectangle calculation to account for CoreImage coordinate system (1092b13)
-  Adjust padding and frame width in VideoEditor views for improved layout (c8838d2)
-  Update video editor to support original file path for "Replace Original" functionality (9a44211)
-  Enhance video editor with undo/redo support, toolbar integration, and improved export functionality (36a3698)
-  Enhance zoom segment interaction by including disabled segments in selection (31e0fa1)
-  Implement zoom feature in VideoEditor (95dd758)
-  Adjust default window size of Annotate and Video Editor and traffic light positions (341d5a8)
-  implement video editor empty state with drag & drop support (27ab219)
-  add dimensions to banner image for improved display (217c4ff)
-  update banner image for enhanced visual appeal (9b5d4db)
-  update README.md for improved clarity and add banner image (361bb0e)
-  rename app from ZapShot to ClaudeShot (9fbaab0)
-  enhance QuickAccessCardView with drag support and refactor action buttons to use QuickAccessIconButton (b98db1d)
-  centralize layout constants for QuickAccess panel and update related components (a98e9ac)
-  update theme management to use systemAppearance for consistent color scheme across views (5fcce91)
-  update theme management to use effectiveColorScheme for consistent appearance across views (dc3743b)
-  implement theme management with appearance mode selection and update UI components for dynamic theming (c0d23d6)
-  update app icon assets and configuration for ZapShot (3be3019)
-  add edit and delete buttons to QuickAccessCardView with hover support (f5bea81)
-  implement BlurCacheManager for optimized blur rendering and integrate with AnnotationRenderer (067ede7)
-  add About tab in preferences and reorganize update settings (fd8dc0b)
-  integrate Sparkle for update management and add update preferences in settings (d9c46fc)
-  integrate Sparkle package for enhanced update management (d4220e9)
-  add mute functionality and update video export logic to handle muted state (dbcbad6)
-  implement video editor functionality with trimming, exporting, and playback controls (734349b)
-  enhance AnnotateWindowController to manage QuickAccess item lifecycle and cleanup (6081837)
-  implement unsaved changes tracking and enhance save functionality with keyboard shortcuts (042090a)
-  enhance blur functionality with pixelated preview and integrate source image handling (610d7d4)
-  add undo/redo functionality and improve annotation path handling (7dc6c10)
-  implement recording toolbar with options menu, audio settings, and improved button styles (d08a6f3)
-  add resizing functionality to recording region overlay with visual handles (53ec65e)
-  add save confirmation dialog for replacing or saving copies of annotated files (0883c51)
-  implement crop functionality with interactive overlay and state management (6e27018)
-  add drag-and-drop support for quick access items with customizable drag preview (cb13915)
-  enhance quick access functionality to support video items, including thumbnail generation and video editor integration (ef4dc47)
-  implement quick access feature for screenshot management, including UI components and state management (9ed6a7a)
-  add annotation functionality with drag-and-drop support and keyboard shortcuts. Improve the preparation recording phase by adding escape and re-range selection immediately (ebbb26e)
-  add recording coordinator and allows user adjusting the select-area (f70f9b7)
-  update layer priority (450d51b)
-  Implement initial screen recording functionality and add extensive planning for various new features. (1923605)
-  Introduce screen recording functionality with updated preferences, onboarding, and core capture logic, alongside extensive planning for future features. (892bfdd)
-  Add comprehensive feature plans, project documentation, and initial implementations for preferences and onboarding. (9d8e370)
-  Add comprehensive feature plans and refactor the application to a menu bar agent app. (0d3b0e9)
-  Add extensive planning documents for future features and refactors, update the selection tool icon, and create a root README.md. (90f3892)
-  Add comprehensive planning documents for multiple features and refine annotation canvas and text editing views. (6d553a5)
-  Add extensive planning documents for multiple features and enhance the annotation module with new state, views, and rendering logic. (00055fb)
-  add debug.sh to run and build ZapShot app (fc1697b)
-  Implement initial onboarding flow and establish foundational plans for various upcoming features. (db6005b)
-  Implement a comprehensive preferences window with general, quick access, and shortcut settings, alongside enhancements to the floating screenshot feature. (57fe19d)
-  Add detailed plans and research for floating screenshots, annotation, canvas refactor, and custom keyboard shortcuts. (c4bfc6a)
-  Add design documents for annotation, floating screenshot, canvas refactor, and custom keyboard shortcut features, and update floating screenshot components. (fe3255d)
-  Add detailed plans for floating screenshots, canvas refactoring, annotation, and keyboard shortcuts, and outline the integration of the floating screenshot feature. (8550c1a)
-  Add initial plans and research for annotation, floating screenshot, and custom keyboard shortcuts, while updating annotation canvas, sidebar, and floating card views. (8cf3429)
-  Implement annotation feature with state management and UI components (80f1e26)
-  Implement global keyboard shortcut manager for screen capture (8fb5f0d)
-  Add core screen capture functionality and UI components (50397b1)

### Bug Fixes
-  Update bump-version script to use temporary files for sed replacements (f5a8c9a)
-  refine window hiding logic to avoid hiding overlay panels and adjust collection behavior for area selection window (7b217c0)
-  Update keyCodeToString method to join key characters with a space for better readability (e0ba181)
-  Update debug visibility for sandbox indicators and troubleshooting suggestions in LicenseActivationView (cb214a6)
-  Clamp blur and pixelation source regions to image bounds and proportionally adjust destination rectangles for accurate rendering. (60f3fe4)
-  Update bug report URL from zapshot.app to snapzy.app. (8852b3f)
-  Update task label in VSCode configuration and remove obsolete debug script (29071d7)
-  Adjust aspect ratio handling in crop functionality to ensure correct dimensions during resizing (b98feb8)
-  Add delay before area capture to prevent overlay artifacts (5967ff5)
-  Improve cleanup function to provide feedback on app stopping status (f63fcfa)
-  Update launch script to use Snapzy scheme and project name (1f720e0)
-  Correct label formatting in build task for macOS app (6f5048c)

### Chore
- refactor: remove unnecessary coordinate conversion logic in screen capture process (635a807)
- chore: remove setup of Secrets.xcconfig from CI and release workflows (c54fc82)
- chore: adding sponsor info (b2df600)
- chore: remove unused project files and user interface state to streamline project structure (46268e3)
- chore: remove outdated workflow documents for application creation, debugging, deployment, enhancement, orchestration, planning, preview management, status display, testing, and UI/UX design. These changes streamline the agent's capabilities and focus on more relevant functionalities. (61e9f0c)
- chore: add /plans directory to .gitignore to prevent tracking of plan files (59bb788)
- chore: remove outdated plans and reports for the Zoom feature implementation, UI fixes, and Screen Studio analysis. These files are no longer relevant to the current development direction. (304dcef)
- chore: bump version to v1.0.1 (12a6851)
- refactor: improve QuickAccessCard drag-and-drop by implementing sandbox file access and managing drag source lifecycle with a new registry. (b9979d4)
- docs: remove project structure refactoring and migration planning documents. (bf567fe)
- docs: Add guidelines for plan storage location, structure, and naming convention. (eb43e9c)
- refactor: rename StatusBarController to AppStatusBarController (ec92512)
- refactor: Introduce AppCoordinator and AppEnvironment for improved app lifecycle management and dependency injection, removing ContentView. (57318fe)
- chore: remove accidentally committed debug log file. (b458019)
- refactor: Introduce `OnboardingStepContainer` for consistent layout and streamline onboarding navigation by removing the skip confirmation flow. (f37dfca)
- refactor: enhanve .agent (4f35bc7)
- chore: add `*.xcuserstate` to `.gitignore` to prevent committing IDE state files. (3bd2dd8)
- refactor: Derive counter tool value dynamically from existing annotations instead of storing it as a published property. (1b7b5b4)
- refactor: overhaul license management by removing trial and grace period logic, externalizing secrets, and simplifying validation. (fd79c94)
- refactor: Wrap appearance mode picker in a `SettingRow` and compact `AppearanceThumbnailView` layout, also adding `.agent` to gitignore. (9baa1f7)
- refactor: Simplify crosshair drawing logic in AreaSelectionOverlayView (966885d)
- chore: Update build workflow to enable manual triggering and comment out push/release events (fdc60c6)
- refactor!: rename the app to Snapzy (7861072)
- refactor: update preferences section titles and remove unused menu bar icon toggle (cf618de)
- refactor: reduce delay before screen capture and window hiding for improved UI responsiveness (1ad52c3)
- chore: set default video extensions by loading from configs (54f5991)
- docs: Add detailed implementation plans for annotation, floating screenshot, custom keyboard shortcuts, and canvas refactor features, and update screenshot sound to Glass. (029adcf)

### Contributors
- @duongductrong
- @github-actions[bot]
