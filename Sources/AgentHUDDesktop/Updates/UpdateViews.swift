// Modified by Lotus for Agent Monitor. See docs/UPSTREAM.md.
import AppKit
import AgentHUDCore
import SwiftUI

/// Shows update status and opens release links after a user action.
public struct UpdateSettingsSection: View {
    @Bindable private var updates: AppUpdateStore
    private let onOpen: (URL) -> Void

    public init(updates: AppUpdateStore, onOpen: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.updates = updates
        self.onOpen = onOpen
    }

    public var body: some View {
        SettingsSection(title: L10n.text("软件更新", "Software updates")) {
            SettingRow(label: L10n.text("当前版本", "Current version"), subtitle: updates.currentVersion) {
                Button(L10n.text("检查更新", "Check for Updates")) { Task { await updates.checkNow() } }
                    .disabled(updates.state == .checking)
                    .accessibilityIdentifier("updates-check-now")
            }
            SettingsDivider()
            SettingsToggleRow(label: L10n.text("自动检查更新", "Check for updates automatically"),
                              subtitle: L10n.text("启动时检查，每 24 小时最多一次。", "Check at startup, at most once every 24 hours."),
                              isOn: $updates.automaticChecksEnabled)
                .accessibilityIdentifier("updates-automatic")
            SettingsDivider()
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    if updates.state == .checking { ProgressView().controlSize(.small) }
                    Text(statusText).font(.ui(12)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("updates-status")
                }
                if let checked = updates.lastCheckedAt {
                    Text(L10n.text("上次检查：", "Last checked: ") + checked.formatted(date: .abbreviated, time: .shortened))
                        .font(.ui(11)).settingsSubtitle().accessibilityIdentifier("updates-last-checked")
                }
                if let release = updates.availableRelease {
                    UpdateReleaseActions(release: release, onOpen: onOpen)
                    Text(L10n.text("下载后手动替换 App。", "Replace the app manually after downloading."))
                        .font(.ui(11)).settingsSubtitle()
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
        .accessibilityIdentifier("updates-settings")
    }

    private var statusText: String {
        switch updates.state {
        case .idle: L10n.text("尚未检查更新。", "Updates have not been checked yet.")
        case .checking: L10n.text("正在检查更新…", "Checking for updates…")
        case .upToDate: L10n.text("已是最新版本。", "You are up to date.")
        case .noRelease: L10n.text("尚无可用的正式版本。", "No stable release is available yet.")
        case .available(let release): L10n.text("新版本 \(release.version) 可用。", "Version \(release.version) is available.")
        case .failed(let failure):
            switch failure {
            case .network: L10n.text("无法连接，请稍后重试。", "Cannot connect. Please try again later.")
            case .rateLimited: L10n.text("检查次数过多，请稍后重试。", "Too many checks. Please try again later.")
            case .invalidResponse: L10n.text("无法验证版本信息，请稍后重试。", "Cannot verify the release. Please try again later.")
            case .serviceUnavailable: L10n.text("更新服务暂时无法使用，请稍后重试。", "The update service is unavailable. Please try again later.")
            }
        }
    }
}

/// Adds a passive release notice to the expanded HUD.
public struct UpdateNotice: View {
    private let updates: AppUpdateStore
    private let onOpen: (URL) -> Void

    public init(updates: AppUpdateStore, onOpen: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.updates = updates
        self.onOpen = onOpen
    }

    public var body: some View {
        if let release = updates.availableRelease {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.text("新版本 \(release.version) 可用", "Version \(release.version) is available"), systemImage: "arrow.down.circle")
                    .font(.ui(12, .medium))
                UpdateReleaseActions(release: release, onOpen: onOpen)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12).settingsCard()
            .accessibilityIdentifier("updates-hud-notice")
        }
    }
}

private struct UpdateReleaseActions: View {
    let release: UpdateRelease
    let onOpen: (URL) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(L10n.text("查看版本", "View Release")) { onOpen(release.pageURL) }
                .accessibilityIdentifier("updates-view-release")
            Button(L10n.text("下载更新", "Download Update")) { onOpen(release.downloadURL) }
                .accessibilityIdentifier("updates-download")
        }.controlSize(.small)
    }
}

/// Keeps preview and probe controls independent of external update services.
public struct DisabledUpdateReleaseClient: UpdateReleaseClient {
    public init() {}
    public func latestRelease() async throws -> UpdateRelease? { nil }
}
