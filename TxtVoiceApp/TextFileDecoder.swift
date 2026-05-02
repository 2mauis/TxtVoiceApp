import Foundation
import CoreFoundation

enum TextFileDecoder {
    static func decode(_ data: Data) throws -> DecodedText {
        guard !data.isEmpty else { throw ReaderError.emptyDocument }

        if data.starts(with: [0xEF, 0xBB, 0xBF]),
           let text = String(data: data.dropFirst(3), encoding: .utf8) {
            return DecodedText(text: normalized(text), encodingName: "UTF-8 BOM")
        }

        if data.starts(with: [0xFF, 0xFE]),
           let text = String(data: data, encoding: .utf16LittleEndian) {
            return DecodedText(text: normalized(text), encodingName: "UTF-16 LE")
        }

        if data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16BigEndian) {
            return DecodedText(text: normalized(text), encodingName: "UTF-16 BE")
        }

        let candidates: [(String.Encoding, String)] = [
            (.utf8, "UTF-8"),
            (.utf16, "UTF-16"),
            (.utf16LittleEndian, "UTF-16 LE"),
            (.utf16BigEndian, "UTF-16 BE"),
            (encoding(.GB_18030_2000), "GB18030"),
            (encoding(.GBK_95), "GBK"),
            (encoding(.big5), "Big5")
        ]

        for (encoding, name) in candidates {
            if let text = String(data: data, encoding: encoding), !text.isEmpty {
                return DecodedText(text: normalized(text), encodingName: name)
            }
        }

        throw ReaderError.unsupportedEncoding
    }

    private static func encoding(_ cfEncoding: CFStringEncodings) -> String.Encoding {
        let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncoding.rawValue))
        return String.Encoding(rawValue: raw)
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
