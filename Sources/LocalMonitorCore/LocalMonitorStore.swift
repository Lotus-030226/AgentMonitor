import Foundation
import Combine
import Darwin
import IOKit.ps

@MainActor public final class LocalMonitorStore: ObservableObject {
    @Published public private(set) var snapshot: MachineSnapshot
    @Published public private(set) var servicesSnapshot: LocalServicesSnapshot
    @Published public private(set) var isRunning = false
    public let isDemo: Bool
    private let collector = MachineCollector()
    private let servicesCollector = LocalServicesCollector()
    private var servicesSampler: (@Sendable () async -> LocalServicesSnapshot)?
    private var loop: Task<Void, Never>?
    private var refreshing = false
    private var generation = 0
    public init(demo: Bool = false) {
        isDemo = demo; snapshot = demo ? .demo : .empty
        servicesSnapshot = demo ? .demo : .empty
    }
    init(demo: Bool, servicesSampler: @escaping @Sendable () async -> LocalServicesSnapshot) {
        isDemo = demo; snapshot = demo ? .demo : .empty
        servicesSnapshot = demo ? .demo : .empty
        self.servicesSampler = servicesSampler
    }
    public func start() {
        guard loop == nil else { return }
        isRunning = true
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
    }
    public func stop() { generation += 1; loop?.cancel(); loop = nil; isRunning = false }
    public func refresh(forceServices: Bool = false) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let token = generation
        let next = isDemo ? MachineSnapshot.demo : await collector.sample()
        guard !Task.isCancelled, token == generation else { return }
        snapshot = next
        let services: LocalServicesSnapshot
        if let servicesSampler { services = await servicesSampler() }
        else if isDemo { services = .demo }
        else { services = await servicesCollector.sample(force: forceServices) }
        guard !Task.isCancelled, token == generation else { return }
        servicesSnapshot = services
    }
    deinit { loop?.cancel() }
}

private actor MachineCollector {
    private var previousCPU: [UInt64]?
    private var previousNetwork: [String: (UInt64, UInt64)]?
    private var previousTime: Double?
    private var slowTime: Double?
    private var processes: [ProcessSample] = []
    private var containers: [ContainerSample] = []
    private var dockerStatus = "尚未取樣"
    func sample() -> MachineSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        var result = MachineSnapshot()
        if let cpu = cpuTicks() {
            result.cpuPercent = SampleMath.cpu(previous: previousCPU, current: cpu)
            previousCPU = cpu
        } else { previousCPU = nil }
        let memory = memoryUsage()
        result.memoryUsedBytes = memory.0; result.memoryTotalBytes = memory.1
        var pressure: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0) == 0 {
            result.memoryPressure = pressure == 1 ? "正常" : pressure == 2 ? "警告" : pressure == 4 ? "嚴重" : "無法取得"
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let total = (attrs[.systemSize] as? NSNumber)?.uint64Value,
           let free = (attrs[.systemFreeSize] as? NSNumber)?.uint64Value, total >= free {
            result.diskTotalBytes = total; result.diskUsedBytes = total - free
        }
        if let current = networkCounters() {
            if let previous = previousNetwork, let time = previousTime,
               previous.keys.sorted() == current.keys.sorted(), now > time {
                var received = 0.0; var sent = 0.0; var valid = true
                for (name, counters) in current {
                    guard let old = previous[name],
                          let rx = SampleMath.rate(previous: old.0, current: counters.0, elapsed: now - time),
                          let tx = SampleMath.rate(previous: old.1, current: counters.1, elapsed: now - time) else { valid = false; break }
                    received += rx; sent += tx
                }
                if valid { result.networkReceivedBytesPerSecond = received; result.networkSentBytesPerSecond = sent }
            }
            previousNetwork = current; previousTime = now
        } else { previousNetwork = nil; previousTime = nil }
        let power = battery()
        result.batteryPercent = power.0; result.isCharging = power.1; result.powerSource = power.2
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: result.thermalState = "正常"
        case .fair: result.thermalState = "溫暖"
        case .serious: result.thermalState = "偏高"
        case .critical: result.thermalState = "嚴重"
        @unknown default: result.thermalState = "無法取得"
        }
        if slowTime == nil || now - (slowTime ?? 0) >= 10 {
            let ps = BoundedCommand.run(path: "/bin/ps", args: ["-A", "-o", "pid=,pcpu=,rss=,comm="])
            processes = ps.map { MonitorPolicy.selectProcesses(MonitorParser.processes($0)) } ?? []
            let docker = readDocker()
            containers = docker.0; dockerStatus = docker.1
            slowTime = now
        }
        result.processes = processes; result.containers = containers; result.dockerStatus = dockerStatus
        result.notices = ["程序 CPU 以單一核心為 100%，多核心程序可超過 100%", "程序與容器每 10 秒更新；程序 CPU 為程序存續期間平均值", "列出 CPU 與記憶體各前 12 名程序；記憶體估算扣除檔案快取與可清除頁面"]
        if result.cpuPercent == nil { result.notices.append("CPU 與網路速率需要兩次有效取樣") }
        return result
    }
    private func cpuTicks() -> [UInt64]? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return nil }
        return [UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3)]
    }
    private func memoryUsage() -> (UInt64?, UInt64?) {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return (nil, ProcessInfo.processInfo.physicalMemory) }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return (nil, ProcessInfo.processInfo.physicalMemory) }
        let total = ProcessInfo.processInfo.physicalMemory
        let used = MonitorPolicy.memoryUsed(active: UInt64(info.active_count), inactive: UInt64(info.inactive_count),
            wired: UInt64(info.wire_count), compressed: UInt64(info.compressor_page_count),
            external: UInt64(info.external_page_count), purgeable: UInt64(info.purgeable_count),
            pageSize: UInt64(pageSize), total: total)
        return (used, total)
    }
    private func networkCounters() -> [String: (UInt64, UInt64)]? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var current = head
        var values: [String: (UInt64, UInt64)] = [:]
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            let item = entry.pointee
            guard let address = item.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                  item.ifa_flags & UInt32(IFF_LOOPBACK) == 0, item.ifa_flags & UInt32(IFF_UP) != 0,
                  let data = item.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            values[String(cString: item.ifa_name)] = (UInt64(data.pointee.ifi_ibytes), UInt64(data.pointee.ifi_obytes))
        }
        return values.isEmpty ? nil : values
    }
    private func battery() -> (Double?, Bool?, String) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, nil, "無法取得") }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
            let percent = current.flatMap { value in maximum.flatMap { $0 > 0 ? min(100, max(0, value / $0 * 100)) : nil } }
            let ac = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (percent, description[kIOPSIsChargingKey] as? Bool, ac ? "電源轉接器" : "電池")
        }
        return (nil, nil, "無內建電池")
    }
    private func readDocker() -> ([ContainerSample], String) {
        let binary = "/Applications/Docker.app/Contents/Resources/bin/docker"
        let resolved = URL(fileURLWithPath: binary).resolvingSymlinksInPath().path
        var binaryInfo = stat()
        guard resolved.hasPrefix("/Applications/Docker.app/Contents/"), lstat(resolved, &binaryInfo) == 0,
              binaryInfo.st_mode & S_IFMT == S_IFREG, MonitorPolicy.trustedOwner(binaryInfo.st_uid, current: getuid()),
              binaryInfo.st_mode & 0o022 == 0, access(resolved, X_OK) == 0 else { return ([], "無法取得：未找到可信任的 Docker Desktop") }
        let socket = NSHomeDirectory() + "/.docker/run/docker.sock"
        var socketInfo = stat()
        guard lstat(socket, &socketInfo) == 0, socketInfo.st_mode & S_IFMT == S_IFSOCK,
              socketInfo.st_uid == getuid() else { return ([], "無法取得：Docker Desktop socket 不存在或未通過驗證") }
        guard let output = BoundedCommand.run(path: resolved, args: ["--config", "/var/empty", "--host", "unix://" + socket,
                    "ps", "--all", "--no-trunc", "--format", "{{json .}}"]),
              let rows = try? MonitorParser.containers(output) else { return ([], "無法取得：Docker 未回應或資料無效") }
        return (rows, rows.isEmpty ? "已連線，沒有容器" : "已連線")
    }
}

