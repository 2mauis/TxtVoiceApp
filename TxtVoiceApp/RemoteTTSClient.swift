import Foundation

enum RemoteTTSClient {
    static func synthesize(text: String, settings: TTSSettings) async throws -> Data {
        switch settings.engine {
        case .localKokoro:
            return try await LocalTTSCommandClient.synthesize(text: text, settings: settings)
        case .iosSystem:
            throw ReaderError.invalidResponse("macOS 本地语音不需要本地 TTS 后端请求。")
        }
    }

    static func synthesizeToFile(
        text: String,
        settings: TTSSettings,
        outputDirectory: URL,
        fileName: String
    ) async throws -> URL {
        switch settings.engine {
        case .localKokoro:
            return try await LocalTTSCommandClient.synthesizeToFile(
                text: text,
                settings: settings,
                outputDirectory: outputDirectory,
                fileName: fileName
            )
        case .iosSystem:
            throw ReaderError.invalidResponse("macOS 本地语音不需要本地 TTS 后端请求。")
        }
    }
}
