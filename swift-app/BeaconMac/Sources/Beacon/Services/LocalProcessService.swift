import Foundation

public struct LocalProbeResult: Sendable {
    public let healthy: Bool
    public let httpStatus: Int?
    public let responseTimeMs: Int?
    public let error: String?
}

/// Probes any user-configured localhost URL (loopback-only SSRF guard) and
/// invokes Apple's App-Sandbox-approved NSUserUnixTask script to restart Vite.
public final class LocalProcessService: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 3.0
        self.session = URLSession(configuration: config)
    }

    public static func isValidLocalhostURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host?.lowercased(),
              (host == "localhost" || host == "127.0.0.1"),
              url.user == nil, url.password == nil else {
            return false
        }
        if let port = url.port, (port < 1 || port > 65535) {
            return false
        }
        return raw.count <= 240
    }

    public static func extractPort(from raw: String, fallback: Int = 5173) -> Int {
        guard let url = URL(string: raw), let port = url.port, (1...65535).contains(port) else {
            return fallback
        }
        return port
    }

    public func probe(urlString: String) async -> LocalProbeResult {
        guard Self.isValidLocalhostURL(urlString), let url = URL(string: urlString) else {
            return LocalProbeResult(
                healthy: false,
                httpStatus: nil,
                responseTimeMs: nil,
                error: "Monitor URL must point to http://localhost:<port> or http://127.0.0.1:<port>."
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await session.data(for: request)
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            return LocalProbeResult(
                healthy: status < 500,
                httpStatus: status,
                responseTimeMs: elapsedMs,
                error: status >= 500 ? "HTTP \(status)" : nil
            )
        } catch {
            return LocalProbeResult(
                healthy: false,
                httpStatus: nil,
                responseTimeMs: nil,
                error: error.localizedDescription
            )
        }
    }

    /// Executes `~/Library/Application Scripts/<bundle-id>/beacon-restart.sh`
    /// via Apple's App-Sandbox-approved NSUserUnixTask API.
    public func runSandboxRestartScript(workingDir: String, port: Int) async -> (ok: Bool, detail: String) {
        guard let scriptsDir = try? FileManager.default.url(
            for: .applicationScriptsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return (false, "Application Scripts directory is unavailable.")
        }

        let scriptURL = scriptsDir.appendingPathComponent("beacon-restart.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            return (
                false,
                "Install beacon-restart.sh in ~/Library/Application Scripts/\(Bundle.main.bundleIdentifier ?? "com.beaconmonitor.mac")/ to enable App-Store-safe automatic restarts."
            )
        }

        do {
            let task = try NSUserUnixTask(url: scriptURL)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                task.execute(withArguments: [workingDir, String(port)]) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            return (true, "Executed beacon-restart.sh for \(workingDir) on port \(port).")
        } catch {
            return (false, "Restart script failed: \(error.localizedDescription)")
        }
    }
}
