# Sparkle 2 Implementation Research Report

## Appcast Feed Setup

### Structure
```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ZapShot Updates</title>
    <item>
      <title>Version 1.1</title>
      <sparkle:version>1.1</sparkle:version>
      <sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
      <pubDate>Sat, 18 Jan 2025 12:00:00 +0000</pubDate>
      <sparkle:releaseNotesLink>https://example.com/notes.html</sparkle:releaseNotesLink>
      <enclosure url="https://example.com/ZapShot-1.1.zip"
                 sparkle:edSignature="..."
                 length="12345678"
                 type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

### Hosting
- HTTPS required for security
- Host appcast XML and update archives on web server
- GitHub Releases works well for hosting

### generate_appcast Tool
```bash
./bin/generate_appcast /path/to/updates
```
- Auto-generates appcast from archives
- Creates EdDSA signatures
- Generates delta updates

## Code Signing & Security

### Requirements
1. Code sign app with Developer ID
2. Notarize app for macOS distribution
3. Sign update archives with EdDSA
4. Serve all content over HTTPS

### EdDSA Key Generation
```bash
./bin/generate_keys
```
- Stores private key in Keychain
- Outputs public key for Info.plist

## SwiftUI Integration

### Programmatic Setup (Required for SwiftUI)
```swift
import Sparkle

@main
struct MyApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup { ContentView() }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}
```

### CheckForUpdatesView
```swift
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var viewModel: CheckForUpdatesViewModel
    let updater: SPUUpdater

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
```

## Sandboxing Considerations
- For sandboxed apps, use XPC Services (included in Sparkle)
- Non-sandboxed direct distribution: simpler setup
- Mac App Store apps cannot use Sparkle (use App Store updates)

## UI Customization
- SPUStandardUserDriver provides default UI
- Custom delegates for advanced customization
- Gentle reminders configurable via delegate

## Sources
- https://sparkle-project.org/documentation/
- https://sparkle-project.org/documentation/programmatic-setup/
- https://sparkle-project.org/documentation/publishing/
