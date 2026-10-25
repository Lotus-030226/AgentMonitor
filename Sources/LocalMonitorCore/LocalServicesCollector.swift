import Foundation

actor LocalServicesCollector {
    private var lastSample: Double?
    private var snapshot = LocalServicesSnapshot.empty
    func sample(now: Double = ProcessInfo.processInfo.systemUptime, force: Bool = false) -> LocalServicesSnapshot {
        guard !Task.isCancelled, force || LocalServicesPolling.shouldSample(last: lastSample, now: now) else { return snapshot }
        let at = Date()
        let result = BoundedCommand.capture(path: "/usr/sbin/lsof", args: ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcnt"])
        guard !Task.isCancelled else { return snapshot }
        lastSample = now
        snapshot = Self.reduce(result, previous: snapshot, at: at)
        guard !snapshot.isStale, !snapshot.services.isEmpty else { return snapshot }
        // Limit optional CWD reads to this sample's first 64 process identities.
        let pids = Array(Set(snapshot.services.map(\.pid))).sorted().prefix(64)
        let cwd = BoundedCommand.capture(path: "/usr/sbin/lsof", args: ["-nP", "-a", "-p", pids.map(String.init).joined(separator: ","), "-d", "cwd", "-Fpcfn"])
        guard !Task.isCancelled else { return snapshot }
        let directories = cwd.failure == nil && cwd.exitCode == 0
            ? LocalServicesParser.workingDirectories(cwd.stdout, services: snapshot.services) : [:]
        let rows = snapshot.services.map { row in
            var next = row; next.workingDirectory = directories[row.pid]; return next
        }
        snapshot = LocalServicesSnapshot(timestamp: snapshot.timestamp, services: rows, status: snapshot.status)
        return snapshot
    }
    static func reduce(_ result: BoundedCommand.Result, previous: LocalServicesSnapshot, at: Date) -> LocalServicesSnapshot {
        if let failure = result.failure {
            return .failed(previous: previous, status: failure == .timeout ? .timedOut : .unavailable, at: at)
        }
        let parsed = LocalServicesParser.listeners(result.stdout)
        let emptySuccess = result.exitCode == 1 && result.stdout.isEmpty && result.stderr.isEmpty
        guard result.exitCode == 0 || emptySuccess || !parsed.services.isEmpty else {
            return .failed(previous: previous, status: .unavailable, at: at)
        }
        let partial = !result.stderr.isEmpty || parsed.rejectedEndpoints > 0 || (!emptySuccess && result.exitCode != 0)
        // Invalid-only output is a failed read, not proof that listeners disappeared.
        if parsed.services.isEmpty && partial {
            return .failed(previous: previous, status: .partial, at: at)
        }
        return LocalServicesSnapshot(timestamp: at, services: parsed.services,
                                     status: partial ? .partial : parsed.services.isEmpty ? .empty : .available)
    }
}
