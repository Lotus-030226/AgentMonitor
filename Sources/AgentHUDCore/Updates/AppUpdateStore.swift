import Foundation
import Observation

@MainActor @Observable
public final class AppUpdateStore {
    public let currentVersion: String
    public private(set) var state: UpdateCheckState
    public private(set) var lastCheckedAt: Date?
    public var automaticChecksEnabled: Bool {
        didSet {
            defaults.set(automaticChecksEnabled, forKey: Self.enabledKey)
            if automaticChecksEnabled && scheduler != nil {
                Task { [weak self] in await self?.checkAutomatically() }
            }
        }
    }
    public var availableRelease: UpdateRelease? {
        if case .available(let release) = state { return release }
        return knownRelease
    }

    private var knownRelease: UpdateRelease?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let client: any UpdateReleaseClient
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var scheduler: Task<Void, Never>?
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    private static let enabledKey = "updates.automaticChecksEnabled"
    private static let checkedKey = "updates.lastCheckedAt"
    private static let releaseKey = "updates.availableRelease"

    public init(currentVersion: String, defaults: UserDefaults = .standard,
                client: any UpdateReleaseClient = GitHubUpdateClient(),
                now: @escaping @Sendable () -> Date = { Date() },
                initialState: UpdateCheckState = .idle) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.client = client
        self.now = now
        let cached = Self.cachedRelease(defaults: defaults, currentVersion: currentVersion)
        let restored = initialState == .idle ? cached : nil
        knownRelease = restored
        state = restored.map(UpdateCheckState.available) ?? initialState
        automaticChecksEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        lastCheckedAt = defaults.object(forKey: Self.checkedKey) as? Date
    }

    private static func cachedRelease(defaults: UserDefaults, currentVersion: String) -> UpdateRelease? {
        guard defaults.object(forKey: releaseKey) != nil else { return nil }
        guard let cache = defaults.dictionary(forKey: releaseKey) as? [String: String],
              let version = cache["version"], let page = cache["pageURL"], let download = cache["downloadURL"],
              let release = UpdateRelease.validated(version: version, pageURL: page, downloadURL: download),
              let available = StableUpdateVersion(version), let current = StableUpdateVersion(currentVersion),
              available > current else {
            defaults.removeObject(forKey: releaseKey)
            return nil
        }
        return release
    }

    private func remember(_ release: UpdateRelease?) {
        knownRelease = release
        guard let release else { defaults.removeObject(forKey: Self.releaseKey); return }
        defaults.set(["version": release.version, "pageURL": release.pageURL.absoluteString,
                      "downloadURL": release.downloadURL.absoluteString], forKey: Self.releaseKey)
    }

    deinit {
        scheduler?.cancel()
        requestTask?.cancel()
    }

    public func start() {
        guard scheduler == nil else { return }
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkAutomatically()
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
    }

    public func stop() {
        scheduler?.cancel()
        scheduler = nil
        requestID = nil
        requestTask?.cancel()
        requestTask = nil
        if state == .checking { state = knownRelease.map(UpdateCheckState.available) ?? .idle }
    }

    func checkAutomatically() async {
        guard automaticChecksEnabled else { return }
        if let lastCheckedAt {
            let elapsed = now().timeIntervalSince(lastCheckedAt)
            if elapsed >= 0 && elapsed < 86400 { return }
        }
        await checkNow()
    }

    public func checkNow() async {
        if let requestTask { await requestTask.value; return }
        let id = UUID()
        requestID = id
        lastCheckedAt = now()
        defaults.set(lastCheckedAt, forKey: Self.checkedKey)
        state = .checking
        let client = client
        let task = Task { [weak self] in
            do {
                let release = try await client.latestRelease()
                guard let self, self.requestID == id, !Task.isCancelled else { return }
                if let release {
                    guard let release = UpdateRelease.validated(version: release.version,
                                                               pageURL: release.pageURL.absoluteString,
                                                               downloadURL: release.downloadURL.absoluteString),
                          let available = StableUpdateVersion(release.version),
                          let current = StableUpdateVersion(self.currentVersion) else {
                        self.state = .failed(.invalidResponse)
                        return
                    }
                    self.remember(available > current ? release : nil)
                    self.state = available > current ? .available(release) : .upToDate
                } else {
                    self.remember(nil)
                    self.state = .noRelease
                }
            } catch {
                guard let self, self.requestID == id, !Task.isCancelled else { return }
                self.state = .failed(error as? UpdateCheckFailure ?? .network)
            }
        }
        requestTask = task
        await task.value
        if requestID == id {
            requestTask = nil
            requestID = nil
        }
    }
}
