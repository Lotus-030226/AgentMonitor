import AppKit
import SwiftUI
import AgentHUDDesktop

private enum MonitorOpaquePreviewKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var monitorOpaquePreview: Bool? {
        get { self[MonitorOpaquePreviewKey.self] }
        set { self[MonitorOpaquePreviewKey.self] = newValue }
    }
}

struct GlassBackdrop: View {
    @Environment(\.monitorOpaquePreview) private var opaquePreview
    var body: some View { DesktopWindowBackground(forceOpaque: opaquePreview == true) }
}

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading).settingsCard()
    }
}

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 11).padding(.vertical, 8)
            .background(.primary.opacity(configuration.isPressed ? 0.13 : 0.055), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { proxy in
            let points = values.enumerated().map { index, value in
                CGPoint(x: proxy.size.width * Double(index) / Double(max(values.count - 1, 1)),
                        y: proxy.size.height * (1 - min(max(value, 0), 100) / 100))
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                    points.forEach { path.addLine(to: $0) }
                    if let last = points.last { path.addLine(to: CGPoint(x: last.x, y: proxy.size.height)) }
                    path.closeSubpath()
                }.fill(LinearGradient(colors: [color.opacity(0.24), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }.stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }.accessibilityHidden(true)
    }
}

enum MonitorFormat {
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f%%", value)
    }
    static func bytes(_ value: UInt64?) -> String {
        value.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .binary) } ?? "—"
    }
    static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return bytes(UInt64(max(0, min(value, Double(Int64.max))))) + "/s"
    }
    static func ratio(_ used: UInt64?, _ total: UInt64?) -> Double? {
        guard let used, let total, total > 0 else { return nil }
        return Double(used) / Double(total) * 100
    }
}

enum MonitorSeverity {
    static func cpu(_ value: Double?) -> Color {
        guard let value, value.isFinite else { return .secondary }
        if value >= 90 { return .red }
        if value >= 70 { return .orange }
        return .primary
    }
    static func state(_ value: String) -> Color {
        if value.contains("嚴重") || value.lowercased().contains("critical") { return .red }
        if value.contains("警告") || value.contains("偏高") || value.contains("溫暖") { return .orange }
        return .secondary
    }
}
