import AppKit
import SwiftUI
import Observation
import AgentHUDCore

public enum MainWindowPage: String, CaseIterable, Sendable {
    case overview, processes, docker, localServices, tokens, sessions, settings

    var title: String {
        switch self {
        case .overview: "總覽"
        case .processes: "程序"
        case .docker: "Docker"
        case .localServices: "本機服務"
        case .tokens: "Token"
        case .sessions: "會話"
        case .settings: "設定"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "waveform.path.ecg"
        case .processes: "list.bullet"
        case .docker: "shippingbox.fill"
        case .localServices: "network"
        case .tokens: "chart.bar.fill"
        case .sessions: "text.bubble.fill"
        case .settings: "gearshape"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "即時掌握效能、電源與容器狀態"
        case .processes: "查看程序 CPU 與記憶體用量"
        case .docker: "唯讀查看 Docker 容器狀態"
        case .localServices: "查看 TCP 監聽服務、連接埠與程序來源"
        default: ""
        }
    }

    static let local: [Self] = [.overview, .processes, .docker, .localServices]
    static let monitoring: [Self] = local + [.tokens, .sessions]
}

@MainActor @Observable
final class MainWindowNavigation {
    var page = MainWindowPage.overview
    let settings = SettingsNavigation()
}

/// Owns the single production window for monitoring and settings.
@MainActor
public final class MainWindowController {
    private let host: HostedWindowController
    private let navigation = MainWindowNavigation()
    private let store: UsageStore
    private let settingsPageIDs: Set<String>
    public var window: NSWindow? { host.window }
    public var selectedPage: MainWindowPage { navigation.page }
    public var selectedSettingsPageID: String { navigation.settings.pageID }

    public init(settings: SettingsStore, store: UsageStore, demo: Bool = false,
                localContent: @escaping (MainWindowPage) -> AnyView,
                additionalSettingsPages: [DesktopSettingsPage] = [],
                experimentalSettings: [DesktopSettingsSection] = []) {
        self.store = store
        settingsPageIDs = Set(SettingsTab.allCases.map(\.id) + additionalSettingsPages.map(\.id))
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1100, height: 800)
        host = HostedWindowController(size: CGSize(width: min(1060, screen.width - 32), height: min(800, screen.height - 32)),
                                      title: "Agent Monitor", resizable: true)
        host.window?.minSize = CGSize(width: min(880, screen.width - 32), height: min(560, screen.height - 32))
        host.window?.isMovableByWindowBackground = false
        let clientSetup = demo ? MCPClientSetup(environment: .init(
            executable: nil, locate: { _ in nil }, hasServer: { _ in false },
            run: { _, _ in MCPCommandResult(status: nil, output: "Demo mode") }, copy: { _ in }
        )) : nil
        host.setContent(MainWindowView(settings: settings, store: store, navigation: navigation,
                                       sourceStatuses: demo ? DemoData.sources : nil, clientSetup: clientSetup,
                                       localContent: localContent, additionalSettingsPages: additionalSettingsPages,
                                       experimentalSettings: experimentalSettings))
        host.refreshLook()
    }

    public func show(_ page: MainWindowPage = .overview, settingsPageID: String? = nil) {
        navigation.page = page
        if page == .tokens { store.statsTab = .tokens }
        if page == .sessions { store.statsTab = .sessions }
        if let settingsPageID, settingsPageIDs.contains(settingsPageID) { navigation.settings.pageID = settingsPageID }
        host.show()
    }

    public func hide() { host.window?.orderOut(nil) }
}

private struct MainWindowView: View {
    let settings: SettingsStore
    let store: UsageStore
    @Bindable var navigation: MainWindowNavigation
    let sourceStatuses: [SourceStatus]?
    let clientSetup: MCPClientSetup?
    let localContent: (MainWindowPage) -> AnyView
    let additionalSettingsPages: [DesktopSettingsPage]
    let experimentalSettings: [DesktopSettingsSection]
    @Environment(\.colorScheme) private var scheme
    @Environment(WindowSurface.self) private var surface: WindowSurface?

