import SwiftUI
import AgentHUDDesktop
import LocalMonitorCore

struct DockerPreviewContent {
    let containers: [ContainerSample]
    let isUnavailable: Bool
    let isPaused: Bool
    let isStale: Bool
    var emptyMessage: String { isUnavailable ? "無法取得 Docker 服務" : "目前沒有 Docker 容器" }

    init(snapshot: MachineSnapshot, isRunning: Bool, isDemo: Bool, now: Date) {
        containers = snapshot.containers
        isUnavailable = !(snapshot.dockerStatus.hasPrefix("已連線") || isDemo)
        isPaused = !isRunning
        isStale = now.timeIntervalSince(snapshot.timestamp) > 15
    }
}

@MainActor
final class DockerPreviewHover: ObservableObject {
    @Published private(set) var isPresented = false
    private var anchorHovered = false
    private var previewHovered = false
    private var keyboardOpened = false
    private var pending: Task<Void, Never>?
    private let openDelay: Duration
    private let closeDelay: Duration

    init(openDelay: Duration = .milliseconds(200), closeDelay: Duration = .milliseconds(300)) {
        self.openDelay = openDelay
        self.closeDelay = closeDelay
    }

    func anchorChanged(_ inside: Bool) { anchorHovered = inside; update() }
    func previewChanged(_ inside: Bool) { previewHovered = inside; update() }
    func openForAccessibility() {
        pending?.cancel()
        keyboardOpened = true
        isPresented = true
    }
    func cancel() {
        pending?.cancel()
        pending = nil
        anchorHovered = false
        previewHovered = false
        keyboardOpened = false
        isPresented = false
    }
    private func update() {
        pending?.cancel()
        guard !keyboardOpened else { return }
        let show = anchorHovered || previewHovered
        guard show != isPresented else { return }
        let delay = show ? openDelay : closeDelay
        pending = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.isPresented = show
        }
    }
    deinit { pending?.cancel() }
}

struct DockerServicePreview: View {
    @Environment(\.monitorOpaquePreview) private var opaquePreview
    let snapshot: MachineSnapshot
    let isRunning: Bool
    let isDemo: Bool
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        DesktopHUDPreviewSurface(forceOpaque: opaquePreview == true) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let content = DockerPreviewContent(snapshot: snapshot, isRunning: isRunning, isDemo: isDemo, now: context.date)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Docker 服務", systemImage: "shippingbox").font(.headline)
                        Spacer()
                        Button(action: onClose) { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("關閉 Docker 服務預覽")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.dockerStatus)
                        if isDemo { Text("展示資料") }
                        if content.isPaused { Text("取樣已暫停，顯示最後快照") }
                        if content.isStale { Text("快照已過期，資料可能已變更") }
                        Text("快照時間 \(snapshot.timestamp.formatted(date: .omitted, time: .standard))")
                        Text("容器每 10 秒更新")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if content.containers.isEmpty {
                        Text(content.emptyMessage).font(.subheadline).padding(.vertical, 16)
                    } else {
                        if content.isUnavailable { Text("以下為最後取得的容器資料").font(.caption).foregroundStyle(.secondary) }
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(content.containers) { container in
                                    GlassCard {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(container.name).font(.system(size: 12, weight: .semibold))
                                            Text(container.image).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                            Text("\(container.state) · \(container.status)").font(.caption).foregroundStyle(.secondary)
                                        }
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityElement(children: .combine)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 240)
                    }
                    Button("開啟本機監測詳細資料", action: onOpen).buttonStyle(GlassButtonStyle())
                }
                .padding(16).frame(width: 360, alignment: .leading)

            }
        }
        .onExitCommand(perform: onClose)
        .accessibilityIdentifier("docker-service-preview")
    }
}
