import Foundation

public protocol UpdateReleaseClient: Sendable {
    func latestRelease() async throws -> UpdateRelease?
}

private final class UpdateRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct GitHubUpdateClient: UpdateReleaseClient {
    private let session: URLSession
    private static let maximumBytes = 1_048_576

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration, delegate: UpdateRedirectPolicy(), delegateQueue: nil)
    }

    init(session: URLSession) { self.session = session }

    public func latestRelease() async throws -> UpdateRelease? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/Lotus-030226/AgentMonitor/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AgentMonitor-UpdateCheck", forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse else { throw UpdateCheckFailure.invalidResponse }
            guard response.statusCode == 200 else {
                return try Self.decodeRelease(data: Data(), statusCode: response.statusCode)
            }
            guard response.expectedContentLength <= Self.maximumBytes else {
                throw UpdateCheckFailure.invalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumBytes else { throw UpdateCheckFailure.invalidResponse }
                data.append(byte)
            }
            return try Self.decodeRelease(data: data, statusCode: response.statusCode)
        } catch is CancellationError { throw CancellationError() }
        catch let failure as UpdateCheckFailure { throw failure }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw UpdateCheckFailure.network
        }
    }

    static func decodeRelease(data: Data, statusCode: Int) throws -> UpdateRelease? {
        switch statusCode {
        case 404: return nil
        case 403, 429: throw UpdateCheckFailure.rateLimited
        case 500...599: throw UpdateCheckFailure.serviceUnavailable
        case 200: break
        default: throw UpdateCheckFailure.invalidResponse
        }
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        struct Release: Decodable {
            let tag_name: String
            let draft: Bool
            let prerelease: Bool
            let html_url: String
            let assets: [Asset]
        }
        guard data.count <= maximumBytes,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.draft, !release.prerelease,
              let version = StableUpdateVersion(release.tag_name) else { throw UpdateCheckFailure.invalidResponse }
        let filename = "AgentMonitor-\(version.normalized)-macOS-arm64.zip"
        for asset in release.assets where asset.name == filename {
            if let validated = UpdateRelease.validated(tag: release.tag_name, pageURL: release.html_url,
                                                       downloadURL: asset.browser_download_url) { return validated }
        }
        throw UpdateCheckFailure.invalidResponse
    }
}
