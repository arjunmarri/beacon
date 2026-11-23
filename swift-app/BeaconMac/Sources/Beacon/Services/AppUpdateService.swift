import AppKit
import Foundation

/// Handles automatic update checks against GitHub Releases (with `releases/releases.json`
/// fallback), verified HTTPS `.dmg` downloads, and seamless macOS self-updates.
public final class AppUpdateService: Sendable {
    public static let defaultRepo = "arjunmarri/beacon"

    private static let allowedDownloadHosts: Set<String> = [
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
        "raw.githubusercontent.com"
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

    public static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return allowedDownloadHosts.contains(host) || host.hasSuffix(".githubusercontent.com")
    }

    public static func sanitizeRepo(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-/"))
        guard trimmed.contains("/"),
              trimmed.split(separator: "/").count == 2,
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return defaultRepo
        }
        return trimmed
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

    public func checkLatestRelease(repo rawRepo: String, githubToken: String?) async throws -> AppUpdateRelease {
        let repo = Self.sanitizeRepo(rawRepo)
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
        let htmlURL = URL(string: decoded.html_url) ?? URL(string: "https://github.com/\(repo)/releases")!

        return AppUpdateRelease(
            version: cleanVersion,
            tagName: decoded.tag_name,
            releaseNotes: (decoded.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            dmgDownloadURL: dmgURL,
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
        let notesText = (match?.notes ?? []).map { "• \($0)" }.joined(separator: "\n")
        let htmlURL = URL(string: "https://github.com/\(repo)/releases/tag/v\(version)")
            ?? URL(string: "https://github.com/\(repo)/releases")!

        return AppUpdateRelease(
            version: version,
            tagName: "v\(version)",
            releaseNotes: notesText,
            dmgDownloadURL: dmgURL,
            htmlReleaseURL: htmlURL,
            publishedAt: match?.date
        )
    }

    public struct InstallOutcome: Sendable {
        public let ok: Bool
        public let willRelaunch: Bool
        public let detail: String
    }

    /// Downloads the release DMG and either installs & relaunches BeaconMac.app automatically
    /// (for non-sandboxed `.app` installs) or hands off safely (for `swift run` / Mac App Store Sandbox).
    public func downloadAndInstall(
        release: AppUpdateRelease,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async -> InstallOutcome {
        // Inside Mac App Store App Sandbox, binaries cannot overwrite themselves; open the verified release URL.
        if EmbeddedScripts.isSandboxed {
            let urlToOpen = release.dmgDownloadURL ?? release.htmlReleaseURL
            await MainActor.run {
                NSWorkspace.shared.open(urlToOpen)
            }
            return InstallOutcome(
                ok: true,
                willRelaunch: false,
                detail: "Opened BeaconMac v\(release.version) download in your browser (App Sandbox prevents self-overwriting)."
            )
        }

        guard let dmgURL = release.dmgDownloadURL, Self.isAllowedDownloadURL(dmgURL) else {
            await MainActor.run {
                NSWorkspace.shared.open(release.htmlReleaseURL)
            }
            return InstallOutcome(
                ok: true,
                willRelaunch: false,
                detail: "No compiled .dmg asset attached to v\(release.version) yet; opened GitHub release page."
            )
        }

        onProgress(0.15, "Downloading BeaconMac v\(release.version) DMG…")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("beaconmac-update-\(UUID().uuidString)", isDirectory: true)
        let localDMG = tempDir.appendingPathComponent("BeaconMac-\(release.version)-universal.dmg")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            var request = URLRequest(url: dmgURL, timeoutInterval: 180)
            request.setValue("BeaconMac/\(Self.currentAppVersion())", forHTTPHeaderField: "User-Agent")

            let (downloadedTmp, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: tempDir)
                return InstallOutcome(
                    ok: false,
                    willRelaunch: false,
                    detail: "Download failed for v\(release.version) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))."
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

        onProgress(0.65, "Verifying & mounting BeaconMac v\(release.version) DMG…")

        // If running via `swift run` (not a `.app` bundle), mount/open the DMG in Finder cleanly.
        let currentBundleURL = Bundle.main.bundleURL
        guard currentBundleURL.pathExtension.lowercased() == "app" else {
            await MainActor.run {
                NSWorkspace.shared.open(localDMG)
            }
            onProgress(1.0, "Opened BeaconMac v\(release.version) DMG")
            return InstallOutcome(
                ok: true,
                willRelaunch: false,
                detail: "Downloaded and opened BeaconMac-\(release.version)-universal.dmg (running from swift run; drag BeaconMac.app to Applications)."
            )
        }

        // Running from a real `.app` bundle outside App Sandbox:
        // Mount DMG, locate BeaconMac.app, stage it, and spawn a short detached post-exit updater
        // that swaps the bundle cleanly once this PID exits and relaunches the updated app.
        let mountPoint = tempDir.appendingPathComponent("mount", isDirectory: true)
        let stagedApp = tempDir.appendingPathComponent("BeaconMac.app", isDirectory: true)

        let stageResult = await stageAppFromDMG(dmgPath: localDMG.path, mountPath: mountPoint.path, stagedAppPath: stagedApp.path)
        guard stageResult.ok else {
            try? FileManager.default.removeItem(at: tempDir)
            return InstallOutcome(ok: false, willRelaunch: false, detail: stageResult.detail)
        }

        onProgress(0.92, "Installing v\(release.version) & preparing relaunch…")

        let targetAppPath = currentBundleURL.path
        let currentPID = ProcessInfo.processInfo.processIdentifier

        // Write a minimal self-cleaning shell helper to swap the bundle after our process terminates.
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
          /usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
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
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperScriptURL.path)

            let updater = Process()
            updater.executableURL = URL(fileURLWithPath: "/bin/bash")
            updater.arguments = [helperScriptURL.path, targetAppPath, stagedApp.path, String(currentPID), tempDir.path]
            updater.standardOutput = FileHandle.nullDevice
            updater.standardError = FileHandle.nullDevice
            try updater.run()

            onProgress(1.0, "Relaunching into BeaconMac v\(release.version)…")
            return InstallOutcome(
                ok: true,
                willRelaunch: true,
                detail: "Installed BeaconMac v\(release.version). Relaunching now…"
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
                    guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
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
