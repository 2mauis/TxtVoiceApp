import Foundation

struct SpeechChunk: Identifiable, Equatable {
    var id: Int { startOffset }
    var text: String
    var startOffset: Int
    var endOffset: Int
}

enum TextChunker {
    static func chunks(
        from text: String,
        startingAt offset: Int = 0,
        endingAt endOffset: Int? = nil,
        maxLength: Int = 900
    ) -> [SpeechChunk] {
        let textLength = text.utf16.count
        let safeOffset = max(0, min(offset, textLength))
        let safeEndOffset = max(safeOffset, min(endOffset ?? textLength, textLength))
        let startIndex = String.Index(utf16Offset: safeOffset, in: text)
        let endIndex = String.Index(utf16Offset: safeEndOffset, in: text)
        let selectedText = String(text[startIndex..<endIndex])
        let paragraphs = selectedText.components(separatedBy: .newlines)
        var chunks: [SpeechChunk] = []
        var buffer = ""
        var bufferStart = safeOffset
        var cursor = safeOffset

        func flush(upTo endOffset: Int) {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                buffer = ""
                bufferStart = endOffset
                return
            }

            let leadingTrim = buffer.utf16.count - buffer.trimmingCharacters(in: .whitespaces).utf16.count
            chunks.append(SpeechChunk(
                text: trimmed,
                startOffset: bufferStart + max(0, leadingTrim),
                endOffset: endOffset
            ))
            buffer = ""
            bufferStart = endOffset
        }

        for paragraph in paragraphs {
            let candidate = paragraph + "\n"
            if buffer.isEmpty {
                bufferStart = cursor
            }

            if candidate.count > maxLength {
                flush(upTo: cursor)
                splitLong(candidate, startOffset: cursor, maxLength: maxLength).forEach { chunks.append($0) }
            } else if buffer.count + candidate.count > maxLength {
                flush(upTo: cursor)
                bufferStart = cursor
                buffer = candidate
            } else {
                buffer += candidate
            }

            cursor += candidate.utf16.count
        }

        flush(upTo: safeEndOffset)
        return chunks
    }

    private static func splitLong(_ text: String, startOffset: Int, maxLength: Int) -> [SpeechChunk] {
        var result: [SpeechChunk] = []
        var cursor = text.startIndex
        var offset = startOffset

        while cursor < text.endIndex {
            let end = text.index(cursor, offsetBy: maxLength, limitedBy: text.endIndex) ?? text.endIndex
            let raw = String(text[cursor..<end])
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result.append(SpeechChunk(text: trimmed, startOffset: offset, endOffset: offset + raw.utf16.count))
            }
            offset += raw.utf16.count
            cursor = end
        }

        return result
    }
}
