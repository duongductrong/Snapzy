import AppKit
import Combine
import SwiftUI

/// Developer tools, collapsed by default.
///
/// Loading a folder and reading the activity log turn "my plugin doesn't work"
/// into a self-service fix — but only an author ever needs them, so they live
/// behind one disclosure rather than in the middle of the tab.
struct PluginDevelopmentSection: View {
  @ObservedObject private var host = PluginHostController.shared
  @State private var loadResult: String?
  @State private var loadFailed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingRow(
        icon: "folder.badge.plus",
        title: L10n.PreferencesPlugins.loadFolder,
        description: loadFailed ? L10n.PreferencesPlugins.developmentNote
          : (loadResult ?? L10n.PreferencesPlugins.developmentNote)
      ) {
        // The row title already says what this loads; the button only has to
        // say what clicking it does.
        Button(L10n.PreferencesGeneral.chooseButton) {
          loadPluginFromFolder()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }

      if loadFailed, let loadResult {
        Label(loadResult, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundColor(.orange)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.leading, 40)
      }

      ForEach(developmentPlugins) { snapshot in
        HStack(spacing: 8) {
          Circle()
            .fill(Color.blue)
            .frame(width: 6, height: 6)
          Text(snapshot.displayName)
            .font(.caption)
          Text(snapshot.id)
            .font(.caption2.monospaced())
            .foregroundColor(.secondary)
            .textSelection(.enabled)
          Spacer(minLength: 0)
        }
        .padding(.leading, 40)
      }
    }
  }

  private var developmentPlugins: [PluginSnapshot] {
    host.snapshots.filter { $0.tier == .sideloaded }
  }

  private func loadPluginFromFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = L10n.PreferencesPlugins.loadFolderPrompt
    guard panel.runModal() == .OK, let url = panel.url else { return }

    Task {
      do {
        let name = try await PluginDevelopmentWatcher.shared.load(from: url)
        loadResult = L10n.PreferencesPlugins.loadFolderSucceeded(name)
        loadFailed = false
      } catch {
        loadResult = L10n.PreferencesPlugins.loadFolderFailed(String(describing: error))
        loadFailed = true
      }
    }
  }
}

/// The last 100 host calls, redacted at write time. Copy-as-text is safe to
/// paste into an issue — no credential can appear.
struct PluginActivityLogSection: View {
  @ObservedObject private var observable = PluginRequestLogObservable.shared
  @State private var didCopy = false

  private var recentEntries: [PluginRequestLogEntry] {
    observable.entries.reversed().prefix(20).map { $0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.PreferencesPlugins.activityLog)
            .fontWeight(.medium)
          Text(L10n.PreferencesPlugins.activityLogDescription)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)

        Button(L10n.PreferencesPlugins.refresh) {
          Task { await observable.reload() }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        Button(didCopy ? L10n.PreferencesPlugins.copied : L10n.PreferencesPlugins.copy) {
          copyAsText()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(observable.entries.isEmpty)
      }

      if observable.entries.isEmpty {
        Text(L10n.PreferencesPlugins.activityLogEmpty)
          .font(.caption)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(recentEntries) { entry in
              VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                  Text(entry.pluginID)
                    .font(.caption2.weight(.semibold).monospaced())
                  Text(entry.service)
                    .font(.caption2.monospaced())
                  Spacer()
                  Text(entry.outcome)
                    .font(.caption2)
                    .foregroundColor(entry.outcome == "ok" ? .secondary : .orange)
                }
                Text(entry.summary)
                  .font(.caption.monospaced())
                  .foregroundColor(.secondary)
                  .lineLimit(1)
              }
              .padding(.vertical, 2)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
      }
    }
    .padding(.vertical, 4)
    .onAppear {
      Task { await observable.reload() }
    }
  }

  private func copyAsText() {
    let text = observable.entries.map {
      "[\($0.timestamp.formatted(date: .omitted, time: .standard))] \($0.pluginID) · \($0.service) · \($0.outcome)\n  \($0.summary)"
    }.joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    didCopy = true
  }
}

// MARK: - Inspector observability

@MainActor
final class PluginRequestLogObservable: ObservableObject {
  static let shared = PluginRequestLogObservable()

  @Published var entries: [PluginRequestLogEntry] = []
  @Published var refreshToken = 0

  private init() {}

  func reload() async {
    entries = await PluginRequestLog.shared.recentEntries()
    refreshToken += 1
  }
}
