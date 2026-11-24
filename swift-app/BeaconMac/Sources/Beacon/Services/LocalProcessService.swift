import Darwin
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

    /// Normalizes local URLs so inputs like `localhost:3001` or `127.0.0.1:5173` automatically
    /// receive an `http://` scheme before validation and probing.
    public static func normalizeLocalAppURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "http://\(trimmed)"
    }

    /// Accepts any local development host (localhost, 127.0.0.1, ::1, *.localhost, *.local)
    /// while blocking remote public internet hosts and embedded URL credentials.
    public static func isValidLocalAppURL(_ raw: String) -> Bool {
        let normalized = normalizeLocalAppURL(raw)
        guard !normalized.isEmpty,
              normalized.count <= 240,
              let url = URL(string: normalized),
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
        guard let url = URL(string: normalizeLocalAppURL(raw)) else { return fallback }
        if let port = url.port, (1...65535).contains(port) {
            return port
        }
        return url.scheme?.lowercased() == "https" ? 443 : 80
    }

    /// Lightweight, silent non-blocking TCP pre-check for loopback hosts (`localhost`, `127.0.0.1`,
    /// `::1`, `0.0.0.0`). Prevents `URLSession` / `Network.framework` from spamming Xcode's console
    /// with verbose `nw_socket_handle_socket_event [61: Connection refused]` diagnostics whenever a
    /// monitored local app has not been started yet or is offline.
    public static func isLoopbackPortListening(host: String, port: Int, timeoutMs: Int32 = 250) -> Bool {
        guard (1...65535).contains(port) else { return false }
        let normalized = host.lowercased()
        switch normalized {
        case "127.0.0.1", "0.0.0.0":
            return canConnectTCPv4(port: UInt16(port), timeoutMs: timeoutMs)
        case "::1":
            return canConnectTCPv6(port: UInt16(port), timeoutMs: timeoutMs)
        case "localhost":
            return canConnectTCPv4(port: UInt16(port), timeoutMs: timeoutMs)
                || canConnectTCPv6(port: UInt16(port), timeoutMs: timeoutMs)
        default:
            // Non-loopback local names (e.g. *.local / *.localhost) fall through to URLSession.
            return true
        }
    }

    private static func canConnectTCPv4(port: UInt16, timeoutMs: Int32) -> Bool {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        let flags = Darwin.fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return finishNonBlockingConnect(fd: fd, connectResult: result, timeoutMs: timeoutMs)
    }

    private static func canConnectTCPv6(port: UInt16, timeoutMs: Int32) -> Bool {
        let fd = Darwin.socket(AF_INET6, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        let flags = Darwin.fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = port.bigEndian
        addr.sin6_addr = in6addr_loopback

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        return finishNonBlockingConnect(fd: fd, connectResult: result, timeoutMs: timeoutMs)
    }

    private static func finishNonBlockingConnect(fd: Int32, connectResult: Int32, timeoutMs: Int32) -> Bool {
        if connectResult == 0 {
            return true
        }
        guard errno == EINPROGRESS else {
            return false
        }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pollResult = Darwin.poll(&pfd, 1, timeoutMs)
        guard pollResult > 0 else {
            return false
        }

        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        guard Darwin.getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 else {
            return false
        }
        return soError == 0
    }

    public func probe(urlString: String) async -> LocalProbeResult {
        let normalizedURLString = Self.normalizeLocalAppURL(urlString)
        guard Self.isValidLocalAppURL(normalizedURLString), let url = URL(string: normalizedURLString) else {
            return LocalProbeResult(
                healthy: false,
                httpStatus: nil,
                responseTimeMs: nil,
                error: "Enter a local app URL (e.g. http://localhost:3000, http://127.0.0.1:8080, or http://myapp.local:5173)."
            )
        }

        let host = url.host?.lowercased() ?? "localhost"
        let port = Self.extractPort(from: normalizedURLString, fallback: url.scheme?.lowercased() == "https" ? 443 : 80)

        // Quietly verify the loopback port is open before invoking URLSession so offline apps
        // don't emit noisy Network.framework `SO_ERROR [61: Connection refused]` logs every poll.
        let portOpen = await Task.detached(priority: .utility) {
            Self.isLoopbackPortListening(host: host, port: port)
        }.value

        guard portOpen else {
            return LocalProbeResult(
                healthy: false,
                httpStatus: nil,
                responseTimeMs: nil,
                error: "No server listening on \(host):\(port) yet (connection refused)."
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

        do {
            // Never gate on FileManager.fileExists(atPath:) inside macOS App Sandbox:
            // Sandbox denies POSIX stat() on ~/Library/Application Scripts/<bundle-id>/.
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
            let nsErr = error as NSError
            let isMissing = nsErr.domain == NSCocoaErrorDomain && (
                nsErr.code == NSFileReadNoSuchFileError ||
                nsErr.code == NSFileNoSuchFileError
            )
            if isMissing {
                return (
                    false,
                    "Click \"Install Hook Scripts\" or install beacon-restart.sh in ~/Library/Application Scripts/\(EmbeddedScripts.bundleID)/ to enable App-Store-safe automatic restarts."
                )
            }
            return (false, "Restart script failed: \(error.localizedDescription)")
        }
    }
}
