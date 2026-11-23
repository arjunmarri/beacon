import Foundation

public struct OllamaHealthResult: Sendable {
    public let connected: Bool
    public let latencyMs: Int?
    public let models: [OllamaModelInfo]
    public let activeModel: String
    public let vramUsedGB: Double
    public let error: String?
}

/// Loopback-restricted native client for local Ollama daemon (127.0.0.1:11434).
public final class OllamaService: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        self.session = URLSession(configuration: config)
    }

    public static func isValidLoopbackEndpoint(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "http",
              let host = url.host?.lowercased(),
              (host == "127.0.0.1" || host == "localhost") else {
            return false
        }
        let port = url.port ?? 80
        return (11434...11440).contains(port)
    }

    public func probeHealth(endpoint: String, preferredModel: String) async -> OllamaHealthResult {
        guard Self.isValidLoopbackEndpoint(endpoint),
              let tagsURL = URL(string: "\(endpoint)/api/tags") else {
            return OllamaHealthResult(
                connected: false,
                latencyMs: nil,
                models: [],
                activeModel: preferredModel,
                vramUsedGB: 0,
                error: "Only loopback http://127.0.0.1:11434–11440 endpoints are allowed."
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await session.data(from: tagsURL)
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                return OllamaHealthResult(
                    connected: false,
                    latencyMs: latencyMs,
                    models: [],
                    activeModel: preferredModel,
                    vramUsedGB: 0,
                    error: "Ollama returned HTTP \(code)."
                )
            }

            struct TagsResponse: Decodable {
                struct ModelItem: Decodable {
                    struct Details: Decodable {
                        let parameter_size: String?
                        let quantization_level: String?
                    }
                    let name: String
                    let size: Int64?
                    let details: Details?
                }
                let models: [ModelItem]?
            }

            let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
            let models = (decoded.models ?? []).map {
                OllamaModelInfo(
                    name: $0.name,
                    parameterSize: $0.details?.parameter_size ?? "n/a",
                    quantization: $0.details?.quantization_level ?? "Q4",
                    sizeGB: Double($0.size ?? 0) / 1_000_000_000.0
                )
            }

            var runningModel = preferredModel
            var vramGB = models.first?.sizeGB ?? 0

            if let psURL = URL(string: "\(endpoint)/api/ps"),
               let (psData, psResp) = try? await session.data(from: psURL),
               let psHTTP = psResp as? HTTPURLResponse, (200...299).contains(psHTTP.statusCode) {
                struct PSResponse: Decodable {
                    struct Running: Decodable {
                        let name: String
                        let size_vram: Int64?
                    }
                    let models: [Running]?
                }
                if let ps = try? JSONDecoder().decode(PSResponse.self, from: psData),
                   let active = ps.models?.first {
                    runningModel = active.name
                    vramGB = Double(active.size_vram ?? 0) / 1_000_000_000.0
                }
            }

            let resolvedModel = models.contains(where: { $0.name == runningModel })
                ? runningModel
                : (models.first?.name ?? preferredModel)

            return OllamaHealthResult(
                connected: true,
                latencyMs: latencyMs,
                models: models,
                activeModel: resolvedModel,
                vramUsedGB: vramGB,
                error: nil
            )
        } catch {
            return OllamaHealthResult(
                connected: false,
                latencyMs: nil,
                models: [],
                activeModel: preferredModel,
                vramUsedGB: 0,
                error: "Ollama daemon not reachable at \(endpoint)."
            )
        }
    }

    public func switchModel(endpoint: String, model: String) async throws -> Int {
        guard Self.isValidLoopbackEndpoint(endpoint),
              let url = URL(string: "\(endpoint)/api/generate") else {
            throw NSError(domain: "BeaconOllama", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Ollama endpoint."])
        }

        let start = CFAbsoluteTimeGetCurrent()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["model": model, "prompt": "", "keep_alive": "10m"]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await session.data(for: req)
        let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "BeaconOllama", code: code, userInfo: [NSLocalizedDescriptionKey: "Failed to load \(model) (HTTP \(code))."])
        }
        return latencyMs
    }
}
