import Foundation

public enum AIHelpProvider: String, CaseIterable, Identifiable, Sendable {
    case auto = "Auto"
    case ollama = "Local Ollama"
    case claude = "Claude API"

    public var id: String { rawValue }
}

public struct AILogContext: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let logText: String
    public let appName: String?

    public init(id: UUID = UUID(), title: String, logText: String, appName: String? = nil) {
        self.id = id
        self.title = title
        self.logText = SecretMasker.redact(logText)
        self.appName = appName
    }
}

public struct AITroubleshootingResult: Sendable {
    public let ok: Bool
    public let providerLabel: String
    public let answer: String
    public let durationMs: Int
    public let error: String?
}

/// Native log troubleshooting client that analyzes redacted BeaconMac terminal, activity,
/// and server logs using the user's already-configured Local Ollama daemon or Claude API key.
public final class LogTroubleshootingService: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90.0
        config.timeoutIntervalForResource = 120.0
        config.connectionProxyDictionary = [:]
        self.session = URLSession(configuration: config)
    }

    public func buildPrompt(context: AILogContext, followUp: String? = nil) -> String {
        let redacted = SecretMasker.redact(context.logText)
        let clipped = redacted.count > 12_000
            ? "...(truncated earlier lines)...\n" + String(redacted.suffix(12_000))
            : redacted

        var sections: [String] = []
        sections.append("Context: BeaconMac macOS app monitoring/deployment logs (\(context.title))")
        if let appName = context.appName, !appName.isEmpty {
            sections.append("Target App: \(appName)")
        }
        if let q = followUp?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            sections.append("User Question: \(q)")
        } else {
            sections.append("Task: Diagnose any errors, warnings, or misconfigurations in the logs below and provide concrete, copy-ready macOS fix steps.")
        }
        sections.append("""
        Logs:
        ```
        \(clipped)
        ```
        """)
        return sections.joined(separator: "\n\n")
    }

    public func analyze(
        context: AILogContext,
        followUp: String?,
        provider: AIHelpProvider,
        claudeAPIKey: String?,
        claudeModel: String,
        ollamaEndpoint: String,
        ollamaModel: String,
        ollamaConnected: Bool,
        claudeConnected: Bool
    ) async -> AITroubleshootingResult {
        let prompt = buildPrompt(context: context, followUp: followUp)
        let trimmedClaudeKey = claudeAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let canUseClaude = !trimmedClaudeKey.isEmpty && (claudeConnected || provider == .claude)
        let canUseOllama = OllamaService.isValidLoopbackEndpoint(ollamaEndpoint)
            && !ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (ollamaConnected || provider == .ollama)

        switch provider {
        case .claude:
            guard !trimmedClaudeKey.isEmpty else {
                return AITroubleshootingResult(
                    ok: false,
                    providerLabel: "Claude API",
                    answer: "",
                    durationMs: 0,
                    error: "No Claude API key configured. Paste your Claude API key in the Claude API card above, or switch to Local Ollama."
                )
            }
            return await analyzeWithClaude(prompt: prompt, apiKey: trimmedClaudeKey, model: claudeModel)

        case .ollama:
            guard OllamaService.isValidLoopbackEndpoint(ollamaEndpoint) else {
                return AITroubleshootingResult(
                    ok: false,
                    providerLabel: "Local Ollama",
                    answer: "",
                    durationMs: 0,
                    error: "Invalid Ollama loopback endpoint (\(ollamaEndpoint))."
                )
            }
            return await analyzeWithOllama(prompt: prompt, endpoint: ollamaEndpoint, model: ollamaModel)

        case .auto:
            if canUseClaude {
                return await analyzeWithClaude(prompt: prompt, apiKey: trimmedClaudeKey, model: claudeModel)
            }
            if canUseOllama {
                return await analyzeWithOllama(prompt: prompt, endpoint: ollamaEndpoint, model: ollamaModel)
            }
            return AITroubleshootingResult(
                ok: false,
                providerLabel: "No AI Connected",
                answer: "",
                durationMs: 0,
                error: "Connect a Claude API key or start Local Ollama (127.0.0.1:11434) in the cards above to run live AI troubleshooting—or click \"Copy AI Prompt\" to paste these redacted logs into any AI assistant."
            )
        }
    }

    private let systemInstructions = """
    You are a concise senior macOS & full-stack DevOps troubleshooter embedded inside BeaconMac.
    Analyze the provided logs and answer in clear plain text with three short sections:
    1. Root Cause: What is failing or misconfigured (or confirm if logs look healthy).
    2. Fix Steps: Exact macOS terminal commands or BeaconMac configuration changes needed.
    3. Verification: One quick command or check to confirm the issue is resolved.
    Keep the response crisp, practical, and directly grounded in the log lines shown.
    """

    private func analyzeWithClaude(prompt: String, apiKey: String, model: String) async -> AITroubleshootingResult {
        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "claude-sonnet-4-5"
            : model.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = CFAbsoluteTimeGetCurrent()

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return AITroubleshootingResult(ok: false, providerLabel: "Claude API", answer: "", durationMs: 0, error: "Invalid Claude API URL.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": resolvedModel,
            "max_tokens": 1200,
            "system": systemInstructions,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: req)
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200...299).contains(status) else {
                struct ErrEnvelope: Decodable {
                    struct Inner: Decodable { let message: String? }
                    let error: Inner?
                }
                let detail = (try? JSONDecoder().decode(ErrEnvelope.self, from: data))?.error?.message
                    ?? "HTTP \(status)"
                return AITroubleshootingResult(
                    ok: false,
                    providerLabel: "Claude (\(resolvedModel))",
                    answer: "",
                    durationMs: elapsedMs,
                    error: "Claude API error: \(SecretMasker.redact(detail))"
                )
            }

            struct ClaudeMessageResponse: Decodable {
                struct Block: Decodable {
                    let type: String?
                    let text: String?
                }
                let content: [Block]?
            }

            let decoded = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
            let text = (decoded.content ?? [])
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return AITroubleshootingResult(
                ok: !text.isEmpty,
                providerLabel: "Claude (\(resolvedModel))",
                answer: text,
                durationMs: elapsedMs,
                error: text.isEmpty ? "Claude returned an empty response." : nil
            )
        } catch {
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            return AITroubleshootingResult(
                ok: false,
                providerLabel: "Claude (\(resolvedModel))",
                answer: "",
                durationMs: elapsedMs,
                error: "Claude request failed: \(SecretMasker.redact(error.localizedDescription))"
            )
        }
    }

    private func analyzeWithOllama(prompt: String, endpoint: String, model: String) async -> AITroubleshootingResult {
        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "llama3.2"
            : model.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = CFAbsoluteTimeGetCurrent()

        guard let url = URL(string: "\(endpoint)/api/chat") else {
            return AITroubleshootingResult(ok: false, providerLabel: "Ollama", answer: "", durationMs: 0, error: "Invalid Ollama endpoint.")
        }

        let host = url.host?.lowercased() ?? "127.0.0.1"
        let port = url.port ?? 11434
        let reachable = await Task.detached(priority: .utility) {
            LocalProcessService.isLoopbackPortListening(host: host, port: port)
        }.value

        guard reachable else {
            return AITroubleshootingResult(
                ok: false,
                providerLabel: "Ollama (\(resolvedModel))",
                answer: "",
                durationMs: 0,
                error: "Local Ollama is not running at \(endpoint). Start Ollama or switch provider to Claude API."
            )
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": resolvedModel,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemInstructions],
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: req)
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200...299).contains(status) else {
                struct OllamaErr: Decodable { let error: String? }
                let msg = (try? JSONDecoder().decode(OllamaErr.self, from: data))?.error ?? "HTTP \(status)"
                return AITroubleshootingResult(
                    ok: false,
                    providerLabel: "Ollama (\(resolvedModel))",
                    answer: "",
                    durationMs: elapsedMs,
                    error: "Ollama error: \(SecretMasker.redact(msg))"
                )
            }

            struct OllamaChatResponse: Decodable {
                struct Msg: Decodable { let content: String? }
                let message: Msg?
            }

            let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
            let text = (decoded.message?.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            return AITroubleshootingResult(
                ok: !text.isEmpty,
                providerLabel: "Ollama (\(resolvedModel))",
                answer: text,
                durationMs: elapsedMs,
                error: text.isEmpty ? "Ollama returned an empty response." : nil
            )
        } catch {
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            return AITroubleshootingResult(
                ok: false,
                providerLabel: "Ollama (\(resolvedModel))",
                answer: "",
                durationMs: elapsedMs,
                error: "Ollama request failed: \(SecretMasker.redact(error.localizedDescription))"
            )
        }
    }
}