    var body: some View {
        let theme = Theme.forScheme(scheme).under(surface?.look)
        HStack(spacing: 0) {
            sidebar(theme).frame(width: 196)
                .overlay(alignment: .trailing) { Rectangle().fill(theme.sidebarBorder).frame(width: 1) }
            ZStack {
                ForEach(MainWindowPage.local, id: \.rawValue) { page in
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(page.title).font(.ui(24, .semibold))
                            Text(page.subtitle).font(.ui(12)).foregroundStyle(theme.secondary)
                        }.padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 20)
                        localContent(page)
                            .padding(.horizontal, page == .localServices ? 20 : 0)
                            .padding(.bottom, page == .localServices ? 16 : 0)
                    }.mainPageVisible(navigation.page == page)
                }
                StatsView(store: store, embedded: true)
                    .mainPageVisible(navigation.page == .tokens || navigation.page == .sessions)
                SettingsView(settings: settings, store: store, navigation: navigation.settings, embedded: true,
                             additionalPages: additionalSettingsPages, experimentalSections: experimentalSettings,
                             clientSetup: clientSetup, sourceStatuses: sourceStatuses)
                    .mainPageVisible(navigation.page == .settings)
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .background(WindowGround(color: theme.windowBackground))
        }
        .foregroundStyle(theme.text).font(.ui(13)).tint(.accentColor)
    }

    private func sidebar(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Agent Monitor").font(.ui(12, .semibold))
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                        .font(.ui(10)).foregroundStyle(theme.secondary)
                }
            }.padding(.horizontal, 9).padding(.top, 44).padding(.bottom, 20)
            ForEach(MainWindowPage.monitoring, id: \.rawValue) { page in
                Button {
                    navigation.page = page
                    if page == .tokens { store.statsTab = .tokens }
                    if page == .sessions { store.statsTab = .sessions }
                } label: { row(page, theme: theme) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("main-nav-\(page.rawValue)")
                .accessibilityAddTraits(navigation.page == page ? .isSelected : [])
            }
            Spacer(minLength: 12)
            Divider().padding(.horizontal, 8).padding(.bottom, 7)
            Button { navigation.page = .settings } label: {
                HStack(spacing: 11) {
                    SettingsArtwork().stroke(style: StrokeStyle(lineWidth: 22.0 / 12.0, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 22).padding(2).accessibilityHidden(true)
                    Text("設定").font(.ui(13, navigation.page == .settings ? .semibold : .regular))
                    Spacer(minLength: 0)
                }.padding(.horizontal, 9).padding(.vertical, 10)
                    .background(navigation.page == .settings ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(navigation.page == .settings ? .white : theme.sidebarText)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("main-settings")
                .accessibilityAddTraits(navigation.page == .settings ? .isSelected : [])
        }.padding(.horizontal, 10).padding(.bottom, 16)
            .frame(maxHeight: .infinity)
            .background(WindowGround(color: theme.sidebarBackground))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("main-sidebar")
    }

    private func row(_ page: MainWindowPage, theme: Theme) -> some View {
        let selected = navigation.page == page
        return HStack(spacing: 10) {
            Image(systemName: page.symbol).frame(width: 26, height: 26).foregroundStyle(selected ? .white : .accentColor)
            Text(page.title).font(.ui(13, selected ? .semibold : .regular)).lineLimit(1)
            Spacer(minLength: 0)
        }.padding(.horizontal, 8).padding(.vertical, 8)
            .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(selected ? .white : theme.sidebarText).contentShape(Rectangle())
    }
}

private extension View {
    func mainPageVisible(_ visible: Bool) -> some View {
        opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityElement(children: .contain)
            .accessibilityHidden(!visible)
            .disabled(!visible)
    }
}
