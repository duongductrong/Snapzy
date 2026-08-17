import Combine
import SwiftUI

/// Settings > Plugins.
///
/// Installed and Discover share one registry fetch: the same index that fills
/// the online list also answers "is there an update" and carries the
/// revocation kill switch, so a forced check here is the only network call the
/// tab makes. Developer tools stay collapsed at the bottom — an author needs
/// them, someone managing their plugins does not.
struct PreferencesPluginsView: View {
  private enum Segment {
    case installed
    case discover
  }

  @ObservedObject private var host = PluginHostController.shared
  @ObservedObject private var registry = PluginRegistryObservable.shared

  @State private var segment: Segment = .installed
  @State private var detailSnapshot: PluginSnapshot?
  @State private var isCheckingUpdates = false
  @State private var updateStatus: String?
  @State private var installingID: String?
  @State private var installNotice: String?
  @State private var installFailed = false

  var body: some View {
    Form {
      Section {
        Text(L10n.PreferencesPlugins.intro)
          .font(.caption)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Picker("", selection: $segment) {
          Text(L10n.PreferencesPlugins.segmentInstalled).tag(Segment.installed)
          Text(L10n.PreferencesPlugins.segmentDiscover).tag(Segment.discover)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }

      switch segment {
      case .installed:
        installedSection
        updatesSection
      case .discover:
        discoverSection
      }

      developerSection
    }
    .formStyle(.grouped)
    .sheet(item: $detailSnapshot) { snapshot in
      PluginDetailSheet(snapshot: snapshot) {
        detailSnapshot = nil
      }
    }
    .task {
      guard case .notLoaded = registry.state else { return }
      await registry.fetch()
      await enforceRevocations()
    }
  }

  // MARK: - Installed

  private var installedSection: some View {
    Section(L10n.PreferencesPlugins.installedSection) {
      if host.snapshots.isEmpty {
        VStack(spacing: 8) {
          Text(L10n.PreferencesPlugins.emptyTitle)
            .font(.headline)
          Text(L10n.PreferencesPlugins.emptyMessage)
            .font(.caption)
            .foregroundColor(.secondary)
          Button(L10n.PreferencesPlugins.emptyAction) {
            segment = .discover
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
      } else {
        ForEach(host.snapshots) { snapshot in
          installedRow(snapshot)
        }
      }
    }
  }

  private func installedRow(_ snapshot: PluginSnapshot) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(snapshot.displayName)
            .fontWeight(.medium)
          PluginStatusBadge(status: snapshot.status)
          PluginTierBadge(tier: snapshot.tier)
        }

        Text(L10n.PreferencesPlugins.version(snapshot.version))
          .font(.caption)
          .foregroundColor(.secondary)

        if let summary = snapshot.summary, !summary.isEmpty {
          Text(summary)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: 8)

      Toggle("", isOn: Binding(
        get: { snapshot.userEnabled ?? true },
        set: { enabled in
          Task { await host.setEnabled(snapshot.id, enabled) }
        }
      ))
      .labelsHidden()
      .help(L10n.PreferencesPlugins.enableHelp)

      Button {
        detailSnapshot = snapshot
      } label: {
        Image(systemName: "chevron.right")
          .foregroundColor(.secondary)
      }
      .buttonStyle(.borderless)
      .help(L10n.PreferencesPlugins.detailsButton)
      .accessibilityLabel(L10n.PreferencesPlugins.detailsButton)
    }
    .padding(.vertical, 4)
  }

  // MARK: - Updates

  private var updatesSection: some View {
    Section(L10n.PreferencesPlugins.updatesSection) {
      SettingRow(
        icon: "arrow.triangle.2.circlepath",
        title: L10n.PreferencesPlugins.checkUpdates,
        description: L10n.PreferencesPlugins.checkUpdatesDescription
      ) {
        Button(isCheckingUpdates ? L10n.PreferencesPlugins.checking : L10n.PreferencesPlugins.checkUpdates) {
          checkForUpdates()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isCheckingUpdates)
      }

      if let updateStatus {
        Text(updateStatus)
          .font(.caption)
          .foregroundColor(.secondary)
          .padding(.leading, 40)
      }

      ForEach(availableUpdates) { entry in
        discoverRow(entry)
      }
    }
  }

  private func checkForUpdates() {
    guard !isCheckingUpdates else { return }
    isCheckingUpdates = true
    updateStatus = nil
    Task {
      await registry.fetch(force: true)
      await enforceRevocations()
      switch registry.state {
      case .loaded, .offline:
        // The update rows below the button carry the news when there is any.
        updateStatus = availableUpdates.isEmpty ? L10n.PreferencesPlugins.checkedJustNow : nil
      case .failed(let reason):
        updateStatus = L10n.PreferencesPlugins.discoverFailed(reason)
      case .notLoaded:
        updateStatus = nil
      }
      isCheckingUpdates = false
    }
  }

  private var availableUpdates: [PluginIndexEntry] {
    PluginUpdateChecker.updatesAvailable(index: registryIndex, installed: host.snapshots)
  }

  // MARK: - Discover

