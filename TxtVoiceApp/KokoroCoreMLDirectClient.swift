import Foundation

enum KokoroCoreMLDirectClient {
    private static let maxTokens = 128
    private static let maxChunkCharacters = 32

    static func synthesize(text: String, settings: TTSSettings) async throws -> Data {
        let task = Task.detached(priority: .userInitiated) {
            try run(text: text, settings: settings)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func run(text: String, settings: TTSSettings) throws -> Data {
        let executableURL = URL(fileURLWithPath: TTSSettings.kokoroCoreMLSwiftBinaryPath)
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw ReaderError.invalidResponse("未找到 Kokoro Swift 可执行文件：\(executableURL.path)")
        }
        guard FileManager.default.fileExists(atPath: TTSSettings.kokoroCoreMLModelsPath) else {
            throw ReaderError.invalidResponse("未找到 Kokoro CoreML 模型目录：\(TTSSettings.kokoroCoreMLModelsPath)")
        }
        guard FileManager.default.fileExists(atPath: TTSSettings.kokoroCoreMLHNSFWeightsPath) else {
            throw ReaderError.invalidResponse("未找到 Kokoro hnsf 权重：\(TTSSettings.kokoroCoreMLHNSFWeightsPath)")
        }

        let vocab = try loadVocab()
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TxtVoiceKokoroCoreML-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let chunks = try makeRequests(
            text: text,
            voice: settings.resolvedLocalTTSVoice,
            speed: settings.localTTSSpeed,
            vocab: vocab
        )

        var wavSegments: [Data] = []
        for (index, request) in chunks.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            let inputsDir = workDirectory.appendingPathComponent("inputs-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: inputsDir, withIntermediateDirectories: true)
            let inputURL = inputsDir.appendingPathComponent("chunk.json")
            let wavURL = workDirectory.appendingPathComponent("segment-\(index).wav")
            let inputData = try JSONEncoder().encode(request)
            try inputData.write(to: inputURL, options: [.atomic])

            try runSwiftPipeline(
                executableURL: executableURL,
                inputsDir: inputsDir,
                outputURL: wavURL
            )

            let data = try Data(contentsOf: wavURL)
            guard !data.isEmpty else {
                throw ReaderError.invalidResponse("Kokoro CoreML 生成了空音频。")
            }
            wavSegments.append(data)
        }

        let output = try concatenateWAV(wavSegments)
        AppLogger.info("kokoro coreml direct output bytes=\(output.count) chunks=\(chunks.count)", category: "kokoro-coreml")
        return output
    }

    private static func makeRequests(
        text: String,
        voice: String,
        speed: Double,
        vocab: [String: Int]
    ) throws -> [KokoroBenchInput] {
        var pending = splitText(text, maxCharacters: maxChunkCharacters)
        var requests: [KokoroBenchInput] = []

        while !pending.isEmpty {
            let chunk = pending.removeFirst()
            let phonemes = phonemizeMandarinApproximation(chunk)
            let ids = tokenize(phonemes: phonemes, vocab: vocab)
            if ids.count > maxTokens {
                let halves = splitInHalf(chunk)
                guard halves.count > 1 else {
                    throw ReaderError.invalidResponse("Kokoro CoreML 输入过长，无法拆分到 \(maxTokens) tokens 以内。")
                }
                pending.insert(contentsOf: halves, at: 0)
                continue
            }

            let padded = ids + Array(repeating: 0, count: max(0, maxTokens - ids.count))
            let attentionMask = Array(repeating: 1, count: ids.count) + Array(repeating: 0, count: max(0, maxTokens - ids.count))
            let refS = try loadVoiceEmbedding(voice: voice, tokenCount: ids.count)
            requests.append(
                KokoroBenchInput(
                    key: "chunk",
                    text: chunk,
                    voice: voice,
                    speed: speed,
                    phonemes: phonemes,
                    input_ids: Array(padded.prefix(maxTokens)),
                    attention_mask: Array(attentionMask.prefix(maxTokens)),
                    ref_s: refS,
                    canonical_duration_s: nil,
                    num_tokens: ids.count
                )
            )
        }

        if requests.isEmpty {
            throw ReaderError.invalidResponse("Kokoro CoreML 没有可朗读文本。")
        }
        return requests
    }

    private static func runSwiftPipeline(executableURL: URL, inputsDir: URL, outputURL: URL) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--models-dir", TTSSettings.kokoroCoreMLModelsPath,
            "--inputs-dir", inputsDir.path,
            "--hnsf-weights", TTSSettings.kokoroCoreMLHNSFWeightsPath,
            "--input-key", "chunk",
            "--wav", outputURL.path,
            "--compute-units", "all"
        ]
        process.environment = mergedEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ReaderError.invalidResponse("Kokoro Swift Pipeline 启动失败：\(error.localizedDescription)")
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        AppLogger.info(
            "kokoro coreml direct exit=\(process.terminationStatus) stdout=\(AppLogger.snippet(stdout)) stderr=\(AppLogger.snippet(stderr))",
            category: "kokoro-coreml"
        )

