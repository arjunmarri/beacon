import Foundation

public struct LocalProbeResult: Sendable {
    public let healthy: Bool
    public let httpStatus: Int?
    public let responseTimeMs: Int?
    public let error: String?
}

/// Probes any locally deployed target application URL (localhost, 127.0.0.1, ::1,
/// *.localhost, or *.local) and invokes Apple's App-Sandbox-approved NSUserUnixTask
/// script to restart that external target app if it crashes.
public final class LocalProcessService: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 4.0
        self.session = URLSession(configuration: config)
    }

    /// Accepts any local development host (localhost, 127.0.0.1, ::1, *.localhost, *.local)
    /// while blocking remote public internet hosts and embedded URL credentials.
    public static func isValidLocalAppURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 240,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host?.lowercased(),
              url.user == nil, url.password == nil else {
            return false
        }

        let isLocalHost =
            host == "localhost" ||
            host == "127.0.0.1" ||
            host == "::1" ||
            host == "0.0.0.0" ||
            host.hasSuffix(".localhost") ||
            host.hasSuffix(".local")

        guard isLocalHost else { return false }

        if let port = url.port, (port < 1 || port > 65535) {
            return false
        }
        return true
    }

    public static func extractPort(from raw: String, fallback: Int = 3000) -> Int {
        guard let url = URL(string: raw) else { return fallback }
        if let port = url.port, (1...65535).contains(port) {
            return port
        }
        return url.scheme?.lowercased() == "https" ? 443 : 80
    }

    public func probe(urlString: String) async -> LocalProbeResult {
        guard Self.isValidLocalAppURL(urlString), let url = URL(string: urlString) else {
            return LocalProbeResult(
                healthy: false,
                httpStatus: nil,
                responseTimeMs: nil,
                error: "Enter a local app URL (e.g. http://localhost:3000, http://127.0.0.1:8080, or http://myapp.local:5173)."
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
    /// via Apple's App-Sandbox-approved NSUserUnixTask API to restart the target local app.
    public func runSandboxRestartScript(
        workingDir: String,
        port: Int,
        startCommand: String = ""
    ) async -> (ok: Bool, detail: String) {
        let trimmedDir = workingDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDir.isEmpty else {
            return (false, "Set the Target App Folder in Configuration before triggering a restart.")
        }

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
                "Install beacon-restart.sh in ~/Library/Application Scripts/\(Bundle.main.bundleIdentifier ?? "com.beaconmac.app")/ to enable App-Store-safe automatic restarts."
            )
        }

        do {
            let task = try NSUserUnixTask(url: scriptURL)
            var args = [trimmedDir, String(port)]
            let trimmedCmd = startCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCmd.isEmpty {
                args.append(trimmedCmd)
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                task.execute(withArguments: args) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            return (true, "Restarted target local app in \(trimmedDir) on port \(port).")
        } catch {
            return (false, "Restart script failed: \(error.localizedDescription)")
        }
    }
}
