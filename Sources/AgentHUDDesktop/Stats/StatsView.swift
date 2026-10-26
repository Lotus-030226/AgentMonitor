// Modified by Lotus for Agent Monitor. See docs/UPSTREAM.md.
import AppKit
import SwiftUI
import AgentHUDCore

/// Usage statistics that fill the available window width, on two pages: token charts, and sessions.
struct StatsView: View {
    let store: UsageStore
    var embedded = false
    var scrollable = true
    var onIdealHeightChange: ((CGFloat) -> Void)?
    @Environment(\.colorScheme) private var scheme
    @Environment(WindowSurface.self) private var surface: WindowSurface?
    @State private var sessionSource: SessionSource?
    @State private var sessionProject: SessionProject?
    @State private var sessionSearch: String

    init(store: UsageStore, scrollable: Bool = true, onIdealHeightChange: ((CGFloat) -> Void)? = nil,
         project: SessionProject? = nil, search: String = "", embedded: Bool = false) {
        self.embedded = embedded
        self.store = store
        self.scrollable = scrollable
        self.onIdealHeightChange = onIdealHeightChange
        _sessionProject = State(initialValue: project)
        _sessionSearch = State(initialValue: search)
    }

    var body: some View {
        let theme = Theme.forScheme(scheme).under(surface?.look)
        HStack(spacing: 0) {
            if !embedded { SettingsSidebar(selection: Binding(get: { store.statsTab == .tokens ? "tokens" : "sessions" },
                                               set: { store.statsTab = $0 == "tokens" ? .tokens : .sessions }),
                            additionalPages: navigationPages, theme: theme, includesBuiltInPages: false,
                            caption: L10n.text("用量统计", "Usage statistics"), identifierPrefix: "stats-tab")
                .frame(width: SettingsWindowLayout.sidebarWidth)
                .overlay(alignment: .trailing) { Rectangle().fill(theme.sidebarBorder).frame(width: 1) }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("stats-tab")
            }
            VStack(spacing: 0) {
            header(theme)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: StatsIdealHeightKey.self, value: proxy.size.height)
                })
            if scrollable {
                ScrollViewReader { proxy in
                    ScrollView { content(theme) }
                        .onChange(of: store.selectedQuotaId, initial: true) { _, id in
                            guard let id, let vendor = store.tokenCardVendors(for: id).first else { return }
                            withAnimation { proxy.scrollTo(AgentCards.anchor(vendor), anchor: .center) }
                            // The tile is pointed out for a moment; it keeps showing the window afterwards.
                            Task {
                                try? await Task.sleep(for: .seconds(2.5))
                                if store.selectedQuotaId == id { withAnimation { store.selectedQuotaId = nil } }
                            }
                        }
                        .onChange(of: store.focusedSessionID) { _, _ in proxy.scrollTo(Self.top, anchor: .top) }
                        // A quota window being pointed out scrolls to its tile instead.
                        .onChange(of: store.statsTab) { _, _ in
                            if store.selectedQuotaId == nil { proxy.scrollTo(Self.top, anchor: .top) }
                        }
                }
            } else {
                content(theme)
            }
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .background {
                if !embedded { WindowGround(color: theme.windowBackground) }
            }
        }
        .foregroundStyle(theme.text)
        .font(.ui(13))
        .id(store.settings.settings.language)
        .onPreferenceChange(StatsIdealHeightKey.self) { height in
            onIdealHeightChange?(height)
        }
    }

    private static let top = "stats-top"

    private func content(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Color.clear.frame(height: 0).id(Self.top)
            if let error = store.lastError {
                Text(L10n.text("刷新失败：", "Refresh failed: ") + error)
                    .font(.ui(12)).foregroundStyle(theme.secondary)
                    .textSelection(.enabled)
            }
            switch store.statsTab {
            case .tokens:
                tokens(theme)
            case .sessions:
                if let session = store.focusedSession {
                    SessionDetailView(session: session, store: store, theme: theme)
                        .id(session.id)
                } else {
                    SessionList(store: store, theme: theme, source: sessionSource,
                                project: sessionProject, search: sessionSearch)
                }
            }
        }
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 32, trailing: 20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: StatsIdealHeightKey.self, value: proxy.size.height)
        })
    }

    @ViewBuilder
    private func tokens(_ theme: Theme) -> some View {
        UsageChartsCard(store: store, theme: theme)
        AgentCards(store: store, theme: theme)
        UsagePeriodsCard(store: store, theme: theme)
        HeatmapCard(grid: store.statsActivity, consumers: store.consumers, theme: theme)
    }

    private var navigationPages: [DesktopSettingsPage] {
        [StatsTab.tokens, .sessions].map { tab in
            DesktopSettingsPage(id: tab == .tokens ? "tokens" : "sessions", title: { tab.label },
                                subtitle: { "" }, symbol: tab == .tokens ? "chart.bar.fill" : "text.bubble.fill",
                                color: .accentColor) { EmptyView() }
        }
    }

    private func header(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(store.statsTab.label).font(.ui(24, .semibold))
                Text(store.statsTab == .tokens
                     ? L10n.text("查看用量、趋势与活动。", "Review usage, trends and activity.")
                     : L10n.text("查看会话与执行状态。", "Review sessions and execution status."))
                    .font(.ui(12)).foregroundStyle(theme.secondary)
            }
            .padding(.top, 24).padding(.bottom, 20)
            VStack(spacing: 12) {
                controls(theme).frame(height: 28)
                if store.statsTab == .sessions && store.focusedSession == nil { sessionFilters(theme) }
            }.padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
    }

    private func controls(_ theme: Theme) -> some View {
        HStack(spacing: 12) {
            switch store.statsTab {
            case .tokens:
                dimensions
                Spacer(minLength: 12)
                if store.statsRange.bucketSizes.count > 1 {
                    SegmentedPills(
                        options: store.statsRange.bucketSizes.map { SegmentOption(value: $0, label: $0.label) },
                        selection: Binding(get: { store.tokenBucketSize }, set: { store.tokenBucketSize = $0 }),
                        theme: theme
                    )
                }
                SegmentedPills(
                    options: StatsRange.allCases.map { SegmentOption(value: $0, label: $0.label) },
                    selection: Binding(get: { store.statsRange }, set: { store.setStatsRange($0) }),
                    theme: theme
                )
            case .sessions where store.focusedSession != nil:
                let parent = store.focusedSessionParent
                Button {
                    store.focusedSessionID = parent?.id
                } label: {
                    Label(parent.map { $0.agentName ?? $0.task } ?? L10n.text("全部会话", "All sessions"), systemImage: "chevron.left")
                        .lineLimit(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.ui(12, .semibold))
                .keyboardShortcut("[", modifiers: .command)
                .help(parent == nil ? L10n.text("回到会话列表", "Back to the session list") : L10n.text("回到上级 agent", "Back to the parent agent"))
                .accessibilityIdentifier("session-list-back")
                Spacer(minLength: 12)
            case .sessions:
                Spacer(minLength: 12)
                sessionCount(theme)
                SelectionMenu(
                    title: L10n.text("会话来源", "Session source"),
                    options: [SegmentOption(value: Optional<SessionSource>.none, label: L10n.text("全部来源", "All sources"))]
                        + sessionSources.map { SegmentOption(value: Optional($0), label: $0.name) },
                    selection: $sessionSource,
                    theme: theme,
                    width: 185
                )
                .accessibilityIdentifier("session-source-filter")
            }
        }
    }

    private var sessionSources: [SessionSource] {
        Array(Set(store.runningSessions().map(store.sessionSource))).sorted {
            if $0.vendor != $1.vendor { return ($0.vendor ?? "") < ($1.vendor ?? "") }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Local list filters leave the token charts' range and dimensions alone and survive opening a session's page.
    private func sessionFilters(_ theme: Theme) -> some View {
        HStack(spacing: 12) {
            SelectionMenu(
                title: L10n.text("项目路径", "Project path"),
                options: [SegmentOption(value: Optional<SessionProject>.none, label: L10n.text("全部项目", "All projects"))]
                    + sessionProjects.map { SegmentOption(value: Optional($0), label: $0.label) },
                selection: $sessionProject,
                theme: theme,
                width: 260
            )
            .help(sessionProject?.label ?? L10n.text("按项目筛选，同一仓库的工作树归为一个项目", "Filter by project, including the repository's worktrees"))
            .accessibilityIdentifier("session-project-filter")
            SessionSearchField(text: $sessionSearch)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("session-search")
        }
        .frame(height: 24)
    }

    private var sessionProjects: [SessionProject] {
        var projects = Set(store.runningSessions().map(SessionProject.init))
        if let sessionProject { projects.insert(sessionProject) }
        return SessionProject.ordered(projects)
    }

    private func sessionCount(_ theme: Theme) -> some View {
        let counts = Self.sessionCounts(store, source: sessionSource, activeOnly: true,
                                        project: sessionProject, search: sessionSearch)
        let running = counts.running
        return HStack(spacing: 6) {
            Circle().fill(running > 0 ? theme.status(.ok) : theme.tertiary).frame(width: 6, height: 6)
            Text(L10n.text("\(running) 个运行中", "\(running) running"))
        }
        .font(.ui(11))
        .foregroundStyle(theme.secondary)
    }

    /// How many sessions the list shows, and how many of them are running.
    static func sessionCounts(_ store: UsageStore, source: SessionSource?, activeOnly: Bool,
                              project: SessionProject? = nil, search: String = "") -> (listed: Int, running: Int) {
        let sessions = store.runningSessions(source: source, project: project, search: search), view = store.view
        return (sessions.count, sessions.filter { view.phase(of: $0).isInFlight }.count)
    }

    /// Which token kinds the charts count: what calls added, everything, or any kinds picked one by one.
    private var dimensions: some View {
        Menu {
            Toggle(L10n.text("不含缓存读取", "Excluding cache reads"), isOn: Binding(
                get: { store.tokenDimensions == .fresh }, set: { if $0 { store.tokenDimensions = .fresh } }))
            Toggle(L10n.text("全部 Token", "All tokens"), isOn: Binding(
                get: { store.tokenDimensions == .all }, set: { if $0 { store.tokenDimensions = .all } }))
            Divider()
            ForEach(TokenDimensions.choices, id: \.value) { choice in
                Toggle(choice.label, isOn: Binding(
                    get: { store.tokenDimensions.contains(choice.value) },
                    set: { selected in
                        if selected { store.tokenDimensions.insert(choice.value) }
                        // At least one kind stays counted.
                        else if store.tokenDimensions != choice.value { store.tokenDimensions.remove(choice.value) }
                    }))
            }
        } label: {
            Text("Token · " + store.tokenDimensions.label).font(.ui(12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(L10n.text("统计的 Token 种类", "Token kinds counted"))
    }

}

/// The same native search control as other Mac windows, with its clear button and immediate filtering.
private struct SessionSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(frame: .zero)
        field.controlSize = .small
        field.font = .systemFont(ofSize: 11)
        field.placeholderString = L10n.text("搜索会话或路径", "Search sessions or paths")
        field.setAccessibilityLabel(L10n.text("搜索会话", "Search sessions"))
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.search(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: 22)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SessionSearchField
        init(_ parent: SessionSearchField) { self.parent = parent }

        @objc func search(_ field: NSSearchField) {
            parent.text = field.stringValue
        }
    }
}

private struct StatsIdealHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

@MainActor
enum StatsWindowLayout {
    // User-selected portrait reference: height : width = 3 : 2.
    static let preferredSize = CGSize(width: 960, height: 1200)
    static let minimumWidth: CGFloat = 880
}

@MainActor
final class StatsWindowController: HostedWindowController {
    private var idealContentHeight: CGFloat = 0

    init(store: UsageStore) {
        let preferred = StatsWindowLayout.preferredSize
        let visible = NSScreen.main?.visibleFrame.height ?? preferred.height
        super.init(
            size: CGSize(width: preferred.width, height: min(preferred.height, visible - 24)),
            title: Self.title,
            resizable: true
        )
        window?.minSize = CGSize(width: StatsWindowLayout.minimumWidth, height: 480)
        setContent(StatsView(store: store, onIdealHeightChange: { [weak self] height in
            self?.idealContentHeight = height
            self?.fitHeightToContent()
        }))
    }

    private static var title: String { L10n.text("用量统计", "Usage statistics") }

    override func show() {
        window?.title = Self.title
        super.show()
        fitHeightToContent()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        fitHeightToContent()
    }

    override func windowDidChangeScreen(_ notification: Notification) {
        super.windowDidChangeScreen(notification)
        fitHeightToContent()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        fitHeightToContent()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        fitHeightToContent()
    }

    /// Keep the top edge stable and let the scroll view handle content taller than the screen.
    private func fitHeightToContent() {
        guard idealContentHeight > 0, let window,
              window.isVisible, !window.isMiniaturized,
              !window.inLiveResize, !window.styleMask.contains(.fullScreen),
              let screen = window.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame.insetBy(dx: 0, dy: 12)
        let chrome = window.frame.height - (window.contentView?.bounds.height ?? window.frame.height)
        let height = min(available.height, max(window.minSize.height, ceil(idealContentHeight + chrome)))
        var frame = window.frame
        frame.origin.y = max(available.minY, min(frame.maxY, available.maxY) - height)
        frame.size.height = height
        guard abs(frame.height - window.frame.height) > 1 || abs(frame.minY - window.frame.minY) > 1 else { return }
        window.setFrame(frame, display: true)
    }
}

private extension StatsTab {
    /// The page's name in the window's picker.
    var label: String {
        switch self {
        case .tokens: L10n.text("Token", "Tokens")
        case .sessions: L10n.text("会话", "Sessions")
        }
    }
}
