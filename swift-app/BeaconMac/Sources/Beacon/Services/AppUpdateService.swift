import AppKit
import CryptoKit
import Foundation
import Security

/// Handles verified update checks against the pinned BeaconMac GitHub Releases feed,
/// SHA-256 checksum validation, Apple Developer ID code-signature & Team ID pinning,
/// Gatekeeper (`spctl`) verification, and safe bundle replacement without stripping quarantine.
public final class AppUpdateService: Sendable {
    /// Hard-coded release repository. Never read dynamically from mutable config files.
    public static let pinnedRepo = "arjunmarri/beacon"
    public static let defaultRepo = pinnedRepo

    /// GitHub's signed release asset CDN hosts permitted ONLY as HTTPS redirect targets
    /// from validated `github.com/arjunmarri/beacon/releases/download/...` URLs.
    private static let allowedRedirectHosts: Set<String> = [
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com"
    ]

    public init() {}

    public static func currentAppVersion() -> String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v
        }
        return "1.1.0"
    }

    public static func currentAppBuild() -> String {
        if let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !b.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return b
        }
        return "2"
    }

    /// Strict allowlist for downloadable release artifacts (`.dmg` and `.sha256`).
    /// Accepts ONLY official release download paths for `pinnedRepo` over HTTPS.
    /// Rejects `raw.githubusercontent.com`, arbitrary `*.githubusercontent.com` hosts,
    /// and any repository other than `arjunmarri/beacon`.
    public static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased() else {
            return false
        }

        let normalizedPath = url.standardized.path
        guard !normalizedPath.contains("..") else { return false }

        if host == "github.com" {
            return normalizedPath.hasPrefix("/\(pinnedRepo)/releases/download/")
        }
        if host == "api.github.com" {
            return normalizedPath.hasPrefix("/repos/\(pinnedRepo)/releases/assets/")
        }
        return false
    }

    /// Validates HTTP redirect targets during release artifact downloads.
    fileprivate static func isAllowedRedirectURL(_ url: URL) -> Bool {
        if isAllowedDownloadURL(url) {
            return true
        }
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased() else {
            return false
        }
        return allowedRedirectHosts.contains(host)
    }

    public static func isAllowedReleasePageURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.host?.lowercased() == "github.com" else {
            return false
        }
        let path = url.standardized.path
        return path == "/\(pinnedRepo)/releases" || path.hasPrefix("/\(pinnedRepo)/releases/")
    }

    public static func sanitizeRepo(_ raw: String) -> String {
        // Always return the pinned repository to prevent feed redirection.
        _ = raw
        return pinnedRepo
    }

    /// Extracts a valid 64-character lowercase hexadecimal SHA-256 digest from raw text or a `.sha256` file.
    public static func parseSHA256Hex(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let firstToken = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)?
            .lowercased() ?? ""
        guard firstToken.count == 64,
              firstToken.unicodeScalars.allSatisfy({
                  ($0 >= "0" && $0 <= "9") || ($0 >= "a" && $0 <= "f")
              }) else {
            return nil
        }
        return firstToken
    }

    /// Compares semantic versions numerically (e.g., "1.10.0" > "1.2.0").
    public static func compareSemVer(_ lhs: String, _ rhs: String) -> ComparisonResult {
        func parse(_ raw: String) -> [Int] {
            let cleaned = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
                .split(separator: "-", maxSplits: 1)
                .first
                .map(String.init) ?? "0"
            return cleaned.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parse(lhs)
        let b = parse(rhs)
        let maxLen = max(a.count, b.count)
        for idx in 0..<maxLen {
            let av = idx < a.count ? a[idx] : 0
            let bv = idx < b.count ? b[idx] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return .orderedSame
    }

    public func checkLatestRelease(repo rawRepo: String = pinnedRepo, githubToken: String?) async throws -> AppUpdateRelease {
        _ = rawRepo
        let repo = Self.pinnedRepo
        if let ghRelease = try? await fetchFromGitHubReleasesAPI(repo: repo, githubToken: githubToken) {
            return ghRelease
        }
        return try await fetchFromReleasesManifestFallback(repo: repo)
    }

    private func fetchFromGitHubReleasesAPI(repo: String, githubToken: String?) async throws -> AppUpdateRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BeaconMac/\(Self.currentAppVersion())", forHTTPHeaderField: "User-Agent")
        if let token = githubToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct GHAsset: Decodable {
            let name: String
            let browser_download_url: String
        }
        struct GHRelease: Decodable {
            let tag_name: String
            let html_url: String
            let body: String?
            let published_at: String?
            let assets: [GHAsset]?
        }

        let decoded = try JSONDecoder().decode(GHRelease.self, from: data)
        let cleanVersion = decoded.tag_name.replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
        let dmgAsset = decoded.assets?.first(where: { $0.name.lowercased().hasSuffix("-universal.dmg") })
            ?? decoded.assets?.first(where: { $0.name.lowercased().hasSuffix(".dmg") })

        let dmgURL: URL? = dmgAsset.flatMap { URL(string: $0.browser_download_url) }.flatMap {
            Self.isAllowedDownloadURL($0) ? $0 : nil
        }

        let shaAsset: GHAsset? = {
            guard let assets = decoded.assets else { return nil }
            if let dmgName = dmgAsset?.name.lowercased(),
               let exact = assets.first(where: { $0.name.lowercased() == "\(dmgName).sha256" }) {
                return exact
            }
            return assets.first(where: { $0.name.lowercased().hasSuffix(".dmg.sha256") })
        }()

        let shaURL: URL? = shaAsset.flatMap { URL(string: $0.browser_download_url) }.flatMap {
            Self.isAllowedDownloadURL($0) ? $0 : nil
        }

        let fallbackReleasePage = URL(string: "https://github.com/\(repo)/releases")!
        let htmlURL: URL = URL(string: decoded.html_url).flatMap {
            Self.isAllowedReleasePageURL($0) ? $0 : nil
        } ?? fallbackReleasePage

        return AppUpdateRelease(
            version: cleanVersion,
            tagName: decoded.tag_name,
            releaseNotes: (decoded.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            dmgDownloadURL: dmgURL,
            sha256: nil,
            sha256DownloadURL: shaURL,
            htmlReleaseURL: htmlURL,
            publishedAt: decoded.published_at
        )
    }

    private func fetchFromReleasesManifestFallback(repo: String) async throws -> AppUpdateRelease {
        guard let url = URL(string: "https://raw.githubusercontent.com/\(repo)/main/releases/releases.json") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("BeaconMac/\(Self.currentAppVersion())", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct ManifestRelease: Decodable {
            let version: String
            let date: String?
            let githubDownloadUrl: String?
            let sha256: String?
            let notes: [String]?
        }
        struct Manifest: Decodable {
            let latest: String
            let releases: [ManifestRelease]
        }

        let decoded = try JSONDecoder().decode(Manifest.self, from: data)
        let match = decoded.releases.first(where: { $0.version == decoded.latest }) ?? decoded.releases.first
        let version = match?.version ?? decoded.latest
        let dmgURL = match?.githubDownloadUrl.flatMap(URL.init(string:)).flatMap {
            Self.isAllowedDownloadURL($0) ? $0 : nil
        }
        let shaURL: URL? = dmgURL.flatMap { URL(string: "\($0.absoluteString).sha256") }.flatMap {
            Self.isAllowedDownloadURL($0) ? $0 : nil
        }
        let notesText = (match?.notes ?? []).map { "• \($0)" }.joined(separator: "\n")
        let fallbackReleasePage = URL(string: "https://github.com/\(repo)/releases")!
        let htmlURL = URL(string: "https://github.com/\(repo)/releases/tag/v\(version)").flatMap {
            Self.isAllowedReleasePageURL($0) ? $0 : nil
        } ?? fallbackReleasePage

        return AppUpdateRelease(
            version: version,
            tagName: "v\(version)",
            releaseNotes: notesText,
            dmgDownloadURL: dmgURL,
            sha256: Self.parseSHA256Hex(match?.sha256),
            sha256DownloadURL: shaURL,
            htmlReleaseURL: htmlURL,
            publishedAt: match?.date
        )
    }

    public struct InstallOutcome: Sendable {
        public let ok: Bool
        public let willRelaunch: Bool
        public let detail: String
    }

    /// Downloads the release DMG, verifies its published SHA-256 digest before mounting,
    /// verifies the staged app bundle's Apple Developer ID signature, matching Team ID,
    /// bundle identifier, and Gatekeeper/notarization status (`SecStaticCodeCheckValidity`,
    /// `codesign --verify --deep --strict`, and `spctl --assess`), and swaps the bundle
    /// without removing `com.apple.quarantine`.
    public func downloadAndInstall(
        release: AppUpdateRelease,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async -> InstallOutcome {
        // Inside Mac App Store App Sandbox, binaries cannot overwrite themselves; open the verified release page.
        if EmbeddedScripts.isSandboxed {
            let urlToOpen = Self.isAllowedReleasePageURL(release.htmlReleaseURL)
                ? release.htmlReleaseURL
                : URL(string: "https://github.com/\(Self.pinnedRepo)/releases")!
            await MainActor.run {
                NSWorkspace.shared.open(urlToOpen)
            }
            return InstallOutcome(
                ok: true,
                willRelaunch: false,
                detail: "Opened BeaconMac v\(release.version) release page in your browser (App Sandbox prevents self-overwriting)."
            )
        }

        guard let dmgURL = release.dmgDownloadURL, Self.isAllowedDownloadURL(dmgURL) else {
            let safePage = Self.isAllowedReleasePageURL(release.htmlReleaseURL)
                ? release.htmlReleaseURL
                : URL(string: "https://github.com/\(Self.pinnedRepo)/releases")!
            await MainActor.run {
                NSWorkspace.shared.open(safePage)
            }
            return InstallOutcome(
                ok: true,
                willRelaunch: false,
                detail: "No verified .dmg release asset attached to v\(release.version) yet; opened GitHub release page."
            )
        }

        // If running from a `.app` bundle, require the currently running app to carry a real
        // Apple Developer ID Team ID so we can cryptographically pin the replacement bundle to the same publisher.
        let currentBundleURL = Bundle.main.bundleURL
        let isRunningAppBundle = currentBundleURL.pathExtension.lowercased() == "app"
        var pinnedBundleID: String?
        var pinnedTeamID: String?

        if isRunningAppBundle {
            let runningIdentity = Self.extractCodeSigningIdentity(at: currentBundleURL)
            guard let bundleID = runningIdentity.bundleID,
                  let teamID = runningIdentity.teamID,
                  Self.isSafeIdentifierToken(bundleID),
                  Self.isSafeTeamID(teamID) else {
                return InstallOutcome(
                    ok: false,
                    willRelaunch: false,
                    detail: "Automatic self-update disabled: this local build is not Developer ID–signed (no Team ID to verify updates against). Download signed releases manually from GitHub."
                )
            }
            pinnedBundleID = bundleID
            pinnedTeamID = teamID
        }

        onProgress(0.10, "Fetching SHA-256 checksum for v\(release.version)…")

        guard let expectedSHA256 = await resolveExpectedSHA256(for: release) else {
            return InstallOutcome(
                ok: false,
                willRelaunch: false,
                detail: "Update rejected: release v\(release.version) does not include a valid published .sha256 checksum."
            )
        }

        onProgress(0.20, "Downloading BeaconMac v\(release.version) DMG…")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("beaconmac-update-\(UUID().uuidString)", isDirectory: true)
        let localDMG = tempDir.appendingPathComponent("BeaconMac-\(release.version)-universal.dmg")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let (downloadedTmp, httpStatus) = try await downloadVerifiedAsset(from: dmgURL, timeout: 180)
            guard (200..<300).contains(httpStatus) else {
                try? FileManager.default.removeItem(at: tempDir)
                return InstallOutcome(
                    ok: false,
                    willRelaunch: false,
                    detail: "Download failed for v\(release.version) (HTTP \(httpStatus))."
                )
            }

            if FileManager.default.fileExists(atPath: localDMG.path) {
                try? FileManager.default.removeItem(at: localDMG)
            }
            try FileManager.default.moveItem(at: downloadedTmp, to: localDMG)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            return InstallOutcome(
                ok: false,
                willRelaunch: false,
                detail: "Could not download update DMG: \(SecretMasker.redact(error.localizedDescription))"
            )
        }

        onProgress(0.55, "Verifying SHA-256 checksum…")

        guard let actualSHA256 = Self.computeFileSHA256(at: localDMG) else {
            try? FileManager.default.removeItem(at: tempDir)
            return InstallOutcome(
                ok: false,
                willRelaunch: false,
                detail: "Update rejected: could not compute SHA-256 hash of downloaded DMG."
            )
        }

        guard actualSHA256 == expectedSHA256 else {
            try? FileManager.default.removeItem(at: tempDir)
            return InstallOutcome(
                ok: false,
                willRelaunch: false,
                detail: "Update rejected: DMG SHA-256 mismatch (expected \(expectedSHA256.prefix(12))…, got \(actualSHA256.prefix(12))…)."
            )
        }

        // If running via `swift run` (not a `.app` bundle), hand off the SHA-256-verified DMG to Finder.
        guard isRunningAppBundle, let expectedBundleID = pinnedBundleID, let expectedTeamID = pinnedTeamID else {
            await MainActor.run {
                NSWorkspace.shared.open(localDMG)
            }
            onProgress(1.0, "Verified & opened BeaconMac v\(release.version) DMG")
            return InstallOutcome(
                ok: true,
                willRelaunch: false,
                detail: "Verified SHA-256 and opened BeaconMac-\(release.version)-universal.dmg (running from swift run; drag BeaconMac.app to Applications)."
            )
        }

        onProgress(0.70, "Mounting DMG & staging BeaconMac.app…")

        let mountPoint = tempDir.appendingPathComponent("mount", isDirectory: true)
        let stagedApp = tempDir.appendingPathComponent("BeaconMac.app", isDirectory: true)

        let stageResult = await stageAppFromDMG(dmgPath: localDMG.path, mountPath: mountPoint.path, stagedAppPath: stagedApp.path)
        guard stageResult.ok else {
            try? FileManager.default.removeItem(at: tempDir)
            return InstallOutcome(ok: false, willRelaunch: false, detail: stageResult.detail)
        }

        onProgress(0.84, "Verifying Developer ID signature, Team ID & Gatekeeper…")

        let verifyResult = await verifyStagedApp(
            at: stagedApp,
            expectedBundleID: expectedBundleID,
            expectedTeamID: expectedTeamID
        )
        guard verifyResult.ok else {
            try? FileManager.default.removeItem(at: tempDir)
            return InstallOutcome(ok: false, willRelaunch: false, detail: verifyResult.detail)
        }

        onProgress(0.94, "Installing verified v\(release.version) & preparing relaunch…")

        let targetAppPath = currentBundleURL.path
        let currentPID = ProcessInfo.processInfo.processIdentifier

        // Minimal post-exit helper that swaps the verified bundle without touching com.apple.quarantine.
        let helperScriptURL = tempDir.appendingPathComponent("apply-update.sh")
        let helperBody = """
        #!/bin/bash
        set -euo pipefail
        TARGET_APP="$1"
        STAGED_APP="$2"
        PARENT_PID="$3"
        TEMP_DIR="$4"

        for _ in $(seq 1 50); do
          if ! kill -0 "$PARENT_PID" 2>/dev/null; then
            break
          fi
          sleep 0.1
        done

        BACKUP_APP="${TARGET_APP}.previous"
        rm -rf "$BACKUP_APP"
        if [ -d "$TARGET_APP" ]; then
          mv "$TARGET_APP" "$BACKUP_APP"
        fi
        if /usr/bin/ditto "$STAGED_APP" "$TARGET_APP"; then
          rm -rf "$BACKUP_APP"
          /usr/bin/open -n "$TARGET_APP"
        else
          if [ -d "$BACKUP_APP" ]; then
            mv "$BACKUP_APP" "$TARGET_APP"
          fi
        fi
        rm -rf "$TEMP_DIR"
        """

        do {
            try helperBody.write(to: helperScriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperScriptURL.path)

            let updater = Process()
            updater.executableURL = URL(fileURLWithPath: "/bin/bash")
            updater.arguments = [helperScriptURL.path, targetAppPath, stagedApp.path, String(currentPID), tempDir.path]
            updater.standardOutput = FileHandle.nullDevice
            updater.standardError = FileHandle.nullDevice
            try updater.run()

            onProgress(1.0, "Relaunching into verified BeaconMac v\(release.version)…")
            return InstallOutcome(
                ok: true,
                willRelaunch: true,
                detail: "Verified SHA-256, Developer ID signature (Team \(expectedTeamID)), and Gatekeeper for v\(release.version). Relaunching…"
            )
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            return InstallOutcome(
                ok: false,
                willRelaunch: false,
                detail: "Failed to launch installer helper: \(SecretMasker.redact(error.localizedDescription))"
            )
        }
    }

    // MARK: - Strict Download & Cryptographic Verification Helpers

    private func resolveExpectedSHA256(for release: AppUpdateRelease) async -> String? {
        if let shaURL = release.sha256DownloadURL, Self.isAllowedDownloadURL(shaURL) {
            if let (data, status) = try? await fetchVerifiedAssetData(from: shaURL, timeout: 30),
               (200..<300).contains(status),
               let text = String(data: data, encoding: .utf8),
               let parsed = Self.parseSHA256Hex(text) {
                return parsed
            }
        }
        return Self.parseSHA256Hex(release.sha256)
    }

    private func fetchVerifiedAssetData(from url: URL, timeout: TimeInterval) async throws -> (Data, Int) {
        guard Self.isAllowedDownloadURL(url) else {
            throw URLError(.unsupportedURL)
        }
        let delegate = ReleaseAssetRedirectDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("BeaconMac/\(Self.currentAppVersion())", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let finalURL = response.url, Self.isAllowedRedirectURL(finalURL) else {
            throw URLError(.userAuthenticationRequired)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    private func downloadVerifiedAsset(from url: URL, timeout: TimeInterval) async throws -> (URL, Int) {
        guard Self.isAllowedDownloadURL(url) else {
            throw URLError(.unsupportedURL)
        }
        let delegate = ReleaseAssetRedirectDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("BeaconMac/\(Self.currentAppVersion())", forHTTPHeaderField: "User-Agent")
        let (downloadedURL, response) = try await session.download(for: request)
        guard let finalURL = response.url, Self.isAllowedRedirectURL(finalURL) else {
            try? FileManager.default.removeItem(at: downloadedURL)
            throw URLError(.userAuthenticationRequired)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (downloadedURL, status)
    }

    public static func computeFileSHA256(at fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            guard let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isSafeIdentifierToken(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isSafeTeamID(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        return value.unicodeScalars.allSatisfy {
            ($0 >= "A" && $0 <= "Z") || ($0 >= "0" && $0 <= "9")
        }
    }

    private static func extractCodeSigningIdentity(at appURL: URL) -> (bundleID: String?, teamID: String?) {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let code = staticCode else {
            return (nil, nil)
        }
        var infoCF: CFDictionary?
        let status = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)),
            &infoCF
        )
        guard status == errSecSuccess, let info = infoCF as? [String: Any] else {
            return (nil, nil)
        }
        let signedID = info[kSecCodeInfoIdentifier as String] as? String
        let bundleID = signedID ?? Bundle(url: appURL)?.bundleIdentifier
        let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        return (bundleID, teamID)
    }

    private func verifyStagedApp(
        at stagedAppURL: URL,
        expectedBundleID: String,
        expectedTeamID: String
    ) async -> (ok: Bool, detail: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // 1. Check bundle identifier matches the currently running app
                guard let stagedBundleID = Bundle(url: stagedAppURL)?.bundleIdentifier,
                      stagedBundleID == expectedBundleID else {
                    continuation.resume(returning: (
                        false,
                        "Update rejected: staged bundle identifier does not match \(expectedBundleID)."
                    ))
                    return
                }

                // 2. Verify Developer ID code signature, anchor, and pinned Team ID via Security.framework
                var staticCode: SecStaticCode?
                let createStatus = SecStaticCodeCreateWithPath(stagedAppURL as CFURL, SecCSFlags(), &staticCode)
                guard createStatus == errSecSuccess, let code = staticCode else {
                    continuation.resume(returning: (
                        false,
                        "Update rejected: could not inspect code signature (OSStatus \(createStatus))."
                    ))
                    return
                }

                let requirementString = """
                identifier "\(expectedBundleID)" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "\(expectedTeamID)"
                """
                var requirement: SecRequirement?
                let reqStatus = SecRequirementCreateWithString(requirementString as CFString, SecCSFlags(), &requirement)
                guard reqStatus == errSecSuccess, let compiledRequirement = requirement else {
                    continuation.resume(returning: (
                        false,
                        "Update rejected: failed to build code-signing verification requirement (OSStatus \(reqStatus))."
                    ))
                    return
                }

                let validityFlags = SecCSFlags(
                    rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
                )
                let validityStatus = SecStaticCodeCheckValidity(code, validityFlags, compiledRequirement)
                guard validityStatus == errSecSuccess else {
                    continuation.resume(returning: (
                        false,
                        "Update rejected: code signature or Team ID (\(expectedTeamID)) verification failed (OSStatus \(validityStatus))."
                    ))
                    return
                }

                let stagedIdentity = Self.extractCodeSigningIdentity(at: stagedAppURL)
                guard stagedIdentity.teamID == expectedTeamID, stagedIdentity.bundleID == expectedBundleID else {
                    continuation.resume(returning: (
                        false,
                        "Update rejected: staged bundle signing identity does not match Team \(expectedTeamID)."
                    ))
                    return
                }

                // 3. Verify deep strict signature with codesign
                let codesignCheck = Self.runTool(
                    executable: "/usr/bin/codesign",
                    arguments: ["--verify", "--deep", "--strict", "--verbose=2", stagedAppURL.path]
                )
                guard codesignCheck.exitCode == 0 else {
                    continuation.resume(returning: (
                        false,
                        "Update rejected: codesign --verify --deep --strict failed (\(codesignCheck.output))."
                    ))
                    return
                }

                // 4. Verify Gatekeeper / notarization assessment with spctl
                let spctlCheck = Self.runTool(
                    executable: "/usr/sbin/spctl",
                    arguments: ["--assess", "--type", "execute", "--verbose", stagedAppURL.path]
                )
                guard spctlCheck.exitCode == 0 else {
                    continuation.resume(returning: (
                        false,
                        "Update rejected: Gatekeeper notarization assessment (spctl) failed (\(spctlCheck.output))."
                    ))
                    return
                }

                continuation.resume(returning: (true, "Verified Developer ID signature, Team ID, and Gatekeeper approval."))
            }
        }
    }

    private static func runTool(executable: String, arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, text.isEmpty ? "exit \(process.terminationStatus)" : text)
        } catch {
            return (-1, SecretMasker.redact(error.localizedDescription))
        }
    }

    private func stageAppFromDMG(dmgPath: String, mountPath: String, stagedAppPath: String) async -> (ok: Bool, detail: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try FileManager.default.createDirectory(atPath: mountPath, withIntermediateDirectories: true)

                    let attach = Process()
                    attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                    attach.arguments = ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPath, dmgPath]
                    attach.standardOutput = FileHandle.nullDevice
                    attach.standardError = FileHandle.nullDevice
                    try attach.run()
                    attach.waitUntilExit()

                    defer {
                        let detach = Process()
                        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                        detach.arguments = ["detach", mountPath, "-quiet"]
                        detach.standardOutput = FileHandle.nullDevice
                        detach.standardError = FileHandle.nullDevice
                        try? detach.run()
                        detach.waitUntilExit()
                    }

                    guard attach.terminationStatus == 0 else {
                        continuation.resume(returning: (false, "Could not mount update DMG (hdiutil exit \(attach.terminationStatus))."))
                        return
                    }

                    let contents = (try? FileManager.default.contentsOfDirectory(atPath: mountPath)) ?? []
                    guard let appName = contents.first(where: { $0 == "BeaconMac.app" }) ?? contents.first(where: { $0.hasSuffix(".app") }) else {
                        continuation.resume(returning: (false, "Update DMG did not contain a .app bundle."))
                        return
                    }

                    let sourceAppPath = (mountPath as NSString).appendingPathComponent(appName)
                    let ditto = Process()
                    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    ditto.arguments = [sourceAppPath, stagedAppPath]
                    ditto.standardOutput = FileHandle.nullDevice
                    ditto.standardError = FileHandle.nullDevice
                    try ditto.run()
                    ditto.waitUntilExit()

                    guard ditto.terminationStatus == 0 else {
                        continuation.resume(returning: (false, "Failed to extract \(appName) from DMG (ditto exit \(ditto.terminationStatus))."))
                        return
                    }

                    continuation.resume(returning: (true, "Staged \(appName) successfully."))
                } catch {
                    continuation.resume(returning: (false, SecretMasker.redact(error.localizedDescription)))
                }
            }
        }
    }
}

/// Ensures HTTP redirects during GitHub release asset downloads stay strictly on
/// GitHub's official release asset hosts (`objects.githubusercontent.com` /
/// `release-assets.githubusercontent.com` / pinned `github.com/arjunmarri/beacon/...`).
private final class ReleaseAssetRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let targetURL = request.url, AppUpdateService.isAllowedRedirectURL(targetURL) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}
