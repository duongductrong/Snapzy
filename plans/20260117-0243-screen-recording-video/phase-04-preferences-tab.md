# Phase 4: Preferences Tab

## Context Links
- [Main Plan](./plan.md)
- [Phase 3: Recording UI Components](./phase-03-recording-ui-components.md)
- [Recording UI Patterns Research](./research/researcher-02-recording-ui-patterns.md)

## Overview
Replace the Recording placeholder tab in Preferences with actual settings: video format, frame rate, quality, audio capture options.

## Requirements
- R1: Video format picker (MOV default, MP4)
- R2: Frame rate picker (30 FPS default, 60 FPS)
- R3: Quality picker (High/Medium/Low)
- R4: System audio toggle
- R5: Microphone toggle
- R6: Use existing export location from General tab

## Related Code Files

### Reference
| File | Purpose |
|------|---------|
| `ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift` | Form pattern |
| `ZapShot/Features/Preferences/PreferencesKeys.swift` | Keys pattern |

### Create
| File | Purpose |
|------|---------|
| `ZapShot/Features/Preferences/Tabs/RecordingSettingsView.swift` | Recording preferences |

### Modify
| File | Changes |
|------|---------|
| `ZapShot/Features/Preferences/PreferencesView.swift` | Replace placeholder |
| `ZapShot/Features/Preferences/PreferencesKeys.swift` | Add recording keys |

## Implementation Steps

### Step 1: Add keys to PreferencesKeys (if not done in Phase 3)
```swift
// Recording
static let recordingFormat = "recording.format"
static let recordingFPS = "recording.fps"
static let recordingQuality = "recording.quality"
static let recordingCaptureAudio = "recording.captureAudio"
static let recordingCaptureMicrophone = "recording.captureMicrophone"
```

### Step 2: Create RecordingSettingsView
File: `ZapShot/Features/Preferences/Tabs/RecordingSettingsView.swift`

```swift
import SwiftUI

struct RecordingSettingsView: View {
    @AppStorage(PreferencesKeys.recordingFormat) private var format = "mov"
    @AppStorage(PreferencesKeys.recordingFPS) private var fps = 30
    @AppStorage(PreferencesKeys.recordingQuality) private var quality = "high"
    @AppStorage(PreferencesKeys.recordingCaptureAudio) private var captureAudio = true
    @AppStorage(PreferencesKeys.recordingCaptureMicrophone) private var captureMicrophone = false

    var body: some View {
        Form {
            Section("Format") {
                Picker("Video Format", selection: $format) {
                    Text("MOV (Recommended)").tag("mov")
                    Text("MP4").tag("mp4")
                }
                .pickerStyle(.radioGroup)

                Text("MOV offers better quality. MP4 provides wider compatibility.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Quality") {
                Picker("Frame Rate", selection: $fps) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }

                Picker("Quality", selection: $quality) {
                    Text("High").tag("high")
                    Text("Medium").tag("medium")
                    Text("Low").tag("low")
                }

                Text("Higher quality results in larger file sizes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Audio") {
                Toggle("Capture System Audio", isOn: $captureAudio)
                Toggle("Capture Microphone", isOn: $captureMicrophone)
                    .disabled(!captureAudio)

                Text("System audio captures sounds from apps. Microphone captures your voice.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Save Location") {
                HStack {
                    Text("Recordings save to the same location as screenshots.")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("General tab")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    RecordingSettingsView()
        .frame(width: 500, height: 400)
}
```

### Step 3: Update PreferencesView
File: `ZapShot/Features/Preferences/PreferencesView.swift`

Replace:
```swift
PlaceholderSettingsView.recording
    .tabItem { Label("Recording", systemImage: "video") }
```

With:
```swift
RecordingSettingsView()
    .tabItem { Label("Recording", systemImage: "video") }
```

## Todo List
- [ ] Add recording keys to PreferencesKeys.swift
- [ ] Create RecordingSettingsView.swift
- [ ] Replace placeholder in PreferencesView.swift
- [ ] Test format picker persists selection
- [ ] Test FPS picker persists selection
- [ ] Test audio toggles work correctly

## Success Criteria
1. Recording tab shows actual settings instead of placeholder
2. Format selection persists across app launches
3. FPS selection persists
4. Audio toggles work and persist
5. Microphone toggle disabled when system audio off

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Key name conflicts | Low | Use prefixed keys (recording.*) |
| Default values not applied | Low | Use AppStorage with defaults |