enum BoundedCommand {
    enum Failure: Sendable, Equatable { case launch, timeout, outputLimit, read, cancelled, invalidEncoding }
    struct Result: Sendable {
        var stdout: String = ""
        var stderr: String = ""
        var exitCode: Int32? = nil
        var failure: Failure? = nil
    }
    static func run(path: String, args: [String]) -> String? {
        let result = capture(path: path, args: args)
        return result.failure == nil && result.exitCode == 0 ? result.stdout : nil
    }
    static func capture(path: String, args: [String]) -> Result {
        guard !Task.isCancelled else { return Result(failure: .cancelled) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = args
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C", "DOCKER_CONFIG": "/var/empty"]
        let output = Pipe(); let errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return Result(failure: .launch) }
        let handles = [output.fileHandleForReading, errors.fileHandleForReading]
        defer { handles.forEach { try? $0.close() } }
        handles.forEach { _ = fcntl($0.fileDescriptor, F_SETFL, O_NONBLOCK) }
        var data = [Data(), Data()]
        var ended = [false, false]
        var buffer = [UInt8](repeating: 0, count: 8192)
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var failure: Failure?
        while !ended.allSatisfy({ $0 }) {
            for index in handles.indices where !ended[index] {
                let count = read(handles[index].fileDescriptor, &buffer, buffer.count)
                if count > 0 { data[index].append(contentsOf: buffer.prefix(count)) }
                else if count == 0 { ended[index] = true }
                else if errno != EAGAIN && errno != EWOULDBLOCK { failure = .read }
            }
            if data.reduce(0, { $0 + $1.count }) > 1_048_576 { failure = .outputLimit }
            if Task.isCancelled { failure = .cancelled }
            if ProcessInfo.processInfo.systemUptime >= deadline { failure = .timeout }
            if failure != nil { break }
            if ended.allSatisfy({ $0 }) && !process.isRunning { break }
            // Pipes may close before the child exits. Keep the same deadline.
            if ended.allSatisfy({ $0 }) && process.isRunning { ended = [false, false] }
            usleep(10_000)
        }
        if failure != nil && process.isRunning {
            process.terminate(); usleep(20_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        guard let stdout = String(data: data[0], encoding: .utf8), let stderr = String(data: data[1], encoding: .utf8) else {
            return Result(exitCode: process.terminationStatus, failure: .invalidEncoding)
        }
        return Result(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus, failure: failure)
    }
}
