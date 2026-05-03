import Foundation

enum RemoteTTSClient {
    static func synthesize(text: String, settings: TTSSettings) async throws -> Data {
        switch settings.engine {
        case .localKokoro, .localChatterbox:
            return try await LocalTTSCommandClient.synthesize(text: text, settings: settings)
        case .iosSystem:
            throw ReaderError.invalidResponse("macOS 本地语音不需要本地 TTS 后端请求。")
        }
    }
}
