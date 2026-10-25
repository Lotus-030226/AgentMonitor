import Foundation

public struct ProcessSample: Codable, Sendable, Identifiable {
    public let id: Int32
    public let name: String
    /// One CPU core equals 100 percent. Multicore processes can exceed 100 percent.
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public init(id: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.id = id; self.name = name; self.cpuPercent = cpuPercent; self.memoryBytes = memoryBytes
    }
}
public struct ContainerSample: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let image: String
    public let state: String
    public let status: String
    public init(id: String, name: String, image: String, state: String, status: String) {
        self.id = id; self.name = name; self.image = image; self.state = state; self.status = status
    }
}
public struct MachineSnapshot: Codable, Sendable {
    public var timestamp: Date
    public var cpuPercent: Double?
    public var memoryUsedBytes: UInt64?
    public var memoryTotalBytes: UInt64?
    public var memoryPressure: String
    public var diskUsedBytes: UInt64?
    public var diskTotalBytes: UInt64?
    public var networkReceivedBytesPerSecond: Double?
    public var networkSentBytesPerSecond: Double?
    public var batteryPercent: Double?
    public var isCharging: Bool?
    public var powerSource: String
    public var thermalState: String
    public var processes: [ProcessSample]
    public var containers: [ContainerSample]
    public var dockerStatus: String
    public var notices: [String]
    public init(timestamp: Date = Date(), cpuPercent: Double? = nil, memoryUsedBytes: UInt64? = nil,
                memoryTotalBytes: UInt64? = nil, memoryPressure: String = "無法取得", diskUsedBytes: UInt64? = nil,
                diskTotalBytes: UInt64? = nil, networkReceivedBytesPerSecond: Double? = nil,
                networkSentBytesPerSecond: Double? = nil, batteryPercent: Double? = nil, isCharging: Bool? = nil,
                powerSource: String = "無法取得", thermalState: String = "無法取得", processes: [ProcessSample] = [],
                containers: [ContainerSample] = [], dockerStatus: String = "尚未取樣", notices: [String] = []) {
        self.timestamp = timestamp; self.cpuPercent = cpuPercent; self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes; self.memoryPressure = memoryPressure; self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes; self.networkReceivedBytesPerSecond = networkReceivedBytesPerSecond
        self.networkSentBytesPerSecond = networkSentBytesPerSecond; self.batteryPercent = batteryPercent
        self.isCharging = isCharging; self.powerSource = powerSource; self.thermalState = thermalState
        self.processes = processes; self.containers = containers; self.dockerStatus = dockerStatus; self.notices = notices
    }
    public static var empty: Self { Self() }
    public static var demo: Self {
        Self(cpuPercent: 32.4, memoryUsedBytes: 12 * 1_073_741_824, memoryTotalBytes: 24 * 1_073_741_824,
             memoryPressure: "正常", diskUsedBytes: 280 * 1_073_741_824, diskTotalBytes: 500 * 1_073_741_824,
             networkReceivedBytesPerSecond: 1_240_000, networkSentBytesPerSecond: 280_000,
             batteryPercent: 82, isCharging: true, powerSource: "電源轉接器", thermalState: "正常",
             processes: [.init(id: 123, name: "Xcode", cpuPercent: 142.5, memoryBytes: 2_400_000_000)],
             containers: [.init(id: "demo-web", name: "preview-web", image: "nginx:alpine", state: "running", status: "Up 2 hours")],
             dockerStatus: "示範資料", notices: ["目前顯示示範資料"])
    }
}

public enum SampleMath {
    public static func cpu(previous: [UInt64]?, current: [UInt64]) -> Double? {
        guard let previous, previous.count == 4, current.count == 4,
              zip(current, previous).allSatisfy({ $0 >= $1 }) else { return nil }
        let delta = zip(current, previous).map { Double($0 - $1) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return nil }
        return min(100, max(0, (total - delta[2]) / total * 100))
    }
    public static func rate(previous: UInt64?, current: UInt64, elapsed: Double) -> Double? {
        guard let previous, current >= previous, elapsed > 0, elapsed.isFinite else { return nil }
        return Double(current - previous) / elapsed
    }
}
public enum MonitorParser {
    public static func processes(_ text: String) -> [ProcessSample] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard fields.count == 4, let pid = Int32(fields[0]), pid > 0,
                  let cpu = Double(fields[1]), cpu.isFinite, cpu >= 0,
                  let rss = UInt64(fields[2]), rss <= UInt64.max / 1024 else { return nil }
            return ProcessSample(id: pid, name: String(fields[3]), cpuPercent: cpu, memoryBytes: rss * 1024)
        }.sorted { $0.cpuPercent == $1.cpuPercent ? $0.memoryBytes > $1.memoryBytes : $0.cpuPercent > $1.cpuPercent }
    }
    public static func containers(_ text: String) throws -> [ContainerSample] {
        struct Row: Decodable { let ID: String; let Names: String; let Image: String; let State: String; let Status: String }
        return try text.split(separator: "\n").map { line in
            let row = try JSONDecoder().decode(Row.self, from: Data(line.utf8))
            guard !row.ID.isEmpty else { throw CocoaError(.coderReadCorrupt) }
            return ContainerSample(id: row.ID, name: row.Names, image: row.Image, state: row.State, status: row.Status)
        }
    }
}

public enum MonitorPolicy {
    public static func trustedOwner(_ owner: UInt32, current: UInt32) -> Bool { owner == 0 || owner == current }
    /// Keep both CPU-intensive and memory-intensive processes.
    public static func selectProcesses(_ processes: [ProcessSample]) -> [ProcessSample] {
        let cpu = processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(12)
        let memory = processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(12)
        var seen: Set<Int32> = []
        return (Array(cpu) + Array(memory)).filter { seen.insert($0.id).inserted }
    }
    /// Exclude file-backed and purgeable pages from the resident memory estimate.
    public static func memoryUsed(active: UInt64, inactive: UInt64, wired: UInt64, compressed: UInt64,
                                  external: UInt64, purgeable: UInt64, pageSize: UInt64, total: UInt64) -> UInt64 {
        let resident = Double(active) + Double(inactive) + Double(wired) + Double(compressed)
        let reclaimable = Double(external) + Double(purgeable)
        let bytes = max(0, resident - reclaimable) * Double(pageSize)
        return bytes >= Double(total) ? total : UInt64(bytes)
    }
}
