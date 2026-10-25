import SwiftUI

private enum DesktopHUDPreviewPresentedKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (Bool) -> Void = { _ in }
}

public extension EnvironmentValues {
    /// A transient preview keeps only its host HUD open.
    var desktopHUDPreviewPresented: @MainActor @Sendable (Bool) -> Void {
        get { self[DesktopHUDPreviewPresentedKey.self] }
        set { self[DesktopHUDPreviewPresentedKey.self] = newValue }
    }
}

/// Draws a preview with its host HUD's surface and text tokens.
public struct DesktopHUDPreviewSurface<Content: View>: View {
    @Environment(\.hudLook) private var look
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.drawsGlassStandIn) private var standIn
    private let forceOpaque: Bool
    private let content: Content

    public init(forceOpaque: Bool = false, @ViewBuilder content: () -> Content) {
        self.forceOpaque = forceOpaque
        self.content = content()
    }

    private var resolvedLook: HUDLook {
        guard forceOpaque || reduceTransparency else { return look }
        var opaque = look
        opaque.material = .solid
        opaque.transparency = 0
        return opaque
    }

    public var body: some View {
        let resolved = resolvedLook
        let shape = RoundedRectangle(cornerRadius: 12)
        content
            .foregroundStyle(resolved.theme.text)
            .background(HUDSurface(shape, look: resolved, fill: resolved.theme.raisedSurface, contact: nil)
                .environment(\.drawsRaisedBox, true))
            .overlay(shape.strokeBorder(resolved.outline(resolved.theme.cardBorder, standIn: standIn)))
            .hudLook(resolved)
            .preferredColorScheme(resolved.colorScheme)
    }
}
