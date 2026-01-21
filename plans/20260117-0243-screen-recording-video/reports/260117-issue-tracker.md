# Screen Recording - Issue Tracker

## High Priority

### #1 Frame Processing on Main Thread
- **File:** `ScreenRecordingManager.swift:419-445`
- **Severity:** HIGH
- **Impact:** Frame drops, UI stuttering during recording
- **Status:** 🔴 Open
- **Fix:**
```swift
nonisolated func stream(...) {
    guard sampleBuffer.isValid else { return }

    processingQueue.async { [weak self] in
        guard let self = self else { return }
        // Move all append() calls to background queue
        // Only access @MainActor state when necessary
    }
}
```

### #2 sessionStarted Race Condition
- **File:** `ScreenRecordingManager.swift:97,424-427`
- **Severity:** HIGH
- **Impact:** Possible duplicate startSession calls
- **Status:** 🔴 Open
- **Fix:**
```swift
private let sessionStartedLock = NSLock()
private var _sessionStarted = false
private var sessionStarted: Bool {
    get {
        sessionStartedLock.lock()
        defer { sessionStartedLock.unlock() }
        return _sessionStarted
    }
    set {
        sessionStartedLock.lock()
        defer { sessionStartedLock.unlock() }
        _sessionStarted = newValue
    }
}
```

### #3 Quality Setting Not Implemented
- **File:** `RecordingSettingsView.swift:37-41`, `RecordingCoordinator.swift`
- **Severity:** MEDIUM-HIGH
- **Impact:** User setting has no effect
- **Status:** 🔴 Open
- **Fix:** Read quality preference and apply to bitrate multiplier

### #4 No User Error Feedback
- **File:** `RecordingCoordinator.swift:108-111`
- **Severity:** MEDIUM-HIGH
- **Impact:** Silent failures confuse users
- **Status:** 🔴 Open
- **Fix:** Show NSAlert with error.localizedDescription

## Medium Priority

### #5 Timer Runs During Pause
- **File:** `ScreenRecordingManager.swift:216-228`
- **Severity:** MEDIUM
- **Impact:** Unnecessary CPU usage
- **Status:** 🟡 Open
- **Fix:** Invalidate timer on pause, restart on resume

### #6 Microphone Setting Not Implemented
- **File:** `RecordingSettingsView.swift:50-51`
- **Severity:** MEDIUM
- **Impact:** UI toggle has no backend
- **Status:** 🟡 Open
- **Decision needed:** Implement or remove for MVP

### #7 No File Size Limits
- **File:** `ScreenRecordingManager.swift`
- **Severity:** MEDIUM
- **Impact:** Could fill disk with long recordings
- **Status:** 🟡 Open
- **Fix:** Add maxDuration check in updateElapsedTime()

### #8 Retina Fallback Wrong
- **File:** `ScreenRecordingManager.swift:176`
- **Severity:** MEDIUM
- **Impact:** Wrong resolution on non-Retina displays
- **Status:** 🟡 Open
- **Fix:** Change fallback from 2.0 to 1.0

### #9 Missing Cleanup on Prepare Failure
- **File:** `ScreenRecordingManager.swift:146-149`
- **Severity:** MEDIUM
- **Impact:** State corruption on errors
- **Status:** 🟡 Open
- **Fix:** Call cleanup() in catch blocks

### #10 Unused Error Property
- **File:** `ScreenRecordingManager.swift:79`
- **Severity:** LOW
- **Impact:** Dead code
- **Status:** 🟡 Open
- **Fix:** Use in UI or remove

## Low Priority

### #11 Magic Numbers in Layout
- **File:** `RecordingToolbarWindow.swift:98,101-107`
- **Fix:** Extract to named constants

### #12 Force Unwrap in saveDirectory
- **File:** `RecordingCoordinator.swift:86`
- **Fix:** Use guard let instead

### #13 Missing Documentation
- **Files:** Multiple
- **Fix:** Add Swift doc comments to public APIs

## Resolved
None yet.
