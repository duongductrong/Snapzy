# Phase 04: Create Video Details Sidebar

## Context

- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** Phase 03 (state and button)
- **Docs:** AnnotateSidebarView.swift (pattern reference)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-24 |
| Description | Create VideoDetailsSidebarView with comprehensive video metadata |
| Priority | High |
| Implementation Status | Pending |
| Review Status | Not Started |

## Key Insights

- Follow AnnotateSidebarView pattern: ScrollView + VStack + controlBackgroundColor
- VideoEditorState has: filename, resolutionString, fileExtension, formattedDuration
- Need to add: file size, aspect ratio, frame rate, bitrate, creation/modification dates
- Some metadata requires AVAsset async loading

## Requirements

1. Create VideoDetailsSidebarView.swift
2. Display: Filename, Path, Size, Resolution, Aspect ratio, Format, Duration, Frame rate, Dates
3. Show zoom segments summary
4. Match AnnotateSidebarView styling
5. Width: 280px (narrower than zoom settings 320px)

## Architecture

```
VideoDetailsSidebarView
  @ObservedObject var state: VideoEditorState
  - fileInfoSection
  - videoInfoSection
  - zoomSummarySection
```

New computed properties in VideoEditorState:
- aspectRatioString
- fileSizeString (async or from URL)
- creationDateString
- modificationDateString

## Related Code Files

| File | Purpose |
|------|---------|
| `ClaudeShot/Features/VideoEditor/Views/VideoDetailsSidebarView.swift` | NEW - sidebar component |
| `ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift` | Add computed properties |
| `ClaudeShot/Features/Annotate/Views/AnnotateSidebarView.swift` | Pattern reference |

## Implementation Steps

### VideoEditorState.swift - Add Computed Properties

After `resolutionString` (line 130):

```swift
var aspectRatioString: String {
  guard naturalSize.width > 0 && naturalSize.height > 0 else { return "-" }
  let gcd = gcd(Int(naturalSize.width), Int(naturalSize.height))
  let w = Int(naturalSize.width) / gcd
  let h = Int(naturalSize.height) / gcd
  return "\(w):\(h)"
}

var fileSizeString: String {
  guard let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
        let size = attrs[.size] as? Int64 else { return "-" }
  return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
}

var fileCreationDate: Date? {
  try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.creationDate] as? Date
}

var fileModificationDate: Date? {
  try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.modificationDate] as? Date
}

private func gcd(_ a: Int, _ b: Int) -> Int {
  b == 0 ? a : gcd(b, a % b)
}
```

### VideoDetailsSidebarView.swift - New File

```swift
//
//  VideoDetailsSidebarView.swift
//  ClaudeShot
//
//  Video details sidebar with comprehensive metadata
//

import SwiftUI

struct VideoDetailsSidebarView: View {
  @ObservedObject var state: VideoEditorState

  private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 16) {
        // Header
        HStack {
          Image(systemName: "info.circle.fill")
            .foregroundColor(ZoomColors.primary)
          Text("Video Details")
            .font(.system(size: 13, weight: .semibold))
        }

        Divider()

        // File Info Section
        SidebarSection(title: "File") {
          DetailRow(label: "Name", value: state.filename)
          DetailRow(label: "Path", value: state.sourceURL.deletingLastPathComponent().path)
          DetailRow(label: "Size", value: state.fileSizeString)
          DetailRow(label: "Format", value: state.fileExtension.uppercased())
        }

        // Video Info Section
        SidebarSection(title: "Video") {
          DetailRow(label: "Resolution", value: state.resolutionString)
          DetailRow(label: "Aspect Ratio", value: state.aspectRatioString)
          DetailRow(label: "Duration", value: state.formattedDuration)
        }

        // Dates Section
        SidebarSection(title: "Dates") {
          if let created = state.fileCreationDate {
            DetailRow(label: "Created", value: dateFormatter.string(from: created))
          }
          if let modified = state.fileModificationDate {
            DetailRow(label: "Modified", value: dateFormatter.string(from: modified))
          }
        }

        // Zoom Summary
        if !state.zoomSegments.isEmpty {
          SidebarSection(title: "Zoom Effects") {
            DetailRow(label: "Segments", value: "\(state.zoomSegments.count)")
            DetailRow(label: "Enabled", value: "\(state.zoomSegments.filter { $0.isEnabled }.count)")
          }
        }

        Spacer(minLength: 20)
      }
      .padding(12)
    }
    .frame(maxHeight: .infinity)
    .background(Color(NSColor.controlBackgroundColor))
  }
}

// MARK: - Components

private struct SidebarSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)
        .textCase(.uppercase)
      content
    }
  }
}

private struct DetailRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack {
      Text(label)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
      Spacer()
      Text(value)
        .font(.system(size: 11))
        .foregroundColor(.primary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }
}
```

## Todo

- [ ] Add aspectRatioString computed property
- [ ] Add fileSizeString computed property
- [ ] Add date computed properties
- [ ] Add gcd helper function
- [ ] Create VideoDetailsSidebarView.swift
- [ ] Add SidebarSection component
- [ ] Add DetailRow component
- [ ] Test with various videos

## Success Criteria

- Sidebar displays all metadata correctly
- Styling matches AnnotateSidebarView
- Handles missing/loading data gracefully
- Scrollable for long content

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| File attrs access fail | Low | Low | Return "-" fallback |
| Long paths truncate | Medium | Low | truncationMode(.middle) |

## Security Considerations

- File path display: acceptable for local app
- No external data exposure

## Next Steps

Proceed to Phase 05: Integrate Sidebar and Cleanup
