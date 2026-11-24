import Foundation

public struct BuiltInNodeHealthResponse: Codable, Sendable {
    public let ok: Bool
    public let pid: Int?
    public let port: Int?
    public let nodeVersion: String?
    public let activeRootSlug: String?
    public let appCount: Int?
    public let uptimeSec: Int?
}

/// Manages BeaconMac's built-in zero-dependency Node.js multi-app host registry
/// and loopback health probes (`http://127.0.0.1:<port>/_beacon/health`).
public final class BuiltInNodeServerService: Sendable {
    public let registryURL: URL

    public init(dataDirectoryURL: URL) {
        self.registryURL = dataDirectoryURL.appendingPathComponent("builtin-server-apps.json")
    }

    private struct RegistryPayload: Codable {
        struct Entry: Codable {
            let id: String
            let name: String
            let slug: String
            let mode: String
            let folderPath: String
            let proxyPort: Int?
            let spaFallback: Bool
        }

        let activeRootSlug: String?
        let apps: [Entry]
    }

    public func writeRegistry(from config: BuiltInServerConfig) {
        let activeSlug = config.mountedApps.first(where: { $0.id == config.activeRootAppID })?.slug
        let payload = RegistryPayload(
            activeRootSlug: activeSlug,
            apps: config.mountedApps.map { app in
                RegistryPayload.Entry(
                    id: app.id.uuidString,
                    name: app.name,
                    slug: app.slug,
                    mode: app.mode.rawValue,
                    folderPath: app.folderPath,
                    proxyPort: app.proxyPort,
                    spaFallback: app.spaFallback
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: registryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: registryURL, options: .atomic)
    }

    public func probeHealth(port: Int) async -> BuiltInNodeHealthResponse? {
        guard (1024...65535).contains(port),
              let url = URL(string: "http://127.0.0.1:\(port)/_beacon/health") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return try? JSONDecoder().decode(BuiltInNodeHealthResponse.self, from: data)
        } catch {
            return nil
        }
    }

    public static func makeSlug(from rawName: String, existingSlugs: Set<String>) -> String {
        let lowered = rawName.lowercased()
        let allowed = CharacterSet.alphanumerics
        var base = ""
        var prevDash = false
        for scalar in lowered.unicodeScalars {
            if allowed.contains(scalar) {
                base.unicodeScalars.append(scalar)
                prevDash = false
            } else if !prevDash && !base.isEmpty {
                base.append("-")
                prevDash = true
            }
        }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.isEmpty {
            base = "app"
        }
        if !existingSlugs.contains(base) {
            return base
        }
        var suffix = 2
        while existingSlugs.contains("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }

    public static func describeServeRoot(for folderPath: String) -> String {
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No folder" }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: trimmed, isDirectory: &isDir), isDir.boolValue else {
            return "Folder missing"
        }
        let baseURL = URL(fileURLWithPath: trimmed, isDirectory: true)
        for sub in ["dist", "build", "out", "public"] {
            let indexFile = baseURL.appendingPathComponent(sub).appendingPathComponent("index.html")
            if fm.fileExists(atPath: indexFile.path) {
                return "\(sub)/ (index.html)"
            }
        }
        let rootIndex = baseURL.appendingPathComponent("index.html")
        if fm.fileExists(atPath: rootIndex.path) {
            return "root (index.html)"
        }
        return "root folder"
    }
}
