import AVFoundation
import Foundation

enum LocalTTSCommandClient {
    static func synthesize(text: String, settings: TTSSettings) async throws -> Data {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("txtnovelreader-tts-result-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let playbackURL = try await synthesizeToFile(
            text: text,
            settings: settings,
            outputDirectory: outputDirectory,
            fileName: "output.m4a"
        )
        let data = try Data(contentsOf: playbackURL)
        guard !data.isEmpty else {
            throw ReaderError.invalidResponse("本地 TTS 输出文件为空。")
        }
        return data
    }

    static func synthesizeToFile(
        text: String,
        settings: TTSSettings,
        outputDirectory: URL,
        fileName: String
    ) async throws -> URL {
        let task = Task.detached(priority: .userInitiated) {
            try runToFile(
                text: text,
                settings: settings,
                outputDirectory: outputDirectory,
                fileName: fileName
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func runToFile(
        text: String,
        settings: TTSSettings,
        outputDirectory: URL,
        fileName: String
    ) throws -> URL {
        let command = settings.effectiveLocalTTSCommandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw ReaderError.invalidResponse("本地 TTS 命令为空。")
        }

        let template = settings.effectiveLocalTTSArgumentsTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputExtension = sanitizedExtension(settings.effectiveLocalTTSOutputExtension)
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("txtnovelreader-tts-\(UUID().uuidString)", isDirectory: true)
        let inputURL = workDirectory.appendingPathComponent("input.txt")
        let outputURL = workDirectory.appendingPathComponent("output.\(outputExtension)")
        let playbackURL = workDirectory.appendingPathComponent("playback.m4a")
        let stdoutURL = workDirectory.appendingPathComponent("stdout.log")
        let stderrURL = workDirectory.appendingPathComponent("stderr.log")
        let finalURL = outputDirectory.appendingPathComponent(fileName)

        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        try text.write(to: inputURL, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        var arguments = splitArguments(template).map { argument in
            argument
                .replacingOccurrences(of: "{input}", with: inputURL.path)
                .replacingOccurrences(of: "{output}", with: outputURL.path)
                .replacingOccurrences(of: "{voice}", with: settings.resolvedLocalTTSVoice)
                .replacingOccurrences(of: "{speed}", with: String(format: "%.2f", settings.localTTSSpeed))
                .replacingOccurrences(of: "{chatterboxVoice}", with: settings.chatterboxVoicePath)
                .replacingOccurrences(of: "{exaggeration}", with: String(format: "%.2f", settings.chatterboxExaggeration))
                .replacingOccurrences(of: "{cfgWeight}", with: String(format: "%.2f", settings.chatterboxCFGWeight))
                .replacingOccurrences(of: "{text}", with: text)
        }

        let executableURL: URL
        if command.contains("/") {
            executableURL = URL(fileURLWithPath: command)
        } else {
            executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments.insert(command, at: 0)
        }

        AppLogger.info(
            "local TTS command=\(command) args=\(AppLogger.snippet(arguments.joined(separator: " "))) textLength=\(text.count) output=\(outputURL.path)",
            category: "local-tts"
        )

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workDirectory
        process.environment = mergedEnvironment()

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        do {
            try process.run()
            while process.isRunning {
                if Task.isCancelled {
                    process.terminate()
                    process.waitUntilExit()
                    AppLogger.info("local TTS cancelled; process terminated", category: "local-tts")
                    throw CancellationError()
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLogger.error("local TTS failed to start: \(error.localizedDescription)", category: "local-tts")
            throw ReaderError.invalidResponse("本地 TTS 命令启动失败：\(error.localizedDescription)")
        }

        try? stdoutHandle.close()
        try? stderrHandle.close()
        let stdout = String(data: (try? Data(contentsOf: stdoutURL)) ?? Data(), encoding: .utf8) ?? ""
        let stderr = String(data: (try? Data(contentsOf: stderrURL)) ?? Data(), encoding: .utf8) ?? ""
        AppLogger.info(
            "local TTS exit=\(process.terminationStatus) stdout=\(AppLogger.snippet(stdout)) stderr=\(AppLogger.snippet(stderr))",
            category: "local-tts"
        )

        guard process.terminationStatus == 0 else {
            let message = stderr.isEmpty ? stdout : stderr
            throw ReaderError.invalidResponse("本地 TTS 命令失败：\(message.isEmpty ? "exit \(process.terminationStatus)" : message)")
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ReaderError.invalidResponse("本地 TTS 命令没有生成输出文件：\(outputURL.path)")
        }

        try transcodeToAAC(inputURL: outputURL, outputURL: playbackURL)
        let sourceSize = fileSize(outputURL)
        let compressedSize = fileSize(playbackURL)
        guard compressedSize > 0 else {
            throw ReaderError.invalidResponse("本地 TTS 输出文件为空。")
        }
        try? FileManager.default.removeItem(at: outputURL)
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.moveItem(at: playbackURL, to: finalURL)

        AppLogger.info(
            "local TTS asset source=\(sourceSize) compressed=\(compressedSize) file=\(finalURL.lastPathComponent)",
            category: "local-tts"
        )
        return finalURL
    }

    private static func transcodeToAAC(inputURL: URL, outputURL: URL) throws {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFile.processingFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000
        ]
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)
        let frameCapacity = AVAudioFrameCount(inputFile.processingFormat.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: frameCapacity) else {
            throw ReaderError.invalidResponse("无法创建 AAC 转码缓冲区。")
        }

        while inputFile.framePosition < inputFile.length {
            try inputFile.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try outputFile.write(from: buffer)
        }
    }

    private static func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
    }

    private static func sanitizedExtension(_ value: String?) -> String {
        let trimmed = (value ?? "wav")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? "wav" : trimmed
    }

    private static func splitArguments(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false

        for character in input {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                } else {
                    current.append(character)
                }
                continue
            }

            if character.isWhitespace, quote == nil {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if isEscaped {
            current.append("\\")
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func mergedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let path = environment["PATH"] ?? ""
        let additions = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        environment["PATH"] = (additions + [path])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["HF_HUB_DISABLE_XET"] = "1"
        environment["NUMBA_CACHE_DIR"] = "/private/tmp/txtnovelreader-numba-cache"
        environment["NUMBA_DISABLE_CACHE"] = "1"
        return environment
    }
}
