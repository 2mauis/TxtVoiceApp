import Foundation

enum RemoteTTSClient {
    static func synthesize(text: String, settings: TTSSettings) async throws -> Data {
        switch settings.engine {
        case .embeddedGemma4:
            throw ReaderError.invalidResponse("已弃用的文本模型不能生成音频。")
        case .gemma4Local:
            return try await synthesizeOpenAICompatible(
                text: text,
                endpoint: URL(string: settings.gemma4EndpointURL),
                apiKey: settings.gemma4APIKey,
                model: settings.gemma4Model,
                voice: settings.gemma4Voice,
                instructions: settings.gemma4Instructions,
                providerName: "本地 TTS Endpoint",
                requiresAPIKey: false
            )
        case .openAICompatible:
            return try await synthesizeOpenAICompatible(
                text: text,
                endpoint: URL(string: "https://api.openai.com/v1/audio/speech"),
                apiKey: settings.openAIAPIKey,
                model: settings.openAIModel,
                voice: settings.openAIVoice,
                instructions: settings.openAIInstructions,
                providerName: "OpenAI",
                requiresAPIKey: true
            )
        case .localCommand:
            return try await LocalTTSCommandClient.synthesize(text: text, settings: settings)
        case .localKokoro, .localChatterbox:
            return try await LocalTTSCommandClient.synthesize(text: text, settings: settings)
        case .kokoroCoreML:
            return try await KokoroCoreMLDirectClient.synthesize(text: text, settings: settings)
        case .customEndpoint:
            return try await synthesizeOpenAICompatible(
                text: text,
                endpoint: URL(string: settings.customEndpointURL),
                apiKey: settings.customAPIKey,
                model: settings.customModel,
                voice: settings.customVoice,
                instructions: nil,
                providerName: "自定义 TTS",
                requiresAPIKey: false
            )
        case .gemini:
            return try await synthesizeGemini(text: text, settings: settings)
        case .iosSystem:
            throw ReaderError.invalidResponse("macOS 本地语音不需要远程 TTS 请求。")
        }
    }

    private static func synthesizeOpenAICompatible(
        text: String,
        endpoint: URL?,
        apiKey: String,
        model: String,
        voice: String,
        instructions: String?,
        providerName: String,
        requiresAPIKey: Bool
    ) async throws -> Data {
        guard let endpoint else { throw ReaderError.invalidEndpoint }
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requiresAPIKey || !trimmedAPIKey.isEmpty else {
            throw ReaderError.missingAPIKey(providerName)
        }
        AppLogger.info(
            "\(providerName) request endpoint=\(endpoint.absoluteString) model=\(model) voice=\(voice) textLength=\(text.count)",
            category: "remote"
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }

        var payload: [String: Any] = [
            "model": model.isEmpty ? "gpt-4o-mini-tts" : model,
            "input": text,
            "voice": voice.isEmpty ? "coral" : voice,
            "response_format": "mp3"
        ]

        if let instructions, !instructions.isEmpty {
            payload["instructions"] = instructions
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            AppLogger.info("\(providerName) response status=\(http.statusCode) bytes=\(data.count)", category: "remote")
        }
        try validateHTTP(response: response, data: data)
        return data
    }

    private static func synthesizeGemini(text: String, settings: TTSSettings) async throws -> Data {
        guard !settings.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReaderError.missingAPIKey("Gemini")
        }

        let model = settings.geminiModel.isEmpty ? "gemini-2.5-flash-preview-tts" : settings.geminiModel
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw ReaderError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(settings.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")

        let prompt = [settings.geminiStylePrompt, text]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": [
                            "voiceName": settings.geminiVoice.isEmpty ? "Kore" : settings.geminiVoice
                        ]
                    ]
                ]
            ],
            "model": model
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        AppLogger.info("Gemini request model=\(model) voice=\(settings.geminiVoice) textLength=\(text.count)", category: "remote")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            AppLogger.info("Gemini response status=\(http.statusCode) bytes=\(data.count)", category: "remote")
        }
        try validateHTTP(response: response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let inlineData = parts.first?["inlineData"] as? [String: Any],
            let base64 = inlineData["data"] as? String,
            let pcm = Data(base64Encoded: base64)
        else {
            throw ReaderError.invalidResponse("Gemini 响应里没有 inlineData.data。")
        }

        return WAVWriter.wrapPCM16Mono24kHz(pcm)
    }

    private static func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? "HTTP \(http.statusCode)"
            AppLogger.error("HTTP error status=\(http.statusCode) body=\(AppLogger.snippet(body))", category: "remote")
            throw ReaderError.invalidResponse(body)
        }
    }
}
