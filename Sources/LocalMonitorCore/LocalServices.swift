import Foundation
import Darwin

public enum LocalServicesStatus: String, Sendable, Equatable {
    case notSampled, available, empty, partial, timedOut, unavailable
    public var description: String {
        switch self {
        case .notSampled: "尚未取樣"
        case .available: "已讀取 TCP 監聽埠"
        case .empty: "未發現可讀取的 TCP 監聽埠"
        case .partial: "部分資料無法讀取"
        case .timedOut: "取樣逾時"
        case .unavailable: "無法讀取監聽埠（權限或系統限制）"
        }
    }
}

public enum LocalServiceScheme: String, Sendable { case http, https }

public enum LocalServiceAddressFamily: String, Sendable {
    case ipv4 = "IPv4", ipv6 = "IPv6", unknown = "未知位址類型"
}

public struct LocalServiceSample: Identifiable, Sendable, Equatable {
    public let pid: Int32
    public let process: String
    public let address: String
    public let port: UInt16
    public let addressFamily: LocalServiceAddressFamily
    public var workingDirectory: String?
    public var applicationProtocol: String { "未知" }
    public var id: String { "\(pid)|\(process)|\(addressFamily.rawValue)|\(address)|\(port)" }
    public init(pid: Int32, process: String, address: String, port: UInt16,
                addressFamily: LocalServiceAddressFamily = .unknown, workingDirectory: String? = nil) {
        self.pid = pid; self.process = process; self.address = address; self.port = port
        self.addressFamily = LocalServicesParser.literalAddressFamily(address) ?? addressFamily
        self.workingDirectory = workingDirectory
    }
    public func url(scheme: LocalServiceScheme) -> URL? {
        let host: String
        if address == "*" {
            switch addressFamily {
            case .ipv4: host = "127.0.0.1"
            case .ipv6: host = "::1"
            case .unknown: return nil
            }
        } else { host = address == "0.0.0.0" ? "127.0.0.1" : address == "::" ? "::1" : address }
        guard LocalServicesParser.isLiteralAddress(host), port > 0 else { return nil }
        let authority = host.contains(":") ? "[\(host)]" : host
        return URL(string: "\(scheme.rawValue)://\(authority):\(port)/")
    }
}

public struct LocalServicesSnapshot: Sendable, Equatable {
    /// Timestamp of retained rows. Failed reads do not change it.
    public let timestamp: Date
    public let attemptedAt: Date
    public let services: [LocalServiceSample]
    public let status: LocalServicesStatus
    public let isStale: Bool
    public init(timestamp: Date = Date(), attemptedAt: Date? = nil, services: [LocalServiceSample] = [],
                status: LocalServicesStatus = .notSampled, isStale: Bool = false) {
        self.timestamp = timestamp; self.attemptedAt = attemptedAt ?? timestamp
        self.services = services; self.status = status; self.isStale = isStale
    }
    public static let empty = LocalServicesSnapshot()
    public static var demo: LocalServicesSnapshot {
        LocalServicesSnapshot(services: [
            LocalServiceSample(pid: 4101, process: "Python", address: "127.0.0.1", port: 8810, workingDirectory: "/Demo/Projects/Website"),
            LocalServiceSample(pid: 4102, process: "node", address: "::1", port: 3000, workingDirectory: nil),
            LocalServiceSample(pid: 4103, process: "postgres", address: "127.0.0.1", port: 5432, workingDirectory: nil)
        ], status: .available)
    }
    static func failed(previous: Self, status: LocalServicesStatus, at: Date) -> Self {
        Self(timestamp: previous.timestamp, attemptedAt: at, services: previous.services,
             status: status, isStale: previous.status != .notSampled)
    }
}

enum LocalServicesPolling {
    static func shouldSample(last: Double?, now: Double) -> Bool {
        guard let last else { return true }
        return now < last || now - last >= 10
    }
}

public enum LocalServicesParser {
    public struct Result: Sendable {
        public let services: [LocalServiceSample]
        public let rejectedEndpoints: Int
    }
    public static func listeners(_ text: String) -> Result {
        var pid: Int32?
        var name: String?
        var socketFamily = LocalServiceAddressFamily.unknown
        var rows: [String: LocalServiceSample] = [:]
        var rejected = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": pid = Int32(value).flatMap { $0 > 0 ? $0 : nil }; name = nil; socketFamily = .unknown
            case "c": name = value.isEmpty || value.contains(where: \.isNewline) ? nil : value
            case "t": socketFamily = LocalServiceAddressFamily(rawValue: value) ?? .unknown
            case "n":
                defer { socketFamily = .unknown }
                guard let pid, let name, let endpoint = endpoint(value) else { rejected += 1; continue }
                let literalFamily = literalAddressFamily(endpoint.0)
                if let literalFamily, socketFamily != .unknown, socketFamily != literalFamily {
                    rejected += 1; continue
                }
                let row = LocalServiceSample(pid: pid, process: name, address: endpoint.0, port: endpoint.1,
                                             addressFamily: literalFamily ?? socketFamily)
                rows[row.id] = row
            default: break
            }
        }
        return Result(services: rows.values.sorted { ($0.pid, $0.address, $0.port, $0.addressFamily.rawValue) < ($1.pid, $1.address, $1.port, $1.addressFamily.rawValue) },
                      rejectedEndpoints: rejected)
    }
    static func endpoint(_ value: String) -> (String, UInt16)? {
        guard let colon = value.lastIndex(of: ":"), let port = UInt16(value[value.index(after: colon)...]), port > 0 else { return nil }
        var host = String(value[..<colon])
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        guard host == "*" || isLiteralAddress(host) else { return nil }
        return (host, port)
    }
    static func isLiteralAddress(_ host: String) -> Bool {
        literalAddressFamily(host) != nil
    }
    static func literalAddressFamily(_ host: String) -> LocalServiceAddressFamily? {
        var ipv4 = in_addr(); var ipv6 = in6_addr()
        return host.withCString {
            if inet_pton(AF_INET, $0, &ipv4) == 1 { return .ipv4 }
            if inet_pton(AF_INET6, $0, &ipv6) == 1 { return .ipv6 }
            return nil
        }
    }
    static func workingDirectories(_ text: String, services: [LocalServiceSample]) -> [Int32: String] {
        let names = Dictionary(services.map { ($0.pid, $0.process) }, uniquingKeysWith: { first, _ in first })
        var pid: Int32?; var name: String?; var cwd = false
        var result: [Int32: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": pid = Int32(value); name = nil; cwd = false
            case "c": name = value
            case "f": cwd = value == "cwd"
            case "n":
                if cwd, let pid, let name, names[pid] == name, value.hasPrefix("/"),
                   !value.contains(where: { $0.isNewline || $0 == "\0" }) { result[pid] = value }
            default: break
            }
        }
        return result
    }
}
