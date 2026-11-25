import Foundation

public enum AIHelpProvider: String, CaseIterable, Identifiable, Sendable {
    case auto = "Auto"
    case openai = "OpenAI (ChatGPT)"
    case gemini = "Google Gemini"
    case claude = "Claude API"
    case openrouter = "OpenRouter"
    case groq = "Groq"
    case cloudflareAI = "Cloudflare Workers AI"
    case customOpenAI = "Custom AI API"
    case ollama = "Local Ollama"

    public var id: String { rawValue }
}

public struct AICloudCredentialsBundle: Sendable {
    public let openaiKey: String?
    public let openaiModel: String
    public let geminiKey: String?
    public let geminiModel: String
    public let openrouterKey: String?
    public let openrouterModel: String
    public let groqKey: String?
    public let groqModel: String
    public let cloudflareToken: String?
    public let cloudflareAccountID: String
    public let cloudflareModel: String
    public let customKey: String?
    public let customBaseURL: String
    public let customModel: String

    public init(
        openaiKey: String? = nil,
        openaiModel: String = "gpt-4o-mini",
        geminiKey: String? = nil,
        geminiModel: String = "gemini-2.5-flash",
        openrouterKey: String? = nil,
        openrouterModel: String = "openai/gpt-4o-mini",
        groqKey: String? = nil,
        groqModel: String = "llama-3.3-70b-versatile",
        cloudflareToken: String? = nil,
        cloudflareAccountID: String = "",
        cloudflareModel: String = "@cf/meta/llama-3.1-8b-instruct",
        customKey: String? = nil,
        customBaseURL: String = "",
        customModel: String = "deepseek-chat"
    ) {
        self.openaiKey = openaiKey
        self.openaiModel = openaiModel
        self.geminiKey = geminiKey
        self.geminiModel = geminiModel
        self.openrouterKey = openrouterKey
        self.openrouterModel = openrouterModel
        self.groqKey = groqKey
        self.groqModel = groqModel
        self.cloudflareToken = cloudflareToken
        self.cloudflareAccountID = cloudflareAccountID
        self.cloudflareModel = cloudflareModel
        self.customKey = customKey
        self.customBaseURL = customBaseURL
        self.customModel = customModel
    }
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
/// and server logs using any connected AI provider (ChatGPT/OpenAI, Google Gemini, Claude,
/// OpenRouter, Groq, Cloudflare Workers AI, Custom OpenAI-compatible, or Local Ollama).
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
        claudeConnected: Bool,
        cloudBundle: AICloudCredentialsBundle = AICloudCredentialsBundle()
    ) async -> AITroubleshootingResult {
        let prompt = buildPrompt(context: context, followUp: followUp)
        let trimmedClaudeKey = claudeAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedOpenAI = cloudBundle.openaiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedGemini = cloudBundle.geminiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedOpenRouter = cloudBundle.openrouterKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedGroq = cloudBundle.groqKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedCFToken = cloudBundle.cloudflareToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedCFAccount = cloudBundle.cloudflareAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomKey = cloudBundle.customKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedCustomBase = cloudBundle.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        let canUseClaude = !trimmedClaudeKey.isEmpty && (claudeConnected || provider == .claude)
        let canUseOllama = OllamaService.isValidLoopbackEndpoint(ollamaEndpoint)
            && !ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (ollamaConnected || provider == .ollama)

        switch provider {
        case .claude:
            guard !trimmedClaudeKey.isEmpty else {
                return missingKeyResult("Claude API", hint: "Connect your Claude API key in Service Cards or Settings.")
            }
            return await analyzeWithClaude(prompt: prompt, apiKey: trimmedClaudeKey, model: claudeModel)

        case .openai:
            guard !trimmedOpenAI.isEmpty else {
                return missingKeyResult("OpenAI (ChatGPT)", hint: "Connect your OpenAI API key in Global Settings & Cloud Integrations.")
            }
            return await analyzeWithOpenAICompatible(
                prompt: prompt,
                baseURL: "https://api.openai.com/v1",
                apiKey: trimmedOpenAI,
                model: cloudBundle.openaiModel.isEmpty ? "gpt-4o-mini" : cloudBundle.openaiModel,
                providerName: "ChatGPT"
            )

        case .gemini:
            guard !trimmedGemini.isEmpty else {
                return missingKeyResult("Google Gemini", hint: "Connect your Google Gemini API key in Global Settings & Cloud Integrations.")
            }
            return await analyzeWithGemini(
                prompt: prompt,
                apiKey: trimmedGemini,
                model: cloudBundle.geminiModel.isEmpty ? "gemini-2.5-flash" : cloudBundle.geminiModel
            )

        case .openrouter:
            guard !trimmedOpenRouter.isEmpty else {
                return missingKeyResult("OpenRouter", hint: "Connect your OpenRouter API key in Global Settings & Cloud Integrations.")
            }
            return await analyzeWithOpenAICompatible(
                prompt: prompt,
                baseURL: "https://openrouter.ai/api/v1",
                apiKey: trimmedOpenRouter,
                model: cloudBundle.openrouterModel.isEmpty ? "openai/gpt-4o-mini" : cloudBundle.openrouterModel,
                providerName: "OpenRouter",
                extraHeaders: ["X-Title": "BeaconMac"]
            )

        case .groq:
            guard !trimmedGroq.isEmpty else {
                return missingKeyResult("Groq", hint: "Connect your Groq API key in Global Settings & Cloud Integrations.")
            }
            return await analyzeWithOpenAICompatible(
                prompt: prompt,
                baseURL: "https://api.groq.com/openai/v1",
                apiKey: trimmedGroq,
                model: cloudBundle.groqModel.isEmpty ? "llama-3.3-70b-versatile" : cloudBundle.groqModel,
                providerName: "Groq"
            )

        case .cloudflareAI:
            guard !trimmedCFToken.isEmpty, !trimmedCFAccount.isEmpty else {
                return missingKeyResult("Cloudflare Workers AI", hint: "Enter both your Cloudflare API Token and Account ID in Global Settings & Cloud Integrations.")
            }
            return await analyzeWithCloudflareAI(
                prompt: prompt,
                apiToken: trimmedCFToken,
                accountID: trimmedCFAccount,
                model: cloudBundle.cloudflareModel.isEmpty ? "@cf/meta/llama-3.1-8b-instruct" : cloudBundle.cloudflareModel
            )

        case .customOpenAI:
            guard !trimmedCustomKey.isEmpty, !trimmedCustomBase.isEmpty else {
                return missingKeyResult("Custom AI API", hint: "Configure a Base URL and API Key under Custom OpenAI-Compatible in Global Settings.")
            }
            return await analyzeWithOpenAICompatible(
                prompt: prompt,
                baseURL: trimmedCustomBase,
                apiKey: trimmedCustomKey,
                model: cloudBundle.customModel.isEmpty ? "deepseek-chat" : cloudBundle.customModel,
                providerName: "Custom AI"
            )

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
            if !trimmedOpenAI.isEmpty {
                return await analyzeWithOpenAICompatible(
                    prompt: prompt,
                    baseURL: "https://api.openai.com/v1",
                    apiKey: trimmedOpenAI,
                    model: cloudBundle.openaiModel.isEmpty ? "gpt-4o-mini" : cloudBundle.openaiModel,
                    providerName: "ChatGPT"
                )
            }
            if !trimmedGemini.isEmpty {
                return await analyzeWithGemini(
                    prompt: prompt,
                    apiKey: trimmedGemini,
                    model: cloudBundle.geminiModel.isEmpty ? "gemini-2.5-flash" : cloudBundle.geminiModel
                )
            }
            if !trimmedOpenRouter.isEmpty {
                return await analyzeWithOpenAICompatible(
                    prompt: prompt,
                    baseURL: "https://openrouter.ai/api/v1",
                    apiKey: trimmedOpenRouter,
                    model: cloudBundle.openrouterModel.isEmpty ? "openai/gpt-4o-mini" : cloudBundle.openrouterModel,
                    providerName: "OpenRouter",
                    extraHeaders: ["X-Title": "BeaconMac"]
                )
            }
            if !trimmedGroq.isEmpty {
                return await analyzeWithOpenAICompatible(
                    prompt: prompt,
                    baseURL: "https://api.groq.com/openai/v1",
                    apiKey: trimmedGroq,
                    model: cloudBundle.groqModel.isEmpty ? "llama-3.3-70b-versatile" : cloudBundle.groqModel,
                    providerName: "Groq"
                )
            }
            if !trimmedCFToken.isEmpty && !trimmedCFAccount.isEmpty {
                return await analyzeWithCloudflareAI(
                    prompt: prompt,
                    apiToken: trimmedCFToken,
                    accountID: trimmedCFAccount,
                    model: cloudBundle.cloudflareModel.isEmpty ? "@cf/meta/llama-3.1-8b-instruct" : cloudBundle.cloudflareModel
                )
            }
            if !trimmedCustomKey.isEmpty && !trimmedCustomBase.isEmpty {
                return await analyzeWithOpenAICompatible(
                    prompt: prompt,
                    baseURL: trimmedCustomBase,
                    apiKey: trimmedCustomKey,
                    model: cloudBundle.customModel.isEmpty ? "deepseek-chat" : cloudBundle.customModel,
                    providerName: "Custom AI"
                )
            }
            if canUseOllama {
                return await analyzeWithOllama(prompt: prompt, endpoint: ollamaEndpoint, model: ollamaModel)
            }
            return AITroubleshootingResult(
                ok: false,
                providerLabel: "No AI Connected",
                answer: "",
                durationMs: 0,
                error: "Connect ChatGPT (OpenAI), Google Gemini, Claude, OpenRouter, Groq, Cloudflare Workers AI, or Local Ollama in Global Settings—or click \"Copy AI Prompt\" to paste these redacted logs into any AI assistant."
            )
        }
    }

    private func missingKeyResult(_ provider: String, hint: String) -> AITroubleshootingResult {
        AITroubleshootingResult(ok: false, providerLabel: provider, answer: "", durationMs: 0, error: hint)
    }

    private let systemInstructions = """
    You are a concise senior macOS & full-stack DevOps troubleshooter embedded inside BeaconMac.
    Analyze the provided logs and answer in clear plain text with three short sections:
    1. Root Cause: What is failing or misconfigured (or confirm if logs look healthy).
    2. Fix Steps: Exact macOS terminal commands or BeaconMac configuration changes needed.
    3. Verification: One quick command or check to confirm the issue is resolved.
    Keep the response crisp, practical, and directly grounded in the log lines shown.
    """

    private func analyzeWithOpenAICompatible(
        prompt: String,
        baseURL: String,
        apiKey: String,
        model: String,
        providerName: String,
        extraHeaders: [String: String] = [:]
    ) async -> AITroubleshootingResult {
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let start = CFAbsoluteTimeGetCurrent()
        guard let url = URL(string: "\(trimmedBase)/chat/completions") else {
            return AITroubleshootingResult(ok: false, providerLabel: providerName, answer: "", durationMs: 0, error: "Invalid \(providerName) endpoint URL.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1200,
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
                struct ErrEnvelope: Decodable {
                    struct Inner: Decodable { let message: String? }
                    let error: Inner?
                }
                let detail = (try? JSONDecoder().decode(ErrEnvelope.self, from: data))?.error?.message ?? "HTTP \(status)"
                return AITroubleshootingResult(
                    ok: false,
                    providerLabel: "\(providerName) (\(model))",
                    answer: "",
                    durationMs: elapsedMs,
                    error: "\(providerName) API error: \(SecretMasker.redact(detail))"
                )
            }

            struct ChatCompletionResp: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { let content: String? }
                    let message: Message?
                }
                let choices: [Choice]?
            }

            let decoded = try JSONDecoder().decode(ChatCompletionResp.self, from: data)
            let text = (decoded.choices?.first?.message?.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            return AITroubleshootingResult(
                ok: !text.isEmpty,
                providerLabel: "\(providerName) (\(model))",
                answer: text,
                durationMs: elapsedMs,
                error: text.isEmpty ? "\(providerName) returned an empty response." : nil
            )
        } catch {
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            return AITroubleshootingResult(
                ok: false,
                providerLabel: "\(providerName) (\(model))",
                answer: "",
                durationMs: elapsedMs,
                error: "\(providerName) request failed: \(SecretMasker.redact(error.localizedDescription))"
            )
        }
    }

    private func analyzeWithGemini(prompt: String, apiKey: String, model: String) async -> AITroubleshootingResult {
        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "gemini-2.5-flash"
            : model.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = CFAbsoluteTimeGetCurrent()

        guard let encodedModel = resolvedModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent") else {
            return AITroubleshootingResult(ok: false, providerLabel: "Gemini", answer: "", durationMs: 0, error: "Invalid Gemini model name.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemInstructions]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": prompt]]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 1400
            ]
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: req)
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200...299).contains(status) else {
                struct GeminiErr: Decodable {
                    struct Inner: Decodable { let message: String? }
                    let error: Inner?
                }
                let detail = (try? JSONDecoder().decode(GeminiErr.self, from: data))?.error?.message ?? "HTTP \(status)"
                return AITroubleshootingResult(
                    ok: false,
                    providerLabel: "Gemini (\(resolvedModel))",
                    answer: "",
                    durationMs: elapsedMs,
                    error: "Gemini API error: \(SecretMasker.redact(detail))"
                )
            }

            struct GeminiResp: Decodable {
                struct Candidate: Decodable {
                    struct Content: Decodable {
                        struct Part: Decodable { let text: String? }
                        let parts: [Part]?
                    }
                    let content: Content?
                }
                let candidates: [Candidate]?
            }

            let decoded = try JSONDecoder().decode(GeminiResp.self, from: data)
            let text = (decoded.candidates?.first?.content?.parts ?? [])
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return AITroubleshootingResult(
                ok: !text.isEmpty,
                providerLabel: "Gemini (\(resolvedModel))",
                answer: text,
                durationMs: elapsedMs,
                error: text.isEmpty ? "Gemini returned an empty response." : nil
            )
        } catch {
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            return AITroubleshootingResult(
                ok: false,
                providerLabel: "Gemini (\(resolvedModel))",
                answer: "",
                durationMs: elapsedMs,
                error: "Gemini request failed: \(SecretMasker.redact(error.localizedDescription))"
            )
        }
    }

    private func analyzeWithCloudflareAI(prompt: String, apiToken: String, accountID: String, model: String) async -> AITroubleshootingResult {
        let start = CFAbsoluteTimeGetCurrent()
        guard let encodedAccount = accountID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.cloudflare.com/client/v4/accounts/\(encodedAccount)/ai/run/\(model)") else {
            return AITroubleshootingResult(ok: false, providerLabel: "Cloudflare Workers AI", answer: "", durationMs: 0, error: "Invalid Cloudflare Account ID or model.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
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

            struct CFAIResp: Decodable {
                struct ResultBody: Decodable { let response: String? }
                struct CFErr: Decodable { let message: String? }
                let success: Bool?
                let result: ResultBody?
                let errors: [CFErr]?
            }

            let decoded = try? JSONDecoder().decode(CFAIResp.self, from: data)
            guard (200...299).contains(status), decoded?.success != false else {
                let errMsg = decoded?.errors?.first?.message ?? "HTTP \(status)"
                return AITroubleshootingResult(
                    ok: false,
                    providerLabel: "Cloudflare AI (\(model))",
                    answer: "",
                    durationMs: elapsedMs,
                    error: "Cloudflare Workers AI error: \(SecretMasker.redact(errMsg))"
                )
            }

            let text = (decoded?.result?.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return AITroubleshootingResult(
                ok: !text.isEmpty,
                providerLabel: "Cloudflare AI (\(model))",
                answer: text,
                durationMs: elapsedMs,
                error: text.isEmpty ? "Cloudflare Workers AI returned an empty response." : nil
            )
        } catch {
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            return AITroubleshootingResult(
                ok: false,
                providerLabel: "Cloudflare AI (\(model))",
                answer: "",
                durationMs: elapsedMs,
                error: "Cloudflare AI request failed: \(SecretMasker.redact(error.localizedDescription))"
            )
        }
    }

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
                error: "Local Ollama is not running at \(endpoint). Start Ollama or switch provider in AI Help."
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
