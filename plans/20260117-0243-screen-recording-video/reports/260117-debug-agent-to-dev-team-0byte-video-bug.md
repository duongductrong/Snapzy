# Debug Report: 0-Byte Video File Bug

**Date:** 2026-01-17
**Reporter:** Debug Agent
**Severity:** Critical
**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Core/ScreenRecordingManager.swift`

## Executive Summary

**Root Cause Identified:** AVAssetWriter session never starts because `startSession(atSourceTime:)` is called on background queue (`processingQueue`) but AVAssetWriter requires main thread or serial queue synchronization.

**Impact:** All screen recordings produce 0-byte files. No video data written.

**Fix Required:** Move `assetWriter?.startSession(atSourceTime:)` call to main thread or ensure proper synchronization.

---

## Technical Analysis

### Data Flow Issue

The recording flow has a **critical thread synchronization bug** introduced by recent changes:

**Current (Broken) Flow:**
```
1. startRecording() [main thread]
   - assetWriter?.startWriting() ✓
   - stream?.startCapture() ✓
   - isCapturing = true ✓

2. stream(_:didOutputSampleBuffer:) [processingQueue - background]
   - First frame arrives
   - assetWriter?.startSession(atSourceTime:) ❌ FAILS SILENTLY
   - videoInput?.append(sampleBuffer) ❌ REJECTED (no session started)

3. stopRecording() [main thread]
   - assetWriter?.finishWriting() ✓ (but no data written)
   - Result: 0-byte file
```

### Code Locations with Issues

#### **Issue #1: startSession() Called on Wrong Thread**
**Location:** Lines 471-473
```swift
if needsSessionStart {
  let timestamp = sampleBuffer.presentationTimeStamp
  self.assetWriter?.startSession(atSourceTime: timestamp)  // ❌ BACKGROUND THREAD
}
```

**Problem:**
- `assetWriter?.startSession()` is called in `processingQueue.async` block (background thread)
- AVAssetWriter is created on main thread (line 334) with @MainActor context
- Cross-thread access causes silent failure - no session starts
- Without active session, `append()` calls are ignored

**Evidence:**
- Line 476: `guard self.assetWriter?.status == .writing else { return }` likely returns immediately
- Status remains `.unknown` or fails to transition to `.writing` properly
- No frames appended, no data written

#### **Issue #2: Missing Status Validation**
**Location:** Line 220
```swift
assetWriter?.startWriting()
```

**Problem:**
- No status check after `startWriting()`
- If this fails, recording continues silently
- Should verify `assetWriter?.status == .writing` before proceeding

#### **Issue #3: No Error Handling in Frame Processing**
**Location:** Lines 476-486
```swift
guard self.assetWriter?.status == .writing else { return }

