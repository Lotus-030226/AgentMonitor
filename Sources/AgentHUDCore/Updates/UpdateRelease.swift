import Foundation

public struct UpdateRelease: Equatable, Sendable {
    public let version: String
    public let pageURL: URL
    public let downloadURL: URL

    static func validated(tag: String, pageURL: String, downloadURL: String) -> Self? {
        guard let version = StableUpdateVersion(tag) else { return nil }
        let base = "https://github.com/Lotus-030226/AgentMonitor/releases"
        let filename = "AgentMonitor-\(version.normalized)-macOS-arm64.zip"
        guard pageURL == "\(base)/tag/\(tag)",
              downloadURL == "\(base)/download/\(tag)/\(filename)",
              let page = URL(string: pageURL), let download = URL(string: downloadURL) else { return nil }
        return Self(version: version.normalized, pageURL: page, downloadURL: download)
    }

    static func validated(version: String, pageURL: String, downloadURL: String) -> Self? {
        guard let tag = URL(string: pageURL)?.lastPathComponent,
              let release = validated(tag: tag, pageURL: pageURL, downloadURL: downloadURL),
              release.version == version else { return nil }
        return release
    }

    public init(version: String, pageURL: URL, downloadURL: URL) {
        self.version = version
        self.pageURL = pageURL
        self.downloadURL = downloadURL
    }
}

public enum UpdateCheckFailure: String, Error, Equatable, Sendable {
    case network, rateLimited, invalidResponse, serviceUnavailable
}

public enum UpdateCheckState: Equatable, Sendable {
    case idle, checking, upToDate, noRelease
    case available(UpdateRelease)
    case failed(UpdateCheckFailure)
}

struct StableUpdateVersion: Comparable, Sendable {
    let components: [Int]
    let normalized: String

    init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part.count == 1 || part.first != "0", let number = Int(part) else { return nil }
            numbers.append(number)
        }
        components = numbers
        normalized = text
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}
