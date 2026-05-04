import Foundation

struct ImportedBook: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var originalFileName: String
    var storedFileName: String
    var encodingName: String
    var characterCount: Int
    var chapterCount: Int
    var createdAt: Date
    var lastReadOffset: Int
}

struct DecodedText {
    var text: String
    var encodingName: String
}

struct Chapter: Identifiable, Codable, Equatable {
    var id: String { "\(startOffset)-\(title)" }
    var title: String
    var startOffset: Int
    var endOffset: Int
}

enum ReaderError: LocalizedError {
    case unsupportedEncoding
    case emptyDocument
    case missingAPIKey(String)
    case invalidEndpoint
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding:
            return "无法识别 TXT 编码。请先转换为 UTF-8、UTF-16、GB18030/GBK 或 Big5。"
        case .emptyDocument:
            return "TXT 文件为空。"
        case .missingAPIKey(let provider):
            return "\(provider) API Key 为空。"
        case .invalidEndpoint:
            return "TTS endpoint URL 无效。"
        case .invalidResponse(let message):
            return "TTS 返回无法解析：\(message)"
        }
    }
}
