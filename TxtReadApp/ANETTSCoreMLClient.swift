import AVFoundation
import AudioCommon
import CoreML
import Foundation
import KokoroTTS

actor ANETTSCoreMLClient {
    static let shared = ANETTSCoreMLClient()

    private var model: KokoroTTSModel?

    func synthesize(text: String, settings: TTSSettings) async throws -> Data {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("txtreadapp-ane-tts-result-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let playbackURL = try await synthesizeToFile(
            text: text,
            settings: settings,
            outputDirectory: outputDirectory,
            fileName: "output.m4a"
        )
        let data = try Data(contentsOf: playbackURL)
        guard !data.isEmpty else {
            throw ReaderError.invalidResponse("Kokoro ANE 输出文件为空。")
        }
        return data
    }

    func synthesizeToFile(
        text: String,
        settings: TTSSettings,
        outputDirectory: URL,
        fileName: String
    ) async throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ReaderError.invalidResponse("Kokoro ANE 输入文本为空。")
        }

        let model = try await loadModel()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("txtreadapp-ane-tts-\(UUID().uuidString)", isDirectory: true)
        let wavURL = workDirectory.appendingPathComponent("output.wav")
        let playbackURL = workDirectory.appendingPathComponent("playback.m4a")
        let finalURL = outputDirectory.appendingPathComponent(fileName)

        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        AppLogger.info(
            "ane TTS synthesize textLength=\(trimmed.count) voice=\(settings.resolvedLocalTTSVoice) speed=\(settings.localTTSSpeed)",
            category: "ane-tts"
        )

        let startedAt = Date()
        let samples = try model.synthesize(
            text: trimmed,
            voice: settings.resolvedLocalTTSVoice,
            language: "zh",
            speed: Float(settings.localTTSSpeed)
        )
        try AudioCommon.WAVWriter.write(
            samples: samples,
            sampleRate: KokoroTTSModel.outputSampleRate,
            to: wavURL
        )
        try transcodeToAAC(inputURL: wavURL, outputURL: playbackURL)
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.moveItem(at: playbackURL, to: finalURL)

        AppLogger.info(
            "ane TTS completed elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s file=\(finalURL.lastPathComponent)",
            category: "ane-tts"
        )
        return finalURL
    }

    private func loadModel() async throws -> KokoroTTSModel {
        if let model {
            return model
        }

        AppLogger.info("ane TTS loading Kokoro CoreML model computeUnits=all", category: "ane-tts")
        let startedAt = Date()
        let loaded = try await KokoroTTSModel.fromPretrained(computeUnits: .all)
        model = loaded
        AppLogger.info(
            "ane TTS model loaded elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s",
            category: "ane-tts"
        )
        return loaded
    }

    private func transcodeToAAC(inputURL: URL, outputURL: URL) throws {
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
            throw ReaderError.invalidResponse("无法创建 ANE AAC 转码缓冲区。")
        }

        while inputFile.framePosition < inputFile.length {
            try inputFile.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try outputFile.write(from: buffer)
        }
    }
}