        guard process.terminationStatus == 0 else {
            let message = stderr.isEmpty ? stdout : stderr
            throw ReaderError.invalidResponse("Kokoro Swift Pipeline 失败：\(message.isEmpty ? "exit \(process.terminationStatus)" : message)")
        }
    }

    private static func loadVocab() throws -> [String: Int] {
        guard let url = Bundle.main.url(forResource: "KokoroVocab", withExtension: "json") else {
            throw ReaderError.invalidResponse("App Bundle 中缺少 KokoroVocab.json。")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: Int].self, from: data)
    }

    private static func tokenize(phonemes: String, vocab: [String: Int]) -> [Int] {
        let ids = phonemes.compactMap { vocab[String($0)] }
        return [0] + ids + [0]
    }

    private static func phonemizeMandarinApproximation(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "！", with: "!")
            .replacingOccurrences(of: "？", with: "?")
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "、", with: ",")

        let mutable = NSMutableString(string: normalized)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)

        return (mutable as String)
            .lowercased()
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "g", with: "ɡ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitText(_ text: String, maxCharacters: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        let punctuation = Set("。！？；，、,.!?;\n")

        for character in text {
            current.append(character)
            if punctuation.contains(character) || current.count >= maxCharacters {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    chunks.append(trimmed)
                }
                current = ""
            }
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            chunks.append(trimmed)
        }
        return chunks
    }

    private static func splitInHalf(_ text: String) -> [String] {
        guard text.count > 1 else { return [text] }
        let middle = text.index(text.startIndex, offsetBy: text.count / 2)
        return [
            String(text[..<middle]).trimmingCharacters(in: .whitespacesAndNewlines),
            String(text[middle...]).trimmingCharacters(in: .whitespacesAndNewlines)
        ].filter { !$0.isEmpty }
    }

    private static func loadVoiceEmbedding(voice: String, tokenCount: Int) throws -> [Float] {
        let voiceURL = URL(fileURLWithPath: TTSSettings.kokoroCoreMLVoicesPath)
            .appendingPathComponent("\(voice).bin")
        guard FileManager.default.fileExists(atPath: voiceURL.path) else {
            throw ReaderError.invalidResponse("未找到 Kokoro voice 文件：\(voiceURL.path)")
        }

        let data = try Data(contentsOf: voiceURL)
        let floats = data.withUnsafeBytes { buffer -> [Float] in
            let count = buffer.count / MemoryLayout<UInt32>.size
            var result: [Float] = []
            result.reserveCapacity(count)
            for index in 0..<count {
                let raw = buffer.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)
                result.append(Float(bitPattern: UInt32(littleEndian: raw)))
            }
            return result
        }

        let styleIndex = min(max(tokenCount - 2, 0), max(0, (floats.count / 256) - 1))
        let start = styleIndex * 256
        let end = min(start + 256, floats.count)
        guard end - start == 256 else {
            throw ReaderError.invalidResponse("Kokoro voice 文件格式无效：\(voiceURL.path)")
        }
        return Array(floats[start..<end])
    }

    private static func concatenateWAV(_ segments: [Data]) throws -> Data {
        guard let first = segments.first else {
            throw ReaderError.invalidResponse("Kokoro CoreML 没有音频片段。")
        }
        guard segments.count > 1 else { return first }
        guard first.count >= 44 else {
            throw ReaderError.invalidResponse("Kokoro CoreML WAV 头无效。")
        }

        var audioData = Data()
        for segment in segments {
            guard segment.count >= 44 else {
                throw ReaderError.invalidResponse("Kokoro CoreML WAV 片段无效。")
            }
            audioData.append(segment.dropFirst(44))
        }

        var output = Data(first.prefix(44))
        writeUInt32LE(UInt32(36 + audioData.count), into: &output, at: 4)
        writeUInt32LE(UInt32(audioData.count), into: &output, at: 40)
        output.append(audioData)
        return output
    }

    private static func writeUInt32LE(_ value: UInt32, into data: inout Data, at offset: Int) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.replaceSubrange(offset..<(offset + 4), with: bytes)
        }
    }

    private static func mergedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TMPDIR"] = "/private/tmp/txtvoice-coreml-tmp"
        environment["PATH"] = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            environment["PATH"] ?? ""
        ].filter { !$0.isEmpty }.joined(separator: ":")
        return environment
    }
}

private struct KokoroBenchInput: Encodable {
    let key: String
    let text: String
    let voice: String
    let speed: Double
    let phonemes: String
    let input_ids: [Int]
    let attention_mask: [Int]
    let ref_s: [Float]
    let canonical_duration_s: Double?
    let num_tokens: Int
}
