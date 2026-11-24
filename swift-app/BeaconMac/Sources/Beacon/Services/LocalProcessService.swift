import Darwin
import Foundation

public struct LocalProbeResult: Sendable {
    public let healthy: Bool
    public let httpStatus: Int?
    public let responseTimeMs: Int?
    public let error: String?
}

/// Delegate for local development health probes:
/// 1. Does NOT follow redirects (a 301/302/307/308 from localhost means the server is healthy).
/// 2. Trusts self-signed TLS certificates ONLY on loopback / `.local` hosts so local HTTPS dev servers work.
private final class LocalProbeSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Do not follow redirects to external login/OAuth pages; the local server already responded.
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            let host = challenge.protectionSpace.host.lowercased()
            let isLocal =
                host == "localhost" ||
                host == "127.0.0.1" ||
                host == "::1" ||
                host == "0.0.0.0" ||
                host.hasSuffix(".localhost") ||
                host.hasSuffix(".local")
            if isLocal {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

/// Probes any locally deployed target application URL (localhost, 127.0.0.1, ::1,
/// *.localhost, or *.local) and invokes Apple's App-Sandbox-approved NSUserUnixTask
/// script to restart that external target app if it crashes.
public final class LocalProcessService: Sendable {
    private let session: URLSession
    private let delegate = LocalProbeSessionDelegate()

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 8.0
        config.waitsForConnectivity = false
        // Bypass macOS system HTTP/SOCKS/VPN proxies for loopback monitoring so
        // `http://localhost:3001` behaves identically to `http://127.0.0.1:11434`.
        config.connectionProxyDictionary = [:]
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
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

    private enum LoopbackFamily: Sendable {
        case ipv4
        case ipv6
        case passthrough
    }

    /// Lightweight, silent non-blocking TCP pre-check for loopback hosts (`localhost`, `127.0.0.1`,
    /// `::1`, `0.0.0.0`). Prevents `URLSession` / `Network.framework` from spamming Xcode's console
    /// with verbose `nw_socket_handle_socket_event [61: Connection refused]` diagnostics whenever a
    /// monitored local app has not been started yet or is offline.
    public static func isLoopbackPortListening(host: String, port: Int, timeoutMs: Int32 = 300) -> Bool {
        detectLoopbackFamily(host: host, port: port, timeoutMs: timeoutMs) != nil
    }

    private static func detectLoopbackFamily(host: String, port: Int, timeoutMs: Int32 = 300) -> LoopbackFamily? {
        guard (1...65535).contains(port) else { return nil }
        let normalized = host.lowercased()
        switch normalized {
        case "127.0.0.1", "0.0.0.0":
            return canConnectTCPv4(port: UInt16(port), timeoutMs: timeoutMs) ? .ipv4 : nil
        case "::1":
            return canConnectTCPv6(port: UInt16(port), timeoutMs: timeoutMs) ? .ipv6 : nil
        case "localhost":
            if canConnectTCPv4(port: UInt16(port), timeoutMs: timeoutMs) {
                return .ipv4
            }
            if canConnectTCPv6(port: UInt16(port), timeoutMs: timeoutMs) {
                return .ipv6
            }
            return nil
        default:
            // Non-loopback local names (e.g. *.local / *.localhost) fall through to URLSession.
            return .passthrough
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

        var connectErrno: Int32 = 0
        let result: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                let r = Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                connectErrno = errno
                return r
            }
        }
        return finishNonBlockingConnect(fd: fd, connectResult: result, connectErrno: connectErrno, timeoutMs: timeoutMs)
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

        var connectErrno: Int32 = 0
        let result: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                let r = Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in6>.size))
                connectErrno = errno
                return r
            }
        }
        return finishNonBlockingConnect(fd: fd, connectResult: result, connectErrno: connectErrno, timeoutMs: timeoutMs)
    }

    private static func finishNonBlockingConnect(
        fd: Int32,
        connectResult: Int32,
        connectErrno: Int32,
        timeoutMs: Int32
    ) -> Bool {
        if connectResult == 0 {
            return true
        }
        guard connectErrno == EINPROGRESS || connectErrno == EALREADY else {
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

    private static func buildDirectURL(from original: URL, family: LoopbackFamily, schemeOverride: String? = nil) -> URL {
        guard var components = URLComponents(url: original, resolvingAgainstBaseURL: false) else {
            return original
        }
        if let schemeOverride {
            components.scheme = schemeOverride
        }
        switch family {
        case .ipv4:
            components.host = "127.0.0.1"
        case .ipv6:
            // RFC 3986 requires bracketed IPv6 literals via percentEncodedHost so URLComponents
            // does not percent-encode the colons or brackets.
            components.percentEncodedHost = "[::1]"
        case .passthrough:
            break
        }
        return components.url ?? original
    }

    private func performHeaderProbe(url: URL, hostHeader: String?) async throws -> (status: Int, elapsedMs: Int) {
        let start = CFAbsoluteTimeGetCurrent()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")
        if let hostHeader {
            request.setValue(hostHeader, forHTTPHeaderField: "Host")
        }

        // `session.bytes(for:)` returns as soon as HTTP response headers arrive,
        // avoiding timeouts on SSE streams, chunked dev responses, or large bundles.
        let (bytes, response) = try await session.bytes(for: request)
        bytes.task.cancel()
        let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        return (status, elapsedMs)
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

        // Quietly verify the loopback port is open and identify whether the server is listening
        // on IPv4 (127.0.0.1) or IPv6 (::1) before invoking URLSession.
        let family = await Task.detached(priority: .utility) {
            Self.detectLoopbackFamily(host: host, port: port)
        }.value

        guard let family else {
            return LocalProbeResult(
                healthy: false,
                httpStatus: nil,
                responseTimeMs: nil,
                error: "No server listening on \(host):\(port) yet (connection refused)."
            )
        }

        let directURL = Self.buildDirectURL(from: url, family: family)
        let hostHeader: String? = (family == .passthrough) ? nil : "\(host):\(port)"

        do {
            let (status, elapsedMs) = try await performHeaderProbe(url: directURL, hostHeader: hostHeader)
            return LocalProbeResult(
                healthy: status < 500,
                httpStatus: status,
                responseTimeMs: elapsedMs,
                error: status >= 500 ? "HTTP \(status) returned by \(normalizedURLString)" : nil
            )
        } catch {
            // Retry against the original URL (e.g. if server requires literal `localhost` Host/SNI).
            if directURL != url,
               let (status, elapsedMs) = try? await performHeaderProbe(url: url, hostHeader: nil) {
                return LocalProbeResult(
                    healthy: status < 500,
                    httpStatus: status,
                    responseTimeMs: elapsedMs,
                    error: status >= 500 ? "HTTP \(status) returned by \(normalizedURLString)" : nil
                )
            }

            // If `http://` failed on a confirmed open loopback port (e.g. local dev server is
            // serving HTTPS on that port), automatically try `https://` once.
            if url.scheme?.lowercased() == "http" {
                let httpsURL = Self.buildDirectURL(from: url, family: family, schemeOverride: "https")
                if let (status, elapsedMs) = try? await performHeaderProbe(url: httpsURL, hostHeader: hostHeader) {
                    return LocalProbeResult(
                        healthy: status < 500,
                        httpStatus: status,
                        responseTimeMs: elapsedMs,
                        error: status >= 500 ? "HTTP \(status) returned by https://\(host):\(port)" : nil
                    )
                }
            }

            return LocalProbeResult(
                healthy: false,
                httpStatus: nil,
                responseTimeMs: nil,
                error: "Port \(port) is open, but HTTP check failed: \(error.localizedDescription)"
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
