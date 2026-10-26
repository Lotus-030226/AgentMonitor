import SwiftUI
import AgentHUDDesktop
import LocalMonitorCore

public enum MonitorSection: String, CaseIterable {
    case overview = "總覽", processes = "程序", docker = "Docker"
}

public struct MonitorDetails: View {
    private let embedded: Bool
    @ObservedObject var store: LocalMonitorStore
    @State private var section: MonitorSection
    private let previewSnapshot: MachineSnapshot?
    private var snapshot: MachineSnapshot { previewSnapshot ?? store.snapshot }
    private var paused: Bool { !store.isRunning }
    @State private var refreshing = false
    @State private var cpuHistory: [Double] = []
    @State private var memoryHistory: [Double] = []
    @State private var sortByMemory = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(store: LocalMonitorStore, section: MonitorSection = .overview, previewSnapshot: MachineSnapshot? = nil, embedded: Bool = false) {
        self.embedded = embedded
        self.store = store
        self.previewSnapshot = previewSnapshot
        _section = State(initialValue: section)
        if store.isDemo && previewSnapshot == nil {
            _cpuHistory = State(initialValue: Self.demoHistory(memory: false))
            _memoryHistory = State(initialValue: Self.demoHistory(memory: true))
        }
    }
    private static func demoHistory(memory: Bool) -> [Double] {
        var values: [Double] = []
        for index in 0..<48 {
            let step = Double(index)
            if memory {
                let wave = sin(step * 0.14) * 4.0
                values.append(46.0 + wave + step * 0.08)
            } else {
                let slowWave = sin(step * 0.27) * 13.0
                let fastWave = cos(step * 0.71) * 4.0
                values.append(30.0 + slowWave + fastWave)
            }
        }
        return values
    }
    public var body: some View {
        Group {
        if embedded {
            VStack(spacing: 0) {
                toolbar.padding(.horizontal, 20).padding(.bottom, 16)
                ScrollView { pageContent.padding(.horizontal, 20).padding(.bottom, 24) }
                statusFooter.font(.caption).foregroundStyle(.secondary).padding(12)
            }
        } else { legacyLayout }
        }
        .onReceive(store.$snapshot) { snapshot in
            guard previewSnapshot == nil else { return }
            if let cpu = snapshot.cpuPercent { cpuHistory.append(cpu); cpuHistory = Array(cpuHistory.suffix(60)) }
            if let memory = MonitorFormat.ratio(snapshot.memoryUsedBytes, snapshot.memoryTotalBytes) {
                memoryHistory.append(memory); memoryHistory = Array(memoryHistory.suffix(60))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: section)
    }
    private var legacyLayout: some View {
        DesktopPageLayout(selection: Binding(get: { section.rawValue }, set: { value in
            if let next = MonitorSection(rawValue: value) { section = next }
        }), pages: pages, caption: "本機監測") {
            toolbar
        } footer: { statusFooter } content: { pageContent }
    }
    private var toolbar: some View {
        HStack(spacing: 10) {
                if store.isDemo { Text("展示資料").font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                Spacer()
                Button { if store.isRunning { store.stop() } else { store.start() } } label: {
                    Label(paused ? "繼續" : "暫停", systemImage: paused ? "play.fill" : "pause.fill")
                }.help("暫停時保留最後一筆資料")
                Button {
                    refreshing = true
                    Task { await store.refresh(); refreshing = false }
                } label: { Label(refreshing ? "更新中" : "更新", systemImage: "arrow.clockwise") }
                .disabled(refreshing).keyboardShortcut("r", modifiers: .command)
            }.controlSize(.small)
    }
    private var statusFooter: some View {
        HStack(spacing: 8) {
                Circle().fill(paused ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(paused ? "已暫停 · 保留最後取樣" : Date().timeIntervalSince(snapshot.timestamp) > 15 ? "資料較舊 · 等待新取樣" : "本機即時取樣")
                Spacer()
                Text(snapshot.timestamp, style: .time).monospacedDigit()
                Text("更新")
            }
    }
    @ViewBuilder private var pageContent: some View {
        switch section {
        case .overview: overview
        case .processes: processes
        case .docker: docker
        }
    }
    private var pages: [DesktopSettingsPage] {
        [page(.overview, symbol: "waveform.path.ecg", subtitle: "即時掌握效能、電源與容器狀態"),
         page(.processes, symbol: "list.bullet", subtitle: "查看程序 CPU 與記憶體用量"),
         page(.docker, symbol: "shippingbox.fill", subtitle: "唯讀查看 Docker 容器狀態")]
    }

    private func page(_ section: MonitorSection, symbol: String, subtitle: String) -> DesktopSettingsPage {
        DesktopSettingsPage(id: section.rawValue, title: { section.rawValue }, subtitle: { subtitle },
                            symbol: symbol, color: .accentColor) { EmptyView() }
    }
    private var memoryDetail: String {
        "估計用量 · 共 \(MonitorFormat.bytes(snapshot.memoryTotalBytes)) · \(snapshot.memoryPressure)"
    }
    private var overview: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                metric("CPU", symbol: "cpu", value: MonitorFormat.percent(snapshot.cpuPercent),
                       detail: memoryDetail, color: .cyan, history: cpuHistory, hidesDetail: true, valueColor: MonitorSeverity.cpu(snapshot.cpuPercent))
                    .accessibilityLabel("全系統 CPU 使用率 \(MonitorFormat.percent(snapshot.cpuPercent))")
                metric("記憶體", symbol: "memorychip", value: MonitorFormat.bytes(snapshot.memoryUsedBytes),
                       detail: memoryDetail, color: .indigo, history: memoryHistory, detailColor: MonitorSeverity.state(snapshot.memoryPressure))
            }.fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("儲存空間", systemImage: "internaldrive").foregroundStyle(.secondary).font(.subheadline)
                            .overviewFrame("disk.title")
                        Text(MonitorFormat.bytes(snapshot.diskUsedBytes)).font(.system(size: 27, weight: .medium)).monospacedDigit()
                            .accessibilityLabel("磁碟已用 \(MonitorFormat.bytes(snapshot.diskUsedBytes))")
                        if let ratio = MonitorFormat.ratio(snapshot.diskUsedBytes, snapshot.diskTotalBytes) {
                            ProgressView(value: ratio, total: 100).tint(.teal).accessibilityLabel("磁碟已用比例")
                        } else {
                            Text("使用率尚無資料").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text("共 \(MonitorFormat.bytes(snapshot.diskTotalBytes))").font(.caption).foregroundStyle(.secondary)
                            .overviewFrame("disk.footer")
                    }.frame(maxHeight: .infinity, alignment: .topLeading)
                }.overviewFrame("disk.card")
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("網路流量", systemImage: "network").foregroundStyle(.secondary).font(.subheadline)
                            .overviewFrame("network.title")
                        HStack { networkRate("下載", symbol: "arrow.down", value: snapshot.networkReceivedBytesPerSecond, color: .cyan)
                            Spacer(); networkRate("上傳", symbol: "arrow.up", value: snapshot.networkSentBytesPerSecond, color: .indigo) }
                        Spacer(minLength: 0)
                        Text("所有啟用介面 · 每秒傳輸量").font(.caption).foregroundStyle(.secondary)
                            .overviewFrame("network.footer")
                    }.frame(maxHeight: .infinity, alignment: .topLeading)
                }.overviewFrame("network.card")
            }.fixedSize(horizontal: false, vertical: true)
            GlassCard {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: snapshot.isCharging == true ? "battery.100percent.bolt" : "battery.100percent")
                            .font(.title2).foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("電源與電池").font(.subheadline.weight(.medium))
                            Text("\(snapshot.powerSource) · \(chargingStatus)")
                                .font(.caption).foregroundStyle(.secondary)
                            if snapshot.batteryPercent == nil {
                                Text("未偵測到電池，或此裝置未提供電池資訊。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(MonitorFormat.percent(snapshot.batteryPercent))
                            .font(.system(size: 25, weight: .medium)).monospacedDigit()
                    }
                    SettingsDivider()
                    HStack(spacing: 12) {
                        Label("系統散熱狀態", systemImage: "thermometer.medium")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(snapshot.thermalState).font(.subheadline)
                            .foregroundStyle(MonitorSeverity.state(snapshot.thermalState))
                    }
                }
            }
            if snapshot.cpuPercent == nil || snapshot.networkReceivedBytesPerSecond == nil {
                note("第一筆取樣需要計算時間差；尚未取得的數值顯示為 —。", symbol: "clock")
            }
            ForEach(Array(snapshot.notices.enumerated()), id: \.offset) { _, notice in note(notice, symbol: "info.circle") }
        }
    }
    private var chargingStatus: String {
        switch snapshot.isCharging {
        case true: "充電中"
        case false: "未充電"
        case nil: "充電狀態未知"
        }
    }

    private func metric(_ title: String, symbol: String, value: String, detail: String, color: Color, history: [Double], hidesDetail: Bool = false, valueColor: Color = .primary, detailColor: Color = .secondary) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
                    .overviewFrame("\(title).title")
                Text(value).font(.system(size: 36, weight: .medium)).foregroundStyle(valueColor).monospacedDigit().contentTransition(.numericText())
                    .overviewFrame("\(title).value")
                Text(detail).font(.caption).foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(hidesDetail ? 0 : 1).accessibilityHidden(hidesDetail)
                    .overviewFrame("\(title).detail")
                Spacer(minLength: 0)
                Sparkline(values: history, color: color).frame(height: 50)
                    .overviewFrame("\(title).chart")
                HStack { Text("最近 \(history.count) 次取樣"); Spacer(); Text("0–100%") }.font(.system(size: 10)).foregroundStyle(.tertiary)
                    .overviewFrame("\(title).footer")
            }.frame(maxHeight: .infinity, alignment: .topLeading)
        }.overviewFrame("\(title).card")
    }
    private func networkRate(_ title: String, symbol: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(color)
            Text(MonitorFormat.rate(value)).font(.system(size: 20, weight: .medium)).monospacedDigit()
        }
    }
    private var processes: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text("程序資源").font(.title3.weight(.semibold)); Text("CPU 以單核心為 100%，多核心程序可超過 100%。").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Picker("排序", selection: $sortByMemory) { Text("CPU 優先").tag(false); Text("記憶體優先").tag(true) }.frame(width: 160)
            }
            GlassCard {
                VStack(spacing: 0) {
                    HStack { Text("程序 / PID"); Spacer(); Text("CPU").frame(width: 90, alignment: .trailing); Text("記憶體").frame(width: 110, alignment: .trailing) }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
                    if snapshot.processes.isEmpty { empty("尚無程序資料", detail: "等待下一次取樣，或檢查系統存取權限。", symbol: "app.dashed") }
                    ForEach(snapshot.processes.sorted { sortByMemory ? $0.memoryBytes > $1.memoryBytes : $0.cpuPercent > $1.cpuPercent }) { process in
                        Divider().opacity(0.4)
                        HStack {
                            Image(systemName: "app").foregroundStyle(.secondary).frame(width: 23)
                            Text(process.name).lineLimit(1).truncationMode(.middle)
                            Text(String(process.id)).font(.caption.monospaced()).foregroundStyle(.tertiary)
                            Spacer()
                            Text(MonitorFormat.percent(process.cpuPercent)).monospacedDigit().frame(width: 90, alignment: .trailing)
                            Text(MonitorFormat.bytes(process.memoryBytes)).monospacedDigit().frame(width: 110, alignment: .trailing)
                        }.font(.subheadline).padding(.vertical, 10).accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
    private var docker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Docker 容器").font(.title3.weight(.semibold)); Spacer(); Label(snapshot.dockerStatus, systemImage: "shippingbox").font(.subheadline).foregroundStyle(.secondary) }
            if snapshot.containers.isEmpty {
                GlassCard { empty("目前沒有容器資料", detail: "\(snapshot.dockerStatus)。此處僅讀取狀態，不會啟動或停止 Docker。", symbol: "shippingbox") }
            }
            ForEach(snapshot.containers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { container in
                GlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox").font(.title2).foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 6) { Text(container.name).font(.headline); Text(container.image).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) { Text(container.state).font(.subheadline.weight(.medium)); Text(container.status).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
    private func note(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
    }
    private func empty(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 12) { Image(systemName: symbol).font(.system(size: 35, weight: .light)).foregroundStyle(.secondary); Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(.vertical, 42)
    }
}

/// Shows local metrics inside the expanded Agent HUD.
public struct LocalMonitorHUDSummary: View {
    @ObservedObject private var store: LocalMonitorStore
    @StateObject private var dockerHover = DockerPreviewHover()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.desktopHUDPreviewPresented) private var previewPresented
    private let onOpen: () -> Void
    private let previewSnapshot: MachineSnapshot?
    private var snapshot: MachineSnapshot { previewSnapshot ?? store.snapshot }

    public init(store: LocalMonitorStore, onOpen: @escaping () -> Void) {
        self.store = store
        self.onOpen = onOpen
        self.previewSnapshot = nil
    }

    init(store: LocalMonitorStore, previewSnapshot: MachineSnapshot, onOpen: @escaping () -> Void) {
        self.store = store
        self.onOpen = onOpen
        self.previewSnapshot = previewSnapshot
    }

    public var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label("本機監測", systemImage: "waveform.path.ecg")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    if store.isDemo { Text("展示資料").foregroundStyle(.orange) }
                    if !store.isRunning { Text("已暫停").foregroundStyle(.orange) }
                    Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                }.font(.system(size: 11))
                HUDMetricGrid {
                    metric("CPU", symbol: "cpu", value: MonitorFormat.percent(snapshot.cpuPercent),
                           detail: "", color: cpuWarning(snapshot.cpuPercent))
                    metric("記憶體", symbol: "memorychip", value: MonitorFormat.bytes(snapshot.memoryUsedBytes),
                           detail: "共 \(MonitorFormat.bytes(snapshot.memoryTotalBytes)) · \(known(snapshot.memoryPressure))",
                           color: stateWarning(snapshot.memoryPressure))
                    metric("網路", symbol: "network", value: "↓ \(MonitorFormat.rate(snapshot.networkReceivedBytesPerSecond))",
                           detail: "↑ \(MonitorFormat.rate(snapshot.networkSentBytesPerSecond))")
                    metric("儲存空間", symbol: "internaldrive", value: MonitorFormat.bytes(snapshot.diskUsedBytes),
                           detail: "共 \(MonitorFormat.bytes(snapshot.diskTotalBytes))")
                    metric("電源", symbol: snapshot.isCharging == true ? "battery.100percent.bolt" : "battery.100percent",
                           value: MonitorFormat.percent(snapshot.batteryPercent), detail: powerDetail)
                    metric("系統散熱狀態", symbol: "thermometer.medium", value: known(snapshot.thermalState),
                           detail: "", color: stateWarning(snapshot.thermalState))
                    metric("Docker", symbol: "shippingbox", value: dockerCount, detail: dockerState)
                        .contentShape(Rectangle())
                        .onHover(perform: dockerHover.anchorChanged)
                        .popover(isPresented: Binding(get: { dockerHover.isPresented }, set: { if !$0 { dockerHover.cancel() } }),
                                 arrowEdge: .bottom) {
                            DockerServicePreview(snapshot: snapshot, isRunning: store.isRunning, isDemo: store.isDemo,
                                                 onOpen: { dockerHover.cancel(); onOpen() }, onClose: dockerHover.cancel)
                                .environment(\.colorScheme, colorScheme)
                                .onHover(perform: dockerHover.previewChanged)
                        }
                    metric("已列程序", symbol: "list.bullet", value: snapshot.processes.isEmpty ? "—" : "\(snapshot.processes.count)",
                           detail: "CPU / 記憶體前列")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.09), lineWidth: 0.5) }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help("開啟本機監測詳細資料。停留 Docker 或聚焦後按向下鍵預覽服務。Docker：\(snapshot.dockerStatus)")
        .accessibilityLabel("本機監測，開啟詳細資料")
        .accessibilityValue(accessibleMetrics)
        .accessibilityAction(named: "顯示 Docker 服務預覽", dockerHover.openForAccessibility)
        .onKeyPress(.downArrow) {
            dockerHover.openForAccessibility()
            return .handled
        }
        .onChange(of: dockerHover.isPresented) { _, presented in previewPresented(presented) }
        .onDisappear {
            let wasPresented = dockerHover.isPresented
            dockerHover.cancel()
            if wasPresented { previewPresented(false) }
        }
        .padding(.bottom, 10)
    }

    private var accessibleMetrics: String {
        var values = [
            "全系統 CPU 使用率 \(MonitorFormat.percent(snapshot.cpuPercent))",
            "記憶體 \(MonitorFormat.bytes(snapshot.memoryUsedBytes))，共 \(MonitorFormat.bytes(snapshot.memoryTotalBytes))，壓力 \(known(snapshot.memoryPressure))",
            "下載 \(MonitorFormat.rate(snapshot.networkReceivedBytesPerSecond))，上傳 \(MonitorFormat.rate(snapshot.networkSentBytesPerSecond))",
            "磁碟已用 \(MonitorFormat.bytes(snapshot.diskUsedBytes))，共 \(MonitorFormat.bytes(snapshot.diskTotalBytes))",
            "電池 \(MonitorFormat.percent(snapshot.batteryPercent))，\(powerDetail)",
            "系統散熱狀態 \(known(snapshot.thermalState))",
            "Docker \(snapshot.dockerStatus)，\(dockerCount)",
            "已列程序 \(snapshot.processes.isEmpty ? "—" : String(snapshot.processes.count))"
        ]
        if store.isDemo { values.append("展示資料") }
        if !store.isRunning { values.append("已暫停") }
        return values.joined(separator: "；")
    }

    private var powerDetail: String {
        let source = known(snapshot.powerSource)
        guard let charging = snapshot.isCharging else { return source }
        return charging ? "\(source)\n充電中" : source
    }
    private var dockerState: String {
        snapshot.dockerStatus.hasPrefix("無法取得") ? "無法取得" : snapshot.dockerStatus
    }
    private var dockerCount: String {
        let available = snapshot.dockerStatus.hasPrefix("已連線") || store.isDemo
        return available ? "\(snapshot.containers.count) 個容器" : "—"
    }
    private func cpuWarning(_ value: Double?) -> Color? {
        guard let value, value.isFinite else { return nil }
        if value >= 90 { return .red }
        if value >= 70 { return .orange }
        return nil
    }
    private func stateWarning(_ value: String) -> Color? {
        if value.contains("嚴重") || value.lowercased().contains("critical") { return .red }
        if value.contains("警告") || value.contains("偏高") || value.contains("溫暖") { return .orange }
        return nil
    }
    private func known(_ value: String) -> String { value == "無法取得" ? "—" : value }
    private func metric(_ title: String, symbol: String, value: String, detail: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: symbol).frame(width: 13)
                Text(title).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary).font(.system(size: 11))
            Group {
                if let color { Text(value).foregroundStyle(color) }
                else { Text(value) }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            if !detail.isEmpty {
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}


/// Fits equal columns and reserves the same height for each metric row.
private struct HUDMetricGrid: Layout {
    private let spacing: CGFloat = 12
    private let minimumWidth: CGFloat = 84

    private func columns(for width: CGFloat) -> Int {
        min(4, max(1, Int((width + spacing) / (minimumWidth + spacing))))
    }

    private func metrics(width: CGFloat, subviews: Subviews) -> (columns: Int, cellWidth: CGFloat, rowHeight: CGFloat) {
        let count = columns(for: width)
        let cellWidth = max(0, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }.max() ?? 0
        return (count, cellWidth, height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? (4 * minimumWidth + 3 * spacing))
        let grid = metrics(width: width, subviews: subviews)
        let rows = (subviews.count + grid.columns - 1) / grid.columns
        return CGSize(width: width, height: CGFloat(rows) * grid.rowHeight + CGFloat(max(0, rows - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let grid = metrics(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let origin = CGPoint(x: bounds.minX + CGFloat(index % grid.columns) * (grid.cellWidth + spacing),
                                 y: bounds.minY + CGFloat(index / grid.columns) * (grid.rowHeight + spacing))
            subview.place(at: origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: grid.cellWidth, height: nil))
        }
    }
}

// Geometry is observed without changing layout proposals or state.
struct OverviewFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private extension View {
    func overviewFrame(_ name: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: OverviewFramePreference.self,
                                   value: [name: proxy.frame(in: .global)])
        })
    }
}
