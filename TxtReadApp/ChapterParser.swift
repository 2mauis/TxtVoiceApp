import Foundation

enum ChapterParser {
    private static let pattern = #"^\s*(第[\d一二三四五六七八九十百千万零〇两]+[章节回卷集部篇][^\n]{0,48}|Chapter\s+\d+[^\n]{0,48})\s*$"#

    static func parse(_ text: String) -> [Chapter] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines, .caseInsensitive]) else {
            return [fallbackChapter(for: text)]
        }

        let matches = regex.matches(in: text, range: fullRange)
        guard !matches.isEmpty else {
            return [fallbackChapter(for: text)]
        }

        return matches.enumerated().map { index, match in
            let titleRange = match.range(at: 1)
            let title = nsText.substring(with: titleRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let start = match.range.location
            let end = index + 1 < matches.count ? matches[index + 1].range.location : nsText.length
            return Chapter(title: title, startOffset: start, endOffset: end)
        }
    }

    static func slice(_ text: String, chapter: Chapter) -> String {
        let safeStart = max(0, min(chapter.startOffset, text.utf16.count))
        let safeEnd = max(safeStart, min(chapter.endOffset, text.utf16.count))
        let start = String.Index(utf16Offset: safeStart, in: text)
        let end = String.Index(utf16Offset: safeEnd, in: text)
        return String(text[start..<end])
    }

    static func text(from text: String, offset: Int) -> String {
        let safeOffset = max(0, min(offset, text.utf16.count))
        let start = String.Index(utf16Offset: safeOffset, in: text)
        return String(text[start...])
    }

    private static func fallbackChapter(for text: String) -> Chapter {
        Chapter(title: "全文", startOffset: 0, endOffset: text.utf16.count)
    }
}
