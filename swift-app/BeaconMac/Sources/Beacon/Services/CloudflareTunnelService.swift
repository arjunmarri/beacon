import Foundation
import Security

public struct CloudflareTunnelProvisionResult: Sendable {
    public let usedCloudflareAPI: Bool
    public let mode: CloudflareTunnelMode
    public let launchMode: LaunchMode
    public let configFilePath: String
    public let tokenFilePath: String?
    public let publicURL: String?
    public let cloudflareTunnelID: String?
    public let resolvedAccountID: String?
    public let resolvedZoneDomain: String?
    public let detailMessage: String
    public let fallbackReason: String?

    public enum LaunchMode: Sendable {
        case localConfigRun
        case remoteTokenRun
        case quickTunnel
    }
}

/// Uses the existing Cloudflare API token stored in macOS Keychain to dynamically
/// provision/reuse a Cloudflare Tunnel, configure its DNS CNAME route, generate a
/// sanitized `cloudflared` `config.yml` (+ `0600` credentials file), and gracefully
/// fall back to an instant Quick Tunnel config if the API token or DNS zone is unavailable.
public final class CloudflareTunnelService: Sendable {
    public let tunnelsDirectoryURL: URL
    private let session: URLSession

    public init(dataDirectoryURL: URL) {
        self.tunnelsDirectoryURL = dataDirectoryURL.appendingPathComponent("tunnels", isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 25.0
        self.session = URLSession(configuration: config)
    }

    // MARK: - Strict Sanitization

    public static func sanitizeSlug(_ raw: String, fallbackPort: Int) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = ""
        var prevDash = false
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                prevDash = false
            } else if !prevDash && !out.isEmpty {
                out.append("-")
                prevDash = true
            }
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if out.isEmpty {
            out = "app-\(fallbackPort)"
        }
        if out.count > 42 {
            out = String(out.prefix(42)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return out.isEmpty ? "app-\(fallbackPort)" : out
    }

    public static func sanitizeDomain(_ raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/").first.map(String.init) ?? ""
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        let cleaned = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return cleaned.count <= 180 ? cleaned : String(cleaned.prefix(180))
    }

    public static func sanitizeTunnelKey(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(raw.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.isEmpty ? "tunnel" : String(cleaned.prefix(80))
    }

    public func tunnelDirectory(for key: String) -> URL {
        tunnelsDirectoryURL.appendingPathComponent(Self.sanitizeTunnelKey(key), isDirectory: true)
    }

    public func configFileURL(for key: String) -> URL {
        tunnelDirectory(for: key).appendingPathComponent("config.yml")
    }

    public func readGeneratedConfig(for key: String) -> String? {
        let url = configFileURL(for: key)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Dynamic Provisioning & Config Generation

    public func prepareTunnelSession(
        tunnelKey: String,
        appName: String,
        targetPort: Int,
        protocolChoice: CloudflareTunnelProtocol,
        preferCloudflareAPI: Bool,
        customBaseDomain: String,
        apiToken: String?,
        configuredAccountID: String
    ) async -> CloudflareTunnelProvisionResult {
        let safeKey = Self.sanitizeTunnelKey(tunnelKey)
        let clampedPort = max(1, min(65535, targetPort))
        let targetURL = "http://127.0.0.1:\(clampedPort)"
        let slug = Self.sanitizeSlug(appName, fallbackPort: clampedPort)
        let tDir = tunnelDirectory(for: safeKey)
        try? FileManager.default.createDirectory(at: tDir, withIntermediateDirectories: true)

        let trimmedToken = (apiToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // If user enabled Cloudflare API mode and has a Cloudflare API Token in Keychain,
        // dynamically provision via Cloudflare v4 API and generate a named-tunnel config.yml.
        if preferCloudflareAPI && trimmedToken.count >= 8 {
            do {
                return try await provisionViaCloudflareAPI(
                    safeKey: safeKey,
                    slug: slug,
                    targetPort: clampedPort,
                    targetURL: targetURL,
                    protocolChoice: protocolChoice,
                    customBaseDomain: Self.sanitizeDomain(customBaseDomain),
                    apiToken: trimmedToken,
                    configuredAccountID: configuredAccountID.trimmingCharacters(in: .whitespacesAndNewlines),
                    tunnelDir: tDir
                )
            } catch {
                let reason = SecretMasker.redact(error.localizedDescription)
                let quickPath = writeQuickTunnelConfig(
                    in: tDir,
                    targetURL: targetURL,
                    protocolChoice: protocolChoice,
                    note: "Fallback to Quick Tunnel (Cloudflare API: \(reason))"
                )
                return CloudflareTunnelProvisionResult(
                    usedCloudflareAPI: false,
                    mode: .quickTunnel,
                    launchMode: .quickTunnel,
                    configFilePath: quickPath,
                    tokenFilePath: nil,
                    publicURL: nil,
                    cloudflareTunnelID: nil,
                    resolvedAccountID: nil,
                    resolvedZoneDomain: nil,
                    detailMessage: "Generated Quick Tunnel config.yml (Cloudflare API fallback)",
                    fallbackReason: reason
                )
            }
        }

        let quickPath = writeQuickTunnelConfig(
            in: tDir,
            targetURL: targetURL,
            protocolChoice: protocolChoice,
            note: trimmedToken.isEmpty
                ? "No Cloudflare API token in Keychain — using zero-config Quick Tunnel"
                : "Quick Tunnel mode selected"
        )
        return CloudflareTunnelProvisionResult(
            usedCloudflareAPI: false,
            mode: .quickTunnel,
            launchMode: .quickTunnel,
            configFilePath: quickPath,
            tokenFilePath: nil,
            publicURL: nil,
            cloudflareTunnelID: nil,
            resolvedAccountID: nil,
            resolvedZoneDomain: nil,
            detailMessage: "Generated Quick Tunnel config.yml",
            fallbackReason: nil
        )
    }

    // MARK: - Cloudflare v4 API Workflow

    private enum ProvisionError: LocalizedError {
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .apiError(let msg): return msg
            }
        }
    }

    private func provisionViaCloudflareAPI(
        safeKey: String,
        slug: String,
        targetPort: Int,
        targetURL: String,
        protocolChoice: CloudflareTunnelProtocol,
        customBaseDomain: String,
        apiToken: String,
        configuredAccountID: String,
        tunnelDir: URL
    ) async throws -> CloudflareTunnelProvisionResult {
        // 1. Resolve Cloudflare Account ID (use configured one or discover via API)
        let accountID: String
        if !configuredAccountID.isEmpty {
            accountID = configuredAccountID
        } else {
            accountID = try await fetchPrimaryAccountID(apiToken: apiToken)
        }

        // 2. Resolve active DNS Zone so we can assign a real HTTPS hostname (<slug>.<zone>)
        let zone = try await resolveDNSZone(
            apiToken: apiToken,
            accountID: accountID,
            preferredDomain: customBaseDomain
        )
        let hostname = "\(slug).\(zone.name)"
        let publicURL = "https://\(hostname)"

        // 3. Find or create Cloudflare Tunnel for this local app/port
        let tunnelName = "beaconmac-\(slug)-\(targetPort)"
        let credsURL = tunnelDir.appendingPathComponent("credentials.json")

        let existingTunnel = try await findExistingTunnel(
            apiToken: apiToken,
            accountID: accountID,
            tunnelName: tunnelName
        )

        let tunnelID: String
        let launchMode: CloudflareTunnelProvisionResult.LaunchMode
        var tokenFilePath: String? = nil

        if let existing = existingTunnel {
            tunnelID = existing.id
            // Check whether we already have matching local credentials.json for this tunnel
            if hasValidCredentialsFile(at: credsURL, expectedTunnelID: tunnelID) {
                launchMode = .localConfigRun
            } else {
                // Reuse existing remote tunnel by pushing ingress config via API and fetching its run token
                try await pushRemoteIngressConfig(
                    apiToken: apiToken,
                    accountID: accountID,
                    tunnelID: tunnelID,
                    hostname: hostname,
                    serviceURL: targetURL
                )
                let runToken = try await fetchTunnelRunToken(
                    apiToken: apiToken,
                    accountID: accountID,
                    tunnelID: tunnelID
                )
                let tokenURL = tunnelDir.appendingPathComponent("tunnel.token")
                try writePrivateFile(runToken, to: tokenURL)
                tokenFilePath = tokenURL.path
                launchMode = .remoteTokenRun
            }
        } else {
            // Create brand-new locally-configured tunnel with cryptographic 32-byte secret
            let tunnelSecretBase64 = generateSecureBase64Secret(byteCount: 32)
            let createdID = try await createLocalConfigTunnel(
                apiToken: apiToken,
                accountID: accountID,
                tunnelName: tunnelName,
                tunnelSecretBase64: tunnelSecretBase64
            )
            tunnelID = createdID

            // Write standard cloudflared credentials JSON with 0600 permissions
            let credsPayload: [String: String] = [
                "AccountTag": accountID,
                "TunnelSecret": tunnelSecretBase64,
                "TunnelID": tunnelID
            ]
            let credsData = try JSONSerialization.data(withJSONObject: credsPayload, options: [.prettyPrinted, .sortedKeys])
            let credsText = String(data: credsData, encoding: .utf8) ?? "{}"
            try writePrivateFile(credsText, to: credsURL)

            // Also sync ingress config remotely as a helpful mirror for Cloudflare dashboard visibility
            try? await pushRemoteIngressConfig(
                apiToken: apiToken,
                accountID: accountID,
                tunnelID: tunnelID,
                hostname: hostname,
                serviceURL: targetURL
            )
            launchMode = .localConfigRun
        }

        // 4. Upsert proxied DNS CNAME record: <slug>.<zone> -> <tunnelID>.cfargotunnel.com
        try await upsertTunnelCNAME(
            apiToken: apiToken,
            zoneID: zone.id,
            hostname: hostname,
            tunnelID: tunnelID
        )

        // 5. Dynamically generate cloudflared config.yml pointing directly to http://127.0.0.1:<port>
        let configPath = writeNamedTunnelConfig(
            in: tunnelDir,
            tunnelID: tunnelID,
            credentialsFilePath: credsURL.path,
            hostname: hostname,
            targetURL: targetURL,
            protocolChoice: protocolChoice,
            includeCredentialsFile: launchMode == .localConfigRun
        )

        return CloudflareTunnelProvisionResult(
            usedCloudflareAPI: true,
            mode: .apiManaged,
            launchMode: launchMode,
            configFilePath: configPath,
            tokenFilePath: tokenFilePath,
            publicURL: publicURL,
            cloudflareTunnelID: tunnelID,
            resolvedAccountID: accountID,
            resolvedZoneDomain: zone.name,
            detailMessage: "Provisioned Cloudflare Tunnel via Keychain API (\(hostname) → \(targetURL))",
            fallbackReason: nil
        )
    }

    // MARK: - Config Writers

    private func writeNamedTunnelConfig(
        in dir: URL,
        tunnelID: String,
        credentialsFilePath: String,
        hostname: String,
        targetURL: String,
        protocolChoice: CloudflareTunnelProtocol,
        includeCredentialsFile: Bool
    ) -> String {
        let configURL = dir.appendingPathComponent("config.yml")
        var lines: [String] = [
            "# Auto-generated by BeaconMac via Cloudflare Keychain API",
            "# Target: \(targetURL)",
            "tunnel: \(tunnelID)"
        ]
        if includeCredentialsFile {
            let escapedCreds = credentialsFilePath.replacingOccurrences(of: "\"", with: "")
            lines.append("credentials-file: \"\(escapedCreds)\"")
        }
        if protocolChoice != .auto {
            lines.append("protocol: \(protocolChoice.rawValue)")
        }
        lines.append("no-autoupdate: true")
        lines.append("ingress:")
        lines.append("  - hostname: \(hostname)")
        lines.append("    service: \(targetURL)")
        lines.append("  - service: http_status:404")
        lines.append("")

        let content = lines.joined(separator: "\n")
        try? content.write(to: configURL, atomically: true, encoding: .utf8)
        return configURL.path
    }

    private func writeQuickTunnelConfig(
        in dir: URL,
        targetURL: String,
        protocolChoice: CloudflareTunnelProtocol,
        note: String
    ) -> String {
        let configURL = dir.appendingPathComponent("config.yml")
        var lines: [String] = [
            "# Auto-generated by BeaconMac (Quick Tunnel)",
            "# \(note.replacingOccurrences(of: "\n", with: " "))",
            "url: \(targetURL)"
        ]
        if protocolChoice != .auto {
            lines.append("protocol: \(protocolChoice.rawValue)")
        }
        lines.append("no-autoupdate: true")
        lines.append("")

        let content = lines.joined(separator: "\n")
        try? content.write(to: configURL, atomically: true, encoding: .utf8)
        return configURL.path
    }

    private func writePrivateFile(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func hasValidCredentialsFile(at url: URL, expectedTunnelID: String) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tid = json["TunnelID"] as? String,
              let secret = json["TunnelSecret"] as? String else {
            return false
        }
        return tid == expectedTunnelID && !secret.isEmpty
    }

    private func generateSecureBase64Secret(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status == errSecSuccess {
            return Data(bytes).base64EncodedString()
        }
        // Fallback using Swift's SystemRandomNumberGenerator if SecRandomCopyBytes fails
        var rng = SystemRandomNumberGenerator()
        for idx in 0..<byteCount {
            bytes[idx] = UInt8.random(in: 0...255, using: &rng)
        }
        return Data(bytes).base64EncodedString()
    }

    // MARK: - Cloudflare REST API Helpers

    private struct CFEnvelope<T: Decodable>: Decodable {
        struct CFAPIError: Decodable {
            let code: Int?
            let message: String?
        }
        let success: Bool?
        let result: T?
        let errors: [CFAPIError]?
    }

    private struct CFAccountItem: Decodable {
        let id: String
        let name: String?
    }

    private struct CFZoneItem: Decodable {
        let id: String
        let name: String
    }

    private struct CFTunnelItem: Decodable {
        let id: String
        let name: String?
    }

    private struct CFDNSRecordItem: Decodable {
        let id: String
        let name: String?
        let content: String?
    }

    private func cfRequest<T: Decodable>(
        method: String,
        path: String,
        apiToken: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> T {
        guard let url = URL(string: "https://api.cloudflare.com/client/v4\(path)") else {
            throw ProvisionError.apiError("Invalid Cloudflare API URL.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
        }

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        let decoded = try? JSONDecoder().decode(CFEnvelope<T>.self, from: data)
        if (200...299).contains(status), decoded?.success == true, let result = decoded?.result {
            return result
        }

        let errMsg = decoded?.errors?.compactMap(\.message).joined(separator: "; ")
            ?? "Cloudflare API HTTP \(status)"
        throw ProvisionError.apiError(errMsg)
    }

    private func fetchPrimaryAccountID(apiToken: String) async throws -> String {
        let accounts: [CFAccountItem] = try await cfRequest(
            method: "GET",
            path: "/accounts?per_page=5",
            apiToken: apiToken
        )
        guard let first = accounts.first, !first.id.isEmpty else {
            throw ProvisionError.apiError("No Cloudflare account found for API token (add Account ID in Settings or grant Account:Read).")
        }
        return first.id
    }

    private func resolveDNSZone(
        apiToken: String,
        accountID: String,
        preferredDomain: String
    ) async throws -> CFZoneItem {
        let queryPath: String
        if !preferredDomain.isEmpty,
           let encoded = preferredDomain.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryPath = "/zones?name=\(encoded)&status=active&per_page=5"
        } else {
            queryPath = "/zones?account.id=\(accountID)&status=active&per_page=10"
        }

        let zones: [CFZoneItem] = try await cfRequest(
            method: "GET",
            path: queryPath,
            apiToken: apiToken
        )
        if let match = zones.first {
            return match
        }
        if !preferredDomain.isEmpty {
            throw ProvisionError.apiError("Active Cloudflare DNS zone '\(preferredDomain)' not found (check Zone:DNS permissions).")
        }
        throw ProvisionError.apiError("No active Cloudflare DNS zone found for this account (add a domain in Cloudflare or use Quick Tunnel).")
    }

    private func findExistingTunnel(
        apiToken: String,
        accountID: String,
        tunnelName: String
    ) async throws -> CFTunnelItem? {
        let encodedName = tunnelName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tunnelName
        let tunnels: [CFTunnelItem] = try await cfRequest(
            method: "GET",
            path: "/accounts/\(accountID)/cfd_tunnel?name=\(encodedName)&is_deleted=false",
            apiToken: apiToken
        )
        return tunnels.first
    }

    private func createLocalConfigTunnel(
        apiToken: String,
        accountID: String,
        tunnelName: String,
        tunnelSecretBase64: String
    ) async throws -> String {
        let created: CFTunnelItem = try await cfRequest(
            method: "POST",
            path: "/accounts/\(accountID)/cfd_tunnel",
            apiToken: apiToken,
            jsonBody: [
                "name": tunnelName,
                "tunnel_secret": tunnelSecretBase64,
                "config_src": "local"
            ]
        )
        return created.id
    }

    private func pushRemoteIngressConfig(
        apiToken: String,
        accountID: String,
        tunnelID: String,
        hostname: String,
        serviceURL: String
    ) async throws {
        struct EmptyResult: Decodable {}
        let _: EmptyResult? = try? await cfRequest(
            method: "PUT",
            path: "/accounts/\(accountID)/cfd_tunnel/\(tunnelID)/configurations",
            apiToken: apiToken,
            jsonBody: [
                "config": [
                    "ingress": [
                        [
                            "hostname": hostname,
                            "service": serviceURL
                        ],
                        [
                            "service": "http_status:404"
                        ]
                    ]
                ]
            ]
        )
    }

    private func fetchTunnelRunToken(
        apiToken: String,
        accountID: String,
        tunnelID: String
    ) async throws -> String {
        let token: String = try await cfRequest(
            method: "GET",
            path: "/accounts/\(accountID)/cfd_tunnel/\(tunnelID)/token",
            apiToken: apiToken
        )
        guard !token.isEmpty else {
            throw ProvisionError.apiError("Cloudflare returned an empty tunnel run token.")
        }
        return token
    }

    private func upsertTunnelCNAME(
        apiToken: String,
        zoneID: String,
        hostname: String,
        tunnelID: String
    ) async throws {
        let cnameTarget = "\(tunnelID).cfargotunnel.com"
        let encodedHost = hostname.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? hostname

        let existing: [CFDNSRecordItem] = try await cfRequest(
            method: "GET",
            path: "/zones/\(zoneID)/dns_records?type=CNAME&name=\(encodedHost)",
            apiToken: apiToken
        )

        let body: [String: Any] = [
            "type": "CNAME",
            "name": hostname,
            "content": cnameTarget,
            "proxied": true,
            "ttl": 1,
            "comment": "Managed by BeaconMac one-click Cloudflare Tunnel"
        ]

        if let record = existing.first {
            if record.content == cnameTarget {
                return
            }
            let _: CFDNSRecordItem = try await cfRequest(
                method: "PUT",
                path: "/zones/\(zoneID)/dns_records/\(record.id)",
                apiToken: apiToken,
                jsonBody: body
            )
        } else {
            let _: CFDNSRecordItem = try await cfRequest(
                method: "POST",
                path: "/zones/\(zoneID)/dns_records",
                apiToken: apiToken,
                jsonBody: body
            )
        }
    }
}
