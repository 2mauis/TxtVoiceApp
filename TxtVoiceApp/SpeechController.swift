import AVFoundation
import Foundation

@MainActor
final class SpeechController: NSObject, ObservableObject {
    struct PlaybackCompletion: Equatable {
        let id = UUID()
        let offset: Int
    }

    enum PlaybackState: Equatable {
        case idle
        case preparing
        case speaking
        case paused
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                return "空闲"
            case .preparing:
                return "准备中"
            case .speaking:
                return "朗读中"
            case .paused:
                return "已暂停"
            case .failed(let message):
                return "失败：\(message)"
            }
        }
    }

    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentOffset: Int = 0
    @Published private(set) var currentSnippet: String = ""
    @Published private(set) var lastCompletion: PlaybackCompletion?

    private let synthesizer = AVSpeechSynthesizer()
    private var chunks: [SpeechChunk] = []
    private var currentChunkIndex = 0
    private var remoteTask: Task<Void, Never>?
    private var audioPrefetchTasks: [Int: Task<Data, Error>] = [:]
    private var audioPlayer: AVAudioPlayer?
    private var audioContinuation: CheckedContinuation<Void, Error>?
    private var speechContinuation: CheckedContinuation<Void, Error>?
    private var playbackSessionID = UUID()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String, startingAt offset: Int, endingAt endOffset: Int? = nil, settings: TTSSettings) {
        stop()
        let sessionID = UUID()
        playbackSessionID = sessionID
        chunks = TextChunker.chunks(from: text, startingAt: offset, endingAt: endOffset)
        currentChunkIndex = 0
        currentOffset = offset
        currentSnippet = chunks.first?.text ?? ""
        lastCompletion = nil
        AppLogger.info(
            "speak start offset=\(offset) end=\(endOffset.map(String.init) ?? "book-end") chunks=\(chunks.count) engine=\(settings.activeEngineSummary)",
            category: "speech"
        )

        guard !chunks.isEmpty else {
            AppLogger.warning("speak ignored because no chunks were produced", category: "speech")
            state = .idle
            return
        }

        configureAudioSession()

        if settings.engine == .iosSystem || settings.engine == .embeddedGemma4 {
            state = .speaking
            enqueueSystemSpeech(settings: settings)
        } else {
            state = .preparing
            remoteTask = Task { [weak self] in
                await self?.runRemoteSpeech(settings: settings, sessionID: sessionID)
            }
        }
    }

    func pauseOrResume() {
        switch state {
        case .speaking:
            if synthesizer.isSpeaking {
                synthesizer.pauseSpeaking(at: .word)
            }
            audioPlayer?.pause()
            state = .paused
        case .paused:
            if synthesizer.isPaused {
                synthesizer.continueSpeaking()
            }
            audioPlayer?.play()
            state = .speaking
        default:
            break
        }
    }

    func stop() {
        if state != .idle {
            AppLogger.info("stop requested state=\(state.label)", category: "speech")
        }
        playbackSessionID = UUID()
        remoteTask?.cancel()
        remoteTask = nil
        cancelAudioPrefetchTasks()
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        audioContinuation?.resume(throwing: CancellationError())
        audioContinuation = nil
        speechContinuation?.resume(throwing: CancellationError())
        speechContinuation = nil
        chunks = []
        currentChunkIndex = 0
        currentSnippet = ""
        state = .idle
    }

    private func enqueueSystemSpeech(settings: TTSSettings) {
        for chunk in chunks {
            let utterance = AVSpeechUtterance(string: chunk.text)
            utterance.rate = settings.systemRate
            utterance.pitchMultiplier = settings.systemPitch
            if let voiceID = settings.systemVoiceIdentifier {
                utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID)
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            }
            synthesizer.speak(utterance)
        }
    }

    private func runRemoteSpeech(settings: TTSSettings, sessionID: UUID) async {
        let prefetchDepth = settings.engine == .localChatterbox ? 1 : 2

        func schedulePrefetch(_ index: Int) {
            guard playbackSessionID == sessionID,
                  chunks.indices.contains(index),
                  audioPrefetchTasks[index] == nil else { return }
            let chunk = chunks[index]
            AppLogger.info(
                "prefetch schedule index=\(index) start=\(chunk.startOffset) length=\(chunk.text.count)",
                category: "speech"
            )
            audioPrefetchTasks[index] = Task(priority: .userInitiated) {
                try await RemoteTTSClient.synthesize(text: chunk.text, settings: settings)
            }
        }

        do {
            guard playbackSessionID == sessionID else { return }
            cancelAudioPrefetchTasks()
            for index in 0..<min(prefetchDepth, chunks.count) {
                schedulePrefetch(index)
            }

            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                guard playbackSessionID == sessionID else { return }
                currentChunkIndex = index
                currentOffset = chunk.startOffset
                currentSnippet = chunk.text
                state = .preparing
                AppLogger.info(
                    "remote chunk index=\(index) start=\(chunk.startOffset) length=\(chunk.text.count) engine=\(settings.activeEngineSummary)",
                    category: "speech"
                )
                schedulePrefetch(index)
                guard let audioTask = audioPrefetchTasks.removeValue(forKey: index) else {
                    throw ReaderError.invalidResponse("后台 TTS 任务没有启动。")
                }
                let audio = try await audioTask.value
                try Task.checkCancellation()
                guard playbackSessionID == sessionID else { return }
                schedulePrefetch(index + prefetchDepth)
                state = .speaking
                try await playAudio(audio)
                guard playbackSessionID == sessionID else { return }
                currentOffset = chunk.endOffset
            }
            cancelAudioPrefetchTasks()
            finishPlaybackNaturally()
        } catch is CancellationError {
            AppLogger.info("remote speech cancelled", category: "speech")
            if playbackSessionID == sessionID {
                cancelAudioPrefetchTasks()
                state = .idle
            }
        } catch {
            guard playbackSessionID == sessionID else { return }
            AppLogger.error("remote speech failed: \(error.localizedDescription)", category: "speech")
            cancelAudioPrefetchTasks()
            currentSnippet = "\(error.localizedDescription) 已自动切换 macOS 系统语音。"
            state = .speaking
            enqueueSystemSpeech(settings: settings)
        }
    }

    private func cancelAudioPrefetchTasks() {
        guard !audioPrefetchTasks.isEmpty else { return }
        AppLogger.info("prefetch cancel count=\(audioPrefetchTasks.count)", category: "speech")
        audioPrefetchTasks.values.forEach { $0.cancel() }
        audioPrefetchTasks.removeAll()
    }

    private func playAudio(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                audioContinuation = continuation
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
            } catch {
                audioContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func configureAudioSession() {
    }

    private func didFinishChunk() {
        guard currentChunkIndex + 1 < chunks.count else {
            finishPlaybackNaturally()
            return
        }

        currentChunkIndex += 1
        let chunk = chunks[currentChunkIndex]
        currentOffset = chunk.startOffset
        currentSnippet = chunk.text
    }

    private func finishPlaybackNaturally() {
        let finalOffset = chunks.last?.endOffset ?? currentOffset
        currentOffset = finalOffset
        currentSnippet = ""
        state = .idle
        lastCompletion = PlaybackCompletion(offset: finalOffset)
        AppLogger.info("playback completed offset=\(finalOffset)", category: "speech")
    }
}

extension SpeechController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if let continuation = self.speechContinuation {
                continuation.resume()
                self.speechContinuation = nil
            } else {
                self.didFinishChunk()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speechContinuation?.resume(throwing: CancellationError())
            self.speechContinuation = nil
            self.state = .idle
        }
    }
}

extension SpeechController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.audioContinuation?.resume()
            self.audioContinuation = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.audioContinuation?.resume(throwing: error ?? ReaderError.invalidResponse("音频解码失败。"))
            self.audioContinuation = nil
        }
    }
}
