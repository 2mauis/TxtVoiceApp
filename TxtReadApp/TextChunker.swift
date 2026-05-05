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
        maxLength: Int = 900,
        boundaryOffsets: [Int] = []
    ) -> [SpeechChunk] {
        let textLength = text.utf16.count
        let safeOffset = max(0, min(offset, textLength))
        let safeEndOffset = max(safeOffset, min(endOffset ?? textLength, textLength))

        let safeBoundaries = Array(Set(boundaryOffsets))
            .filter { $0 > safeOffset && $0 < safeEndOffset }
            .sorted()
        if !safeBoundaries.isEmpty {
            let segmentOffsets = [safeOffset] + safeBoundaries + [safeEndOffset]
            return zip(segmentOffsets, segmentOffsets.dropFirst()).flatMap { segmentStart, segmentEnd in
                Self.chunks(
                    from: text,
                    startingAt: segmentStart,
                    endingAt: segmentEnd,
                    maxLength: maxLength
                )
            }
        }

        return chunksInRawRange(
            text,
            startingAt: safeOffset,
            endingAt: safeEndOffset,
            maxLength: maxLength
        )
    }

    private static func chunksInRawRange(
        _ text: String,
        startingAt safeOffset: Int,
        endingAt safeEndOffset: Int,
        maxLength: Int
    ) -> [SpeechChunk] {
        var chunks: [SpeechChunk] = []

        var segmentStartIndex = String.Index(utf16Offset: safeOffset, in: text)
        let endIndex = String.Index(utf16Offset: safeEndOffset, in: text)
        var cursorIndex = segmentStartIndex
        var segmentStartOffset = safeOffset
        var cursorOffset = safeOffset
        var lastSoftBreakIndex: String.Index?
        var lastSoftBreakOffset: Int?

        func appendSegment(upTo segmentEndIndex: String.Index, endOffset: Int) {
            guard segmentStartIndex < segmentEndIndex else {
                segmentStartIndex = segmentEndIndex
                segmentStartOffset = endOffset
                return
            }

            let raw = String(text[segmentStartIndex..<segmentEndIndex])
            let leadingTrim = raw.leadingTrimUTF16Count
            let trailingTrim = raw.trailingTrimUTF16Count
            let textStartOffset = min(endOffset, segmentStartOffset + leadingTrim)
            let textEndOffset = max(textStartOffset, endOffset - trailingTrim)
            guard textStartOffset < textEndOffset else {
                segmentStartIndex = segmentEndIndex
                segmentStartOffset = endOffset
                return
            }

            let textStartIndex = String.Index(utf16Offset: textStartOffset, in: text)
            let textEndIndex = String.Index(utf16Offset: textEndOffset, in: text)
            chunks.append(SpeechChunk(
                text: String(text[textStartIndex..<textEndIndex]),
                startOffset: textStartOffset,
                endOffset: textEndOffset
            ))
            segmentStartIndex = segmentEndIndex
            segmentStartOffset = endOffset
            lastSoftBreakIndex = nil
            lastSoftBreakOffset = nil
        }

        while cursorIndex < endIndex {
            let character = text[cursorIndex]
            let characterLength = String(character).utf16.count
            text.formIndex(after: &cursorIndex)
            cursorOffset += characterLength

            if character.isChunkBoundary {
                lastSoftBreakIndex = cursorIndex
                lastSoftBreakOffset = cursorOffset
            }

            let segmentLength = cursorOffset - segmentStartOffset
            guard segmentLength >= maxLength else { continue }

            if let breakIndex = lastSoftBreakIndex,
               let breakOffset = lastSoftBreakOffset,
               breakOffset > segmentStartOffset {
                appendSegment(upTo: breakIndex, endOffset: breakOffset)
            } else {
                appendSegment(upTo: cursorIndex, endOffset: cursorOffset)
            }
        }

        appendSegment(upTo: endIndex, endOffset: safeEndOffset)
        return chunks
    }
}

private extension String {
    var leadingTrimUTF16Count: Int {
        var count = 0
        for character in self {
            guard character.isWhitespace || character.isNewline else { break }
            count += String(character).utf16.count
        }
        return count
    }

    var trailingTrimUTF16Count: Int {
        var count = 0
        for character in reversed() {
            guard character.isWhitespace || character.isNewline else { break }
            count += String(character).utf16.count
        }
        return count
    }
}

private extension Character {
    var isChunkBoundary: Bool {
        isNewline || "，,、。！？!?；;：:…".contains(self)
    }
}
