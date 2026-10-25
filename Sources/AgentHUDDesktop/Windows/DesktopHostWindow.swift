import AppKit
import SwiftUI
import AgentHUDCore

/// Hosts local pages through the same window pipeline as Settings and Statistics.
@MainActor
public final class DesktopHostWindow {
    private let controller: HostedWindowController
    public var window: NSWindow? { controller.window }

    public init<Content: View>(title: String, @ViewBuilder content: () -> Content) {
        controller = HostedWindowController(size: SettingsWindowLayout.size, title: title, resizable: true)
        controller.window?.minSize = SettingsWindowLayout.minimum
        controller.setContent(content())
        controller.refreshLook()
    }

    public func show() { controller.show() }
    public func hide() { controller.window?.orderOut(nil) }
}

/// Enables unified window appearance once. Later user changes remain effective.
@MainActor
public enum DesktopAppearanceMigration {
    static let key = "agentmonitor.unified-window-look.v1"

    public static func apply(settings: SettingsStore, defaults: UserDefaults, screens: [String: Bool]? = nil) {
        let displays = screens ?? Dictionary(uniqueKeysWithValues: NSScreen.screens.map {
            (ScreenIdentity.key(for: $0), ScreenIdentity.hasNotch($0))
        })
        let migrate = !defaults.bool(forKey: key)
        let missing = displays.filter { settings.settings.screens[$0.key] == nil }
        guard migrate || !missing.isEmpty else { return }
        settings.update { value in
            if migrate { value.appearanceFollowsScreen = true }
            for (id, hasNotch) in displays where value.screens[id] == nil {
                value.screens[id] = value.placement(on: id, hasNotch: hasNotch)
            }
            let targets = migrate ? Array(value.screens.keys) : Array(missing.keys)
            for id in targets {
                value.screens[id]?.material = .glass
                value.screens[id]?.glassStyle = .material
            }
        }
        if migrate { defaults.set(true, forKey: key) }
    }
}

/// Gives host surfaces the existing window ground, with an opaque accessibility fallback.
public struct DesktopWindowBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(WindowSurface.self) private var surface: WindowSurface?
    private let forceOpaque: Bool

    public init(forceOpaque: Bool = false) { self.forceOpaque = forceOpaque }

    public var body: some View {
        let theme = Theme.forScheme(scheme).under(surface?.look)
        if forceOpaque || reduceTransparency { Theme.forScheme(scheme).windowBackground }
        else { WindowGround(color: theme.windowBackground) }
    }
}

/// Uses Settings navigation, header, content width, and surface tokens for host pages.
public struct DesktopPageLayout<Content: View, Toolbar: View, Footer: View>: View {
    @Binding private var selection: String
    private let pages: [DesktopSettingsPage]
    private let caption: String
    private let content: Content
    private let toolbar: Toolbar
    private let footer: Footer
    @Environment(\.colorScheme) private var scheme
    @Environment(WindowSurface.self) private var surface: WindowSurface?

    public init(selection: Binding<String>, pages: [DesktopSettingsPage], caption: String,
                @ViewBuilder toolbar: () -> Toolbar, @ViewBuilder footer: () -> Footer,
                @ViewBuilder content: () -> Content) {
        _selection = selection
        self.pages = pages
        self.caption = caption
        self.toolbar = toolbar()
        self.footer = footer()
        self.content = content()
    }

    public var body: some View {
        let theme = Theme.forScheme(scheme).under(surface?.look)
        let page = pages.first { $0.id == selection }
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection, additionalPages: pages, theme: theme,
                            includesBuiltInPages: false, caption: caption)
                .frame(width: SettingsWindowLayout.sidebarWidth)
                .overlay(alignment: .trailing) { Rectangle().fill(theme.sidebarBorder).frame(width: 1) }
                .layoutPriority(1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(page?.title() ?? caption).font(.ui(24, .semibold))
                    Text(page?.subtitle() ?? "").font(.ui(12)).foregroundStyle(theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 20)
                toolbar.padding(.horizontal, 20).padding(.bottom, 16)
                ScrollView {
                    content.frame(maxWidth: page?.preferredContentWidth ?? 640, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20).padding(.bottom, 32)
                }.id(selection)
                footer.font(.ui(11)).foregroundStyle(theme.secondary)
                    .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .background(WindowGround(color: theme.windowBackground))
        }
        .foregroundStyle(theme.text).font(.ui(13)).tint(.accentColor)
        .frame(minWidth: SettingsWindowLayout.minimum.width, minHeight: SettingsWindowLayout.minimum.height)
    }
}