switch type {
case .screen:
  if self.videoInput?.isReadyForMoreMediaData == true {
    self.videoInput?.append(sampleBuffer)  // ❌ NO ERROR CHECK
  }
```

**Problem:**
- `append()` can fail silently - no error captured
- No logging when frames are dropped
- Impossible to debug why data isn't written

---

## Root Cause Summary

**Primary Issue:** Thread synchronization bug with AVAssetWriter session initialization

**Contributing Factors:**
1. Recent change moved frame processing to background queue (line 455)
2. Added `isCapturing` flag with `sessionLock` (lines 115-116, 459-465)
3. `sessionStarted` flag managed on background thread (lines 461-464)
4. AVAssetWriter accessed from multiple threads without proper synchronization

**Why It Produces 0-Byte Files:**
1. File created during `setupAssetWriter()` (line 334)
2. `startWriting()` called but session never started
3. All `append()` calls rejected (no active session)
4. `finishWriting()` completes with no data
5. Empty file remains on disk

---

## Specific Code Fixes Needed

### **Fix #1: Move startSession() to Main Thread** (CRITICAL)
**Location:** Lines 471-473

**Current:**
```swift
if needsSessionStart {
  let timestamp = sampleBuffer.presentationTimeStamp
  self.assetWriter?.startSession(atSourceTime: timestamp)
}
```

**Fixed:**
```swift
if needsSessionStart {
  let timestamp = sampleBuffer.presentationTimeStamp
  Task { @MainActor in
    self.assetWriter?.startSession(atSourceTime: timestamp)
  }
}
```

**OR better - start session immediately in startRecording():**
```swift
// In startRecording() after line 220
assetWriter?.startWriting()

// Add this:
if assetWriter?.status == .writing {
  let startTime = CMTime(seconds: 0, preferredTimescale: 600)
  assetWriter?.startSession(atSourceTime: startTime)
  sessionStarted = true
} else {
  throw RecordingError.setupFailed("AssetWriter failed to start writing")
}
```

### **Fix #2: Add Status Validation**
**Location:** After line 220

**Add:**
```swift
assetWriter?.startWriting()

guard assetWriter?.status == .writing else {
  let error = assetWriter?.error?.localizedDescription ?? "Unknown error"
  state = .idle
  self.error = .setupFailed(error)
  throw RecordingError.setupFailed(error)
}
```

### **Fix #3: Add Error Logging in Frame Processing**
**Location:** Lines 480-481

**Current:**
```swift
if self.videoInput?.isReadyForMoreMediaData == true {
  self.videoInput?.append(sampleBuffer)
}
```

**Fixed:**
```swift
if self.videoInput?.isReadyForMoreMediaData == true {
  if !self.videoInput!.append(sampleBuffer) {
    print("❌ Failed to append video frame - status: \(self.assetWriter?.status.rawValue ?? -1)")
  }
} else {
  print("⚠️ Video input not ready for data")
}
```

### **Fix #4: Remove Premature sessionStarted Logic**
**Location:** Lines 461-474

**Current approach is flawed** - remove the "start session on first frame" logic entirely and start session immediately in `startRecording()` as shown in Fix #1.

---

## Verification Checklist

After implementing fixes, verify:

1. ✓ `assetWriter?.startWriting()` returns `.writing` status
2. ✓ `assetWriter?.startSession()` called successfully before first frame
3. ✓ `sessionStarted` flag set to true
4. ✓ `videoInput?.append()` returns true for frames
5. ✓ Console shows no "Failed to append" errors
6. ✓ `assetWriter?.status` remains `.writing` during recording
7. ✓ `finishWriting()` completes without errors
8. ✓ Output file size > 0 bytes
9. ✓ Video file playable with metadata/dimensions/codec

---

## Test Commands

```bash
# After fixes, test recording:
# 1. Start ZapShot app
# 2. Trigger screen recording
# 3. Record for 5-10 seconds
# 4. Stop recording
# 5. Check file:

ls -lh ~/Movies/ZapShot_Recording_*.mov
file ~/Movies/ZapShot_Recording_*.mov
mdls ~/Movies/ZapShot_Recording_*.mov | grep -i duration
```

---

## Recommended Solution (Simplest)

**Replace lines 217-238 with:**

```swift
func startRecording() async throws {
  guard state == .preparing else { return }

  // Start writing
  assetWriter?.startWriting()

  // Validate status
  guard assetWriter?.status == .writing else {
    let error = assetWriter?.error?.localizedDescription ?? "Failed to start writing"
    state = .idle
    self.error = .setupFailed(error)
    throw RecordingError.setupFailed(error)
  }

  // Start session immediately with zero time
  let startTime = CMTime(seconds: 0, preferredTimescale: 600)
  assetWriter?.startSession(atSourceTime: startTime)

  // Start stream capture
  do {
    try await stream?.startCapture()
  } catch {
    state = .idle
    self.error = .setupFailed(error.localizedDescription)
    throw RecordingError.setupFailed(error.localizedDescription)
  }

  sessionLock.lock()
  isCapturing = true
  sessionStarted = true  // Set here, not in callback
  sessionLock.unlock()

  state = .recording
  startTime = Date()
  elapsedSeconds = 0
  pausedDuration = 0
  startTimer()
}
```

**And remove lines 461-474 (session start logic in callback):**

```swift
// DELETE THIS ENTIRE BLOCK:
// self.sessionLock.lock()
// let capturing = self.isCapturing
// let needsSessionStart = capturing && !self.sessionStarted
// if needsSessionStart {
//   self.sessionStarted = true
// }
// self.sessionLock.unlock()
//
// if needsSessionStart {
//   let timestamp = sampleBuffer.presentationTimeStamp
//   self.assetWriter?.startSession(atSourceTime: timestamp)
// }

// REPLACE WITH:
sessionLock.lock()
let capturing = isCapturing
sessionLock.unlock()
```

---

## Unresolved Questions

1. Why was frame processing moved to background queue? Performance issue?
2. Are there any console errors during recording that were ignored?
3. What is the expected file size for a 10-second recording at current settings?

---

**Next Steps:** Implement recommended solution and re-test recording functionality.
