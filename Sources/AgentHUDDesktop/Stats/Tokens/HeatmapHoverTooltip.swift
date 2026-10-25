import AppKit
import SwiftUI

/// A child panel escapes the heatmap's clipped scroll view.
struct HeatmapHoverTooltip<Content: View>: NSViewRepresentable {
    let content: Content
    let identifier: String
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> HeatmapHoverAnchor {
        HeatmapHoverAnchor()
    }

    func updateNSView(_ view: HeatmapHoverAnchor, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.content = AnyView(content.hudLook(context.environment.hudLook))
        view.onHover = onHover
    }

    static func dismantleNSView(_ view: HeatmapHoverAnchor, coordinator: ()) {
        view.dismiss()
    }
}

final class HeatmapHoverAnchor: NSView {
    var content = AnyView(EmptyView())
    var onHover: (Bool) -> Void = { _ in }
    var mouseLocation: () -> CGPoint = { NSEvent.mouseLocation }
    private var area: NSTrackingArea?
    private var popup: OverlayPanel?
    private var timer: Timer?
    private var exitDeadline: Date?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) { show() }
    override func mouseExited(with event: NSEvent) {
        exitDeadline = Date().addingTimeInterval(0.25)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { dismiss() }
        super.viewWillMove(toWindow: newWindow)
    }

    func show() {
        guard let window, let root = window.contentView else { return }
        var viewport = window.convertToScreen(root.convert(root.bounds, to: nil))
        if let clip = enclosingScrollView?.contentView {
            viewport = viewport.intersection(window.convertToScreen(clip.convert(clip.bounds, to: nil)))
        }
        if let screen = window.screen {
            viewport = viewport.intersection(screen.visibleFrame)
        }
        viewport = viewport.insetBy(dx: 4, dy: 4)
        let cell = window.convertToScreen(convert(bounds.intersection(visibleRect), to: nil))
        guard !cell.isEmpty, viewport.intersects(cell), viewport.width > 0 else { dismiss(); return }
        let width = min(300, viewport.width)
        let measurement = NSHostingView(rootView: content.frame(width: width).fixedSize(horizontal: false, vertical: true))
        let naturalHeight = ceil(measurement.fittingSize.height)
        let below = max(0, cell.minY - viewport.minY - 8)
        let above = max(0, viewport.maxY - cell.maxY - 8)
        let opensBelow = naturalHeight <= below || (naturalHeight > above && below >= above)
        let height = min(naturalHeight, opensBelow ? below : above)
        guard height > 0 else { dismiss(); return }
        let x = max(viewport.minX, min(cell.midX - width / 2, viewport.maxX - width))
        let y = opensBelow ? cell.minY - 8 - height : cell.maxY + 8
        for sibling in window.childWindows ?? [] where sibling.title == "Heatmap model details" && sibling !== popup {
            window.removeChildWindow(sibling)
            sibling.orderOut(nil)
        }
        let panel = popup ?? OverlayPanel(frame: .zero, level: window.level, acceptsMouse: true)
        panel.title = "Heatmap model details"
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView:
            ScrollView(.vertical) { content.frame(width: width).fixedSize(horizontal: false, vertical: true) }
                .frame(width: width, height: height))
        panel.setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)
        if panel.parent !== window { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
        popup = panel
        exitDeadline = nil
        onHover(true)
        observeDismissal(in: window)
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 0.08, target: self, selector: #selector(checkPointer), userInfo: nil, repeats: true)
    }

    private func observeDismissal(in window: NSWindow) {
        let center = NotificationCenter.default
        center.removeObserver(self)
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            center.addObserver(self, selector: #selector(dismiss), name: name, object: window)
        }
        center.addObserver(self, selector: #selector(dismiss), name: NSApplication.didResignActiveNotification, object: nil)
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            center.addObserver(self, selector: #selector(dismiss), name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    @objc private func checkPointer() {
        guard let window, let popup, popup.parent === window, popup.isVisible else { dismiss(); return }
        let point = mouseLocation()
        let cell = window.convertToScreen(convert(bounds.intersection(visibleRect), to: nil))
        if cell.contains(point) || popup.frame.contains(point) { exitDeadline = nil; return }
        if let exitDeadline, Date() >= exitDeadline { dismiss() }
        else if exitDeadline == nil { exitDeadline = Date().addingTimeInterval(0.25) }
    }

    @objc func dismiss() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
        guard let panel = popup else { return }
        popup = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        onHover(false)
    }
}
