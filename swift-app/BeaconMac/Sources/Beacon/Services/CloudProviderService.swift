import Foundation

public struct CloudProviderProbeResult: Sendable {
    public let connected: Bool
    public let httpStatus: Int?
    public let latencyMs: Int
    public let accountLabel: String?
    public let models: [String]
    public let error: String?
}

/// Zero-token-cost connectivity & credential verifier for Cloud AI APIs (ChatGPT/OpenAI,
/// Google Gemini, OpenRouter, Groq, Custom OpenAI-compatible) and Cloud platforms
/// (Cloudflare API & Workers AI, Vercel, Supabase).
public final class CloudProviderService: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 15.0
        self.session = URLSession(configuration: config)
    }

    public func probe(
        kind: CloudProviderKind,
        apiKey: String,
        baseURL: String = "",
        accountID: String = ""
    ) async -> CloudProviderProbeResult {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.count >= 8, !trimmedKey.contains(where: \.isWhitespace) else {
            return CloudProviderProbeResult(
                connected: false,
                httpStatus: nil,
                latencyMs: 0,
                accountLabel: nil,
                models: [],
                error: "Paste a valid \(kind.displayName) API key or token."
            )
        }

        switch kind {
        case .openai:
            return await probeOpenAICompatible(
                baseURLString: "https://api.openai.com/v1",
                apiKey: trimmedKey,
                providerLabel: "OpenAI",
                extraHeaders: [:],
                preferredPrefixes: ["gpt-4.1", "gpt-4o", "o3", "o4", "gpt-4"]
            )
        case .openrouter:
            return await probeOpenAICompatible(
                baseURLString: "https://openrouter.ai/api/v1",
                apiKey: trimmedKey,
                providerLabel: "OpenRouter",
                extraHeaders: ["X-Title": "BeaconMac"],
                preferredPrefixes: ["openai/gpt-4o", "anthropic/claude", "google/gemini"]
            )
        case .groq:
            return await probeOpenAICompatible(
                baseURLString: "https://api.groq.com/openai/v1",
                apiKey: trimmedKey,
                providerLabel: "Groq",
                extraHeaders: [:],
                preferredPrefixes: ["llama-3.3", "llama-3.1", "mixtral", "qwen"]
            )
        case .customOpenAI:
            let resolvedBase = sanitizeHTTPSBaseURL(baseURL)
            guard let resolvedBase else {
                return CloudProviderProbeResult(
                    connected: false,
                    httpStatus: nil,
                    latencyMs: 0,
                    accountLabel: nil,
                    models: [],
                    error: "Enter a valid HTTPS Base URL (e.g. https://api.deepseek.com/v1 or https://api.x.ai/v1)."
                )
            }
            return await probeOpenAICompatible(
                baseURLString: resolvedBase,
                apiKey: trimmedKey,
                providerLabel: "Custom AI",
                extraHeaders: [:],
                preferredPrefixes: []
            )
        case .gemini:
            return await probeGemini(apiKey: trimmedKey)
        case .cloudflare:
            return await probeCloudflare(apiToken: trimmedKey, accountID: accountID.trimmingCharacters(in: .whitespacesAndNewlines))
        case .vercel:
            return await probeVercel(apiToken: trimmedKey)
        case .supabase:
            return await probeSupabase(projectURL: baseURL, apiKey: trimmedKey)
        }
    }

    private func sanitizeHTTPSBaseURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            return nil
        }
        guard scheme == "https" || (scheme == "http" && (host == "localhost" || host == "127.0.0.1")) else {
            return nil
        }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    private func probeOpenAICompatible(
        baseURLString: String,
        apiKey: String,
        providerLabel: String,
        extraHeaders: [String: String],
        preferredPrefixes: [String]
    ) async -> CloudProviderProbeResult {
        guard let url = URL(string: "\(baseURLString)/models") else {
            return CloudProviderProbeResult(
                connected: false, httpStatus: nil, latencyMs: 0, accountLabel: nil, models: [],
                error: "Invalid \(providerLabel) endpoint URL."
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }

        do {
            let (data, response) = try await session.data(for: req)
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200...299).contains(status) else {
                let errDetail = extractGenericErrorMessage(from: data) ?? "HTTP \(status)"
                return CloudProviderProbeResult(
                    connected: false,
                    httpStatus: status,
                    latencyMs: latencyMs,
                    accountLabel: nil,
                    models: [],
                    error: "\(providerLabel) error: \(SecretMasker.redact(errDetail))"
                )
            }

            struct OpenAIModelsResp: Decodable {
                struct Item: Decodable { let id: String }
                let data: [Item]?
            }

            let decoded = try? JSONDecoder().decode(OpenAIModelsResp.self, from: data)
            var ids = (decoded?.data ?? []).map(\.id)
            if !preferredPrefixes.isEmpty {
                ids.sort { lhs, rhs in
                    let lScore = preferredPrefixes.firstIndex { lhs.hasPrefix($0) } ?? preferredPrefixes.count
                    let rScore = preferredPrefixes.firstIndex { rhs.hasPrefix($0) } ?? preferredPrefixes.count
                    if lScore != rScore { return lScore < rScore }
                    return lhs < rhs
                }
            }
            let capped = Array(ids.prefix(40))

            return CloudProviderProbeResult(
                connected: true,
                httpStatus: status,
                latencyMs: latencyMs,
                accountLabel: capped.isEmpty ? "Verified" : "\(ids.count) models",
                models: capped,
                error: nil
            )
        } catch {
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            return CloudProviderProbeResult(
                connected: false, httpStatus: nil, latencyMs: latencyMs, accountLabel: nil, models: [],
                error: "Network error: \(SecretMasker.redact(error.localizedDescription))"
            )
        }
    }

    private func probeGemini(apiKey: String) async -> CloudProviderProbeResult {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=50") else {
            return CloudProviderProbeResult(
                connected: false, httpStatus: nil, latencyMs: 0, accountLabel: nil, models: [],
                error: "Invalid Gemini API endpoint."
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: req)
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200...299).contains(status) else {
                let errDetail = extractGenericErrorMessage(from: data) ?? "HTTP \(status)"
                return CloudProviderProbeResult(
                    connected: false,
                    httpStatus: status,
                    latencyMs: latencyMs,
                    accountLabel: nil,
                    models: [],
                    error: "Gemini API error: \(SecretMasker.redact(errDetail))"
                )
            }

            struct GeminiModelsResp: Decodable {
                struct Item: Decodable {
                    let name: String
                    let supportedGenerationMethods: [String]?
                }
                let models: [Item]?
            }

            let decoded = try? JSONDecoder().decode(GeminiModelsResp.self, from: data)
            let generative = (decoded?.models ?? [])
                .filter { ($0.supportedGenerationMethods ?? []).contains("generateContent") }
                .map { item -> String in
                    item.name.hasPrefix("models/") ? String(item.name.dropFirst("models/".count)) : item.name
                }
                .sorted { lhs, rhs in
                    let rank: (String) -> Int = { m in
                        if m.contains("gemini-2.5-flash") { return 0 }
                        if m.contains("gemini-2.5-pro") { return 1 }
                        if m.contains("gemini-2.0-flash") { return 2 }
                        if m.contains("gemini-1.5-pro") { return 3 }
                        return 4
                    }
                    let lr = rank(lhs), rr = rank(rhs)
                    return lr != rr ? lr < rr : lhs < rhs
                }

            return CloudProviderProbeResult(
                connected: true,
                httpStatus: status,
                latencyMs: latencyMs,
                accountLabel: "\(generative.count) Gemini models",
                models: Array(generative.prefix(30)),
                error: nil
            )
        } catch {
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            return CloudProviderProbeResult(
                connected: false, httpStatus: nil, latencyMs: latencyMs, accountLabel: nil, models: [],
                error: "Network error: \(SecretMasker.redact(error.localizedDescription))"
            )
        }
    }

    private func probeCloudflare(apiToken: String, accountID: String) async -> CloudProviderProbeResult {
        guard let url = URL(string: "https://api.cloudflare.com/client/v4/user/tokens/verify") else {
            return CloudProviderProbeResult(
                connected: false, httpStatus: nil, latencyMs: 0, accountLabel: nil, models: [],
                error: "Invalid Cloudflare API URL."
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: req)
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            struct CFVerifyResp: Decodable {
                struct ResultObj: Decodable { let status: String?; let id: String? }
                struct CFErr: Decodable { let message: String? }
                let success: Bool?
                let result: ResultObj?
                let errors: [CFErr]?
            }

            let decoded = try? JSONDecoder().decode(CFVerifyResp.self, from: data)
            guard (200...299).contains(status), decoded?.success == true else {
                let errMsg = decoded?.errors?.first?.message ?? "HTTP \(status)"
                return CloudProviderProbeResult(
                    connected: false,
                    httpStatus: status,
                    latencyMs: latencyMs,
                    accountLabel: nil,
                    models: [],
                    error: "Cloudflare error: \(SecretMasker.redact(errMsg))"
                )
            }

            let tokenState = decoded?.result?.status ?? "active"
            let label = accountID.isEmpty
                ? "Token \(tokenState) · add Account ID for Workers AI"
                : "Token \(tokenState) · Workers AI ready"
            let workersAIModels = [
                "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
                "@cf/meta/llama-3.1-8b-instruct",
                "@cf/qwen/qwen2.5-coder-32b-instruct",
                "@cf/mistral/mistral-7b-instruct-v0.2"
            ]

            return CloudProviderProbeResult(
                connected: true,
                httpStatus: status,
                latencyMs: latencyMs,
                accountLabel: label,
                models: workersAIModels,
                error: nil
            )
        } catch {
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            return CloudProviderProbeResult(
                connected: false, httpStatus: nil, latencyMs: latencyMs, accountLabel: nil, models: [],
                error: "Network error: \(SecretMasker.redact(error.localizedDescription))"
            )
        }
    }

    private func probeVercel(apiToken: String) async -> CloudProviderProbeResult {
        guard let url = URL(string: "https://api.vercel.com/v2/user") else {
            return CloudProviderProbeResult(
                connected: false, httpStatus: nil, latencyMs: 0, accountLabel: nil, models: [],
                error: "Invalid Vercel API URL."
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: req)
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200...299).contains(status) else {
                let detail = extractGenericErrorMessage(from: data) ?? "HTTP \(status)"
                return CloudProviderProbeResult(
                    connected: false, httpStatus: status, latencyMs: latencyMs, accountLabel: nil, models: [],
                    error: "Vercel error: \(SecretMasker.redact(detail))"
                )
            }

            struct VercelUserResp: Decodable {
                struct User: Decodable { let username: String?; let email: String? }
                let user: User?
            }

            let decoded = try? JSONDecoder().decode(VercelUserResp.self, from: data)
            let label = decoded?.user?.username.map { "@\($0)" } ?? decoded?.user?.email ?? "Verified"
            return CloudProviderProbeResult(
                connected: true, httpStatus: status, latencyMs: latencyMs, accountLabel: label, models: [], error: nil
            )
        } catch {
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            return CloudProviderProbeResult(
                connected: false, httpStatus: nil, latencyMs: latencyMs, accountLabel: nil, models: [],
                error: "Network error: \(SecretMasker.redact(error.localizedDescription))"
            )
        }
    }

    private func probeSupabase(projectURL: String, apiKey: String) async -> CloudProviderProbeResult {
        guard let base = sanitizeHTTPSBaseURL(projectURL), let url = URL(string: "\(base)/rest/v1/") else {
            return CloudProviderProbeResult(
                connected: false, httpStatus: nil, latencyMs: 0, accountLabel: nil, models: [],
                error: "Enter your Supabase Project URL (e.g. https://xyz.supabase.co)."
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: req)
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200...299).contains(status) else {
                let detail = extractGenericErrorMessage(from: data) ?? "HTTP \(status)"
                return CloudProviderProbeResult(
                    connected: false, httpStatus: status, latencyMs: latencyMs, accountLabel: nil, models: [],
                    error: "Supabase error: \(SecretMasker.redact(detail))"
                )
            }

            let hostLabel = URL(string: base)?.host ?? "Supabase"
            return CloudProviderProbeResult(
                connected: true, httpStatus: status, latencyMs: latencyMs, accountLabel: hostLabel, models: [], error: nil
            )
        } catch {
            let latencyMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            return CloudProviderProbeResult(
                connected: false, httpStatus: nil, latencyMs: latencyMs, accountLabel: nil, models: [],
                error: "Network error: \(SecretMasker.redact(error.localizedDescription))"
            )
        }
    }

    private func extractGenericErrorMessage(from data: Data) -> String? {
        struct NestedErr: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
            let message: String?
        }
        if let decoded = try? JSONDecoder().decode(NestedErr.self, from: data) {
            if let msg = decoded.error?.message, !msg.isEmpty { return msg }
            if let msg = decoded.message, !msg.isEmpty { return msg }
        }
        return nil
    }
}
