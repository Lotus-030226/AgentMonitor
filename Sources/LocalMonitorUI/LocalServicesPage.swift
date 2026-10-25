import AppKit
import SwiftUI
import LocalMonitorCore
import AgentHUDDesktop

public struct LocalServicesPage: View {
    @ObservedObject private var store: LocalMonitorStore
    @State private var search = ""
    @State private var hidesProjectNames = true
    @State private var refreshing = false
    public init(store: LocalMonitorStore) { self.store = store }
    private var rows: [LocalServiceSample] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.servicesSnapshot.services.filter { row in
            query.isEmpty || "\(row.process) \(row.pid) \(row.address) \(row.port)".localizedCaseInsensitiveContains(query)
        }
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if store.isDemo { Text("展示資料").font(.caption).foregroundStyle(.orange) }
                Spacer()
                Button {
                    if store.isRunning { store.stop() } else { store.start() }
                } label: {
                    Label(store.isRunning ? "暫停" : "繼續", systemImage: store.isRunning ? "pause.fill" : "play.fill")
                }
                .accessibilityIdentifier("localServices.pauseResume")
                .help("暫停時保留最後一筆資料")
                Button {
                    refreshing = true
                    Task { await store.refresh(forceServices: true); refreshing = false }
                } label: {
                    Label(refreshing ? "更新中" : "更新", systemImage: "arrow.clockwise")
                }
                .disabled(refreshing)
                .accessibilityIdentifier("localServices.refresh")
                .keyboardShortcut("r", modifiers: .command)
            }.controlSize(.small)
            HStack {
                TextField("搜尋程序、PID、位址或埠號", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("localServices.search")
                Toggle("隱藏目錄名稱", isOn: $hidesProjectNames).toggleStyle(.checkbox).fixedSize()
                    .accessibilityIdentifier("localServices.hideProjectNames")
            }
            HStack(spacing: 8) {
                Image(systemName: store.servicesSnapshot.isStale ? "exclamationmark.triangle" : "network")
                Text(store.servicesSnapshot.status.description)
                if store.servicesSnapshot.isStale { Text("保留上次資料").foregroundStyle(.orange) }
                if !store.isRunning { Text("已暫停").foregroundStyle(.secondary) }
                Spacer()
                Text(store.servicesSnapshot.timestamp, style: .time).monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary)
            Text("僅讀取 TCP 監聽埠，每 10 秒更新；應用協定未知。選擇 HTTP 或 HTTPS 才會開啟瀏覽器。")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 10) {
                    if rows.isEmpty {
                        Text(search.isEmpty ? emptyMessage : "沒有符合搜尋的服務")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24).settingsCard()
                    }
                    ForEach(rows) { row in serviceRow(row) }
                }.padding(.bottom, 8)
            }
        }
    }
    private var emptyMessage: String {
        switch store.servicesSnapshot.status {
        case .empty: "沒有可讀取的 TCP 監聽埠"
        case .notSampled: "等待第一次取樣"
        default: "目前沒有可顯示的監聽埠資料"
        }
    }
    private func serviceRow(_ row: LocalServiceSample) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.process).font(.headline).lineLimit(1)
                Text(verbatim: "PID \(row.pid)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("以瀏覽器開啟…") {
                    Button("HTTP（自行選擇協定）") { open(row, scheme: .http) }
                    Button("HTTPS（自行選擇協定）") { open(row, scheme: .https) }
                }.menuStyle(.borderlessButton).fixedSize()
                    .disabled(row.url(scheme: .http) == nil)
                    .help(row.url(scheme: .http) == nil ? "未知位址類型，無法選擇正確的本機連線位址" : "自行選擇 HTTP 或 HTTPS；不會自動偵測協定")
            }
            Text(verbatim: "\(row.address.contains(":") ? "[\(row.address)]" : row.address):\(row.port)")
                .font(.system(.body, design: .monospaced)).textSelection(.enabled)
            HStack {
                Text(row.addressFamily.rawValue)
                Text("·")
                Text("協定：\(row.applicationProtocol)")
                Text("·")
                if let directory = row.workingDirectory {
                    Text(hidesProjectNames ? "工作目錄：已取得（已隱藏）" : "工作目錄：\(URL(fileURLWithPath: directory).lastPathComponent)")
                        .lineLimit(1)
                } else { Text("工作目錄：無法取得") }
            }.font(.caption).foregroundStyle(.secondary)
            if row.address == "*" && row.addressFamily == .unknown {
                Text("位址類型未知，無法建立本機網址。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).settingsCard()
    }
    private func open(_ row: LocalServiceSample, scheme: LocalServiceScheme) {
        guard let url = row.url(scheme: scheme) else { return }
        NSWorkspace.shared.open(url)
    }
}
