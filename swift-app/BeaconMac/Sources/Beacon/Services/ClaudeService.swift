import Foundation

public struct ClaudeProbeResult: Sendable {
    public let connected: Bool
    public let httpStatus: Int?
    public let latencyMs: Int
    public let models: [ClaudeModelInfo]
    public let error: String?
}

/// Zero-token-cost Anthropic Claude API health checker using GET /v1/models.
public final class ClaudeService: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8.0
        self.session = URLSession(configuration: config)
    }

    public func probeHealth(apiKey: String) async -> ClaudeProbeResult {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16, !trimmed.contains(where: \.isWhitespace) else {
            return ClaudeProbeResult(
                connected: false,
                httpStatus: nil,
                latencyMs: 0,
                models: [],
                error: "Paste a valid Anthropic Claude API key (starts with sk-ant-...)."
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=30")!)
        req.httpMethod = "GET"
        req.setValue(trimmed, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: req)
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200...299).contains(status) else {
                struct AnthropicErr: Decodable {
                    struct Inner: Decodable { let message: String? }
                    let error: Inner?
                }
                let errMsg = (try? JSONDecoder().decode(AnthropicErr.self, from: data))?.error?.message
                let detail = errMsg.map { "HTTP \(status): \(SecretMasker.redact($0))" } ?? "HTTP \(status)"
                return ClaudeProbeResult(
                    connected: false,
                    httpStatus: status,
                    latencyMs: latencyMs,
                    models: [],
                    error: detail
                )
            }

            struct ModelsResponse: Decodable {
                struct Item: Decodable {
                    let id: String
                    let display_name: String?
                    let created_at: String?
                }
                let data: [Item]?
            }

            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            let models = (decoded.data ?? []).map {
                ClaudeModelInfo(
                    id: $0.id,
                    displayName: $0.display_name ?? $0.id,
                    createdAt: $0.created_at
                )
            }

            return ClaudeProbeResult(
                connected: true,
                httpStatus: status,
                latencyMs: latencyMs,
                models: models,
                error: nil
            )
        } catch {
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            return ClaudeProbeResult(
                connected: false,
                httpStatus: nil,
                latencyMs: latencyMs,
                models: [],
                error: "Network error: \(SecretMasker.redact(error.localizedDescription))"
            )
        }
    }
}
