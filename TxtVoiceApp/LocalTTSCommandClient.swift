import Foundation

enum LocalTTSCommandClient {
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
        let command = settings.effectiveLocalTTSCommandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw ReaderError.invalidResponse("本地 TTS 命令为空。")
        }

        let template = settings.effectiveLocalTTSArgumentsTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputExtension = sanitizedExtension(settings.effectiveLocalTTSOutputExtension)
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TxtVoiceTTS-\(UUID().uuidString)", isDirectory: true)
        let inputURL = workDirectory.appendingPathComponent("input.txt")
        let outputURL = workDirectory.appendingPathComponent("output.\(outputExtension)")

        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        try text.write(to: inputURL, atomically: true, encoding: .utf8)

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

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

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

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
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

        let data = try Data(contentsOf: outputURL)
        guard !data.isEmpty else {
            throw ReaderError.invalidResponse("本地 TTS 输出文件为空。")
        }

        AppLogger.info("local TTS output bytes=\(data.count)", category: "local-tts")
        return data
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
        environment["NUMBA_CACHE_DIR"] = "/private/tmp/txtvoice-numba-cache"
        environment["NUMBA_DISABLE_CACHE"] = "1"
        return environment
    }
}
