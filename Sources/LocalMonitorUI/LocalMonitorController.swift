import AppKit
import SwiftUI
import LocalMonitorCore
import AgentHUDDesktop

@MainActor
public final class LocalMonitorController: NSObject, NSWindowDelegate {
    public var onShowDetails: (() -> Void)?
    private let store: LocalMonitorStore
    private var details: DesktopHostWindow?

    public init(store: LocalMonitorStore) {
        self.store = store
        super.init()
    }

    public func start() {
        store.start()
    }

    public func stop() {
        store.stop()
        details?.hide()
    }

    public func showDetails() {
        if let onShowDetails { onShowDetails(); return }
        _ = makeDetails()
        details?.show()
    }

    public func snapshot(into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let detailWindow = makeDetails()
        try writeSnapshot(of: detailWindow, to: directory.appendingPathComponent("local-monitor-details.png"))
        let integratedSummary = LocalMonitorHUDSummary(store: store, onOpen: {})
            .padding(16).frame(width: 432).background(GlassBackdrop())
        let summarySize = NSHostingView(rootView: integratedSummary).fittingSize
        try snapshotVariant(integratedSummary, name: "local-monitor-integrated-hud", directory: directory, size: summarySize)
        let darkParentSummary = LocalMonitorHUDSummary(store: store, onOpen: {})
            .foregroundStyle(.white).environment(\.colorScheme, .light)
            .padding(16).frame(width: 432).background(.black)
        try snapshotVariant(darkParentSummary, name: "local-monitor-integrated-hud-dark-parent", directory: directory,
                            size: NSHostingView(rootView: darkParentSummary).fittingSize)
        try snapshotVariant(MonitorDetails(store: store).environment(\.colorScheme, .light), name: "local-monitor-light", directory: directory)
        try snapshotVariant(MonitorDetails(store: store).environment(\.colorScheme, .dark), name: "local-monitor-dark", directory: directory)
        try snapshotVariant(MonitorDetails(store: store, section: .processes), name: "local-monitor-processes", directory: directory)
        try snapshotVariant(MonitorDetails(store: store, section: .docker), name: "local-monitor-docker", directory: directory)
        try snapshotVariant(MonitorDetails(store: store, previewSnapshot: .empty), name: "local-monitor-empty", directory: directory)
        try snapshotVariant(MonitorDetails(store: store).environment(\.monitorOpaquePreview, true), name: "local-monitor-opaque", directory: directory)

    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func makeDetails() -> NSWindow {
        if let window = details?.window { return window }
        let host = DesktopHostWindow(title: "本機監測") { MonitorDetails(store: store) }
        details = host
        return host.window!
    }

    private func snapshotVariant<Content: View>(_ content: Content, name: String, directory: URL, size: NSSize = NSSize(width: 960, height: 780)) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        try writeSnapshot(of: window, to: directory.appendingPathComponent(name + ".png"))
        window.close()
    }

    private func writeSnapshot(of window: NSWindow, to url: URL) throws {
        guard let view = window.contentView else { throw SnapshotError.missingView }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw SnapshotError.missingBitmap }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw SnapshotError.missingBitmap }
        try data.write(to: url, options: .atomic)
    }

    private enum SnapshotError: Error { case missingView, missingBitmap }
}