  private var discoverSection: some View {
    Section(L10n.PreferencesPlugins.discoverSection) {
      switch registry.state {
      case .notLoaded:
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(L10n.PreferencesPlugins.discoverLoading)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)

      case .failed(let reason):
        VStack(alignment: .leading, spacing: 8) {
          Text(L10n.PreferencesPlugins.discoverFailed(reason))
            .font(.caption)
            .foregroundColor(.orange)
            .fixedSize(horizontal: false, vertical: true)
          Button(L10n.PreferencesPlugins.discoverRetry) {
            Task { await registry.fetch(force: true) }
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
        .padding(.vertical, 4)

      case .offline(let cached):
        Text(L10n.PreferencesPlugins.discoverOffline)
          .font(.caption)
          .foregroundColor(.orange)
          .fixedSize(horizontal: false, vertical: true)
        if let cached {
          discoverList(cached)
        } else {
          Button(L10n.PreferencesPlugins.discoverRetry) {
            Task { await registry.fetch(force: true) }
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

      case .loaded(let index, _):
        discoverList(index)
      }

      if let installNotice {
        Text(installNotice)
          .font(.caption)
          .foregroundColor(installFailed ? .orange : .secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private func discoverList(_ index: PluginRegistryIndex) -> some View {
    if index.plugins.isEmpty {
      Text(L10n.PreferencesPlugins.discoverEmpty)
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.vertical, 4)
    } else {
      ForEach(index.plugins) { entry in
        discoverRow(entry)
      }
    }
  }

  private func discoverRow(_ entry: PluginIndexEntry) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(entry.displayName)
              .fontWeight(.medium)
            if entry.revoked {
              StatusBadge(
                label: L10n.PreferencesPlugins.withdrawn,
                systemImage: "exclamationmark.triangle.fill",
                tint: .red
              )
            } else if let tier = PluginTier(rawValue: entry.tier) {
              PluginTierBadge(tier: tier)
            }
          }

          Text(L10n.PreferencesPlugins.version(entry.version))
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer(minLength: 8)

        discoverAction(entry)
      }

      if let summary = entry.summary, !summary.isEmpty {
        Text(summary)
          .font(.caption)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if entry.revoked {
        Text(L10n.PreferencesPlugins.withdrawnMessage)
          .font(.caption)
          .foregroundColor(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func discoverAction(_ entry: PluginIndexEntry) -> some View {
    if entry.revoked {
      EmptyView()
    } else if installingID == entry.id {
      Button(L10n.PreferencesPlugins.installing) {}
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(true)
    } else if let installedVersion = installedVersions[entry.id] {
      if PluginUpdateChecker.isUpdate(entry.version, newerThan: installedVersion) {
        Button(L10n.PreferencesPlugins.update) {
          install(entry)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(installingID != nil)
      } else {
        Text(L10n.PreferencesPlugins.installed)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    } else {
      Button(L10n.PreferencesPlugins.install) {
        install(entry)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .disabled(installingID != nil)
    }
  }

  private func install(_ entry: PluginIndexEntry) {
    guard installingID == nil else { return }
    installNotice = nil
    installingID = entry.id
    Task {
      do {
        // The installer re-discovers plugins itself on success.
        try await PluginInstaller.shared.install(entry: entry)
        installNotice = L10n.PreferencesPlugins.installSucceeded
        installFailed = false
      } catch {
        let reason = (error as? PluginInstaller.InstallError)?.description
          ?? error.localizedDescription
        installNotice = L10n.PreferencesPlugins.installFailed(reason)
        installFailed = true
      }
      installingID = nil
    }
  }

  // MARK: - Developer tools

  private var developerSection: some View {
    Section {
      DisclosureGroup {
        VStack(alignment: .leading, spacing: 16) {
          Text(L10n.PreferencesPlugins.developerDescription)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

          PluginDevelopmentSection()
          PluginActivityLogSection()
        }
        .padding(.vertical, 4)
      } label: {
        Text(L10n.PreferencesPlugins.developerSection)
          .fontWeight(.medium)
      }
    }
  }

  // MARK: - Helpers

  private var registryIndex: PluginRegistryIndex? {
    switch registry.state {
    case .loaded(let index, _): return index
    case .offline(let index?): return index
    default: return nil
    }
  }

  private var installedVersions: [String: String] {
    Dictionary(host.snapshots.map { ($0.id, $0.version) }, uniquingKeysWith: { first, _ in first })
  }

  /// The kill switch rides on every successful fetch, user-initiated or not.
  private func enforceRevocations() async {
    guard let index = registryIndex else { return }
    await PluginRevocationEnforcer.enforce(index)
  }
}

// MARK: - Registry observability

/// `PluginRegistryClient` lives on the plugin engine actor and is deliberately
/// not observable; this mirror republishes its state after every fetch so the
/// tab can render it.
@MainActor
final class PluginRegistryObservable: ObservableObject {
  static let shared = PluginRegistryObservable()

  @Published private(set) var state: PluginRegistryClient.State = .notLoaded

  private var inFlight = false

  private init() {}

  func fetch(force: Bool = false) async {
    guard !inFlight else { return }
    inFlight = true
    defer { inFlight = false }
    await PluginRegistryClient.shared.fetch(force: force)
    state = await PluginRegistryClient.shared.state
  }
}

#Preview {
  PreferencesPluginsView()
    .formStyle(.grouped)
}
