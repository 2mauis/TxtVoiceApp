import AVFoundation
import Foundation

enum SystemVoiceResolver {
    static func isLikelyChineseMaleVoiceName(_ name: String) -> Bool {
        preferredVoiceNames(for: .male).contains { normalized(name).contains(normalized($0)) }
            || preferredVoiceNames(for: .uncle).contains { normalized(name).contains(normalized($0)) }
    }

    static func voice(for settings: TTSSettings) -> AVSpeechSynthesisVoice? {
        if settings.systemVoicePreset == .custom,
           let voiceID = settings.systemVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            return voice
        }

        let chineseVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("zh") }
        let preferredNames = preferredVoiceNames(for: settings.systemVoicePreset)
        for name in preferredNames {
            if let voice = chineseVoices.first(where: { normalized($0.name).contains(normalized(name)) }) {
                return voice
            }
        }

        if let genderMatched = chineseVoices.first(where: { voice in
            switch settings.systemVoicePreset {
            case .female, .matureFemale:
                return voice.gender == .female
            case .male, .uncle:
                return voice.gender == .male
            case .custom:
                return false
            }
        }) {
            return genderMatched
        }

        return AVSpeechSynthesisVoice(language: "zh-CN") ?? chineseVoices.first
    }

    private static func preferredVoiceNames(for preset: SystemVoicePreset) -> [String] {
        switch preset {
        case .female:
            return ["Tingting", "Ting-Ting", "Lili", "Li-li", "莉莉", "Meijia", "Mei-Jia", "Sinji", "Sin-Ji", "美佳"]
        case .male:
            return ["Han", "瀚", "Bobo", "Bo-bo", "波波", "Yushu", "Yu-Shu", "Li-mu", "Limu"]
        case .uncle:
            return ["Han", "瀚", "Bobo", "Bo-bo", "波波", "Li-mu", "Limu", "Yushu", "Yu-Shu"]
        case .matureFemale:
            return ["Lili", "Li-li", "莉莉", "Meijia", "Mei-Jia", "Tingting", "Ting-Ting", "Sinji", "Sin-Ji"]
        case .custom:
            return []
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}

@MainActor
final class SpeechController: NSObject, ObservableObject {
    struct PlaybackCompletion: Equatable {
        let id = UUID()
        let offset: Int
    }

    private struct AudioChunkAsset {
        let index: Int
        let chunk: SpeechChunk
        let fileURL: URL
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
    private var audioPrefetchTasks: [Int: Task<AudioChunkAsset, Error>] = [:]
    private var audioSessionDirectory: URL?
    private var audioPlayer: AVAudioPlayer?
    private var activeAudioPlayerID: ObjectIdentifier?
    private var audioProgressTask: Task<Void, Never>?
    private var audioContinuation: CheckedContinuation<Void, Error>?
    private var speechContinuation: CheckedContinuation<Void, Error>?
    private var systemUtteranceOffsets: [ObjectIdentifier: Int] = [:]
    private var playbackSessionID = UUID()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        text: String,
        startingAt offset: Int,
        endingAt endOffset: Int? = nil,
        boundaryOffsets: [Int] = [],
        settings: TTSSettings
    ) {
        stop()
        let sessionID = UUID()
        playbackSessionID = sessionID
        chunks = TextChunker.chunks(
            from: text,
            startingAt: offset,
            endingAt: endOffset,
            boundaryOffsets: boundaryOffsets
        )
        currentChunkIndex = 0
        currentOffset = offset
        currentSnippet = chunks.first?.text ?? ""
        lastCompletion = nil
        AppLogger.info(
            "speak start offset=\(offset) end=\(endOffset.map(String.init) ?? "book-end") boundaries=\(boundaryOffsets.count) chunks=\(chunks.count) engine=\(settings.activeEngineSummary)",
            category: "speech"
        )

        guard !chunks.isEmpty else {
            AppLogger.warning("speak ignored because no chunks were produced", category: "speech")
            state = .idle
            return
        }

        configureAudioSession()

        if settings.engine == .iosSystem {
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
        stopActiveAudioPlayer()
        speechContinuation?.resume(throwing: CancellationError())
        speechContinuation = nil
        systemUtteranceOffsets.removeAll()
        removeAudioSessionDirectory()
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
            utterance.voice = SystemVoiceResolver.voice(for: settings)
            systemUtteranceOffsets[ObjectIdentifier(utterance)] = chunk.startOffset
            synthesizer.speak(utterance)
        }
    }

    private func runRemoteSpeech(settings: TTSSettings, sessionID: UUID) async {
        let prefetchDepth = 5
        let initialBufferCount = min(2, chunks.count)
        let sessionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("txtreadapp-playback-\(sessionID.uuidString)", isDirectory: true)
        audioSessionDirectory = sessionDirectory

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
                let fileURL = try await RemoteTTSClient.synthesizeToFile(
                    text: chunk.text,
                    settings: settings,
                    outputDirectory: sessionDirectory,
                    fileName: String(format: "chunk-%05d.m4a", index)
                )
                return AudioChunkAsset(index: index, chunk: chunk, fileURL: fileURL)
            }
        }

        do {
            guard playbackSessionID == sessionID else { return }
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            cancelAudioPrefetchTasks()
            for index in 0..<min(prefetchDepth, chunks.count) {
                schedulePrefetch(index)
            }
            try await waitForInitialBuffer(count: initialBufferCount, sessionID: sessionID)

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
                let asset = try await audioTask.value
                try Task.checkCancellation()
                guard playbackSessionID == sessionID else { return }
                schedulePrefetch(index + prefetchDepth)
                state = .speaking
                try await playAudio(asset)
                stopAudioProgressTracking()
                try? FileManager.default.removeItem(at: asset.fileURL)
                guard playbackSessionID == sessionID else { return }
                currentOffset = chunk.endOffset
            }
            cancelAudioPrefetchTasks()
            removeAudioSessionDirectory()
            finishPlaybackNaturally()
        } catch is CancellationError {
            AppLogger.info("remote speech cancelled", category: "speech")
            if playbackSessionID == sessionID {
                cancelAudioPrefetchTasks()
                stopActiveAudioPlayer()
                removeAudioSessionDirectory()
                state = .idle
            }
        } catch {
            guard playbackSessionID == sessionID else { return }
            AppLogger.error("remote speech failed: \(error.localizedDescription)", category: "speech")
            cancelAudioPrefetchTasks()
            stopActiveAudioPlayer()
            removeAudioSessionDirectory()
            currentSnippet = "\(error.localizedDescription) 已自动切换 macOS 系统语音。"
            state = .speaking
            enqueueSystemSpeech(settings: settings)
        }
    }

    private func waitForInitialBuffer(count: Int, sessionID: UUID) async throws {
        guard count > 1 else { return }
        for index in 0..<count {
            try Task.checkCancellation()
            guard playbackSessionID == sessionID else { throw CancellationError() }
            _ = try await audioPrefetchTasks[index]?.value
        }
    }

    private func cancelAudioPrefetchTasks() {
        guard !audioPrefetchTasks.isEmpty else { return }
        AppLogger.info("prefetch cancel count=\(audioPrefetchTasks.count)", category: "speech")
        audioPrefetchTasks.values.forEach { $0.cancel() }
        audioPrefetchTasks.removeAll()
    }

    private func playAudio(_ asset: AudioChunkAsset) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                audioPlayer?.delegate = nil
                audioPlayer = nil
                activeAudioPlayerID = nil
                audioContinuation = continuation
                let player = try AVAudioPlayer(contentsOf: asset.fileURL)
                audioPlayer = player
                activeAudioPlayerID = ObjectIdentifier(player)
                player.delegate = self
                player.prepareToPlay()
                guard player.play() else {
                    player.delegate = nil
                    if audioPlayer === player {
                        audioPlayer = nil
                        activeAudioPlayerID = nil
                    }
                    audioContinuation = nil
                    continuation.resume(throwing: ReaderError.invalidResponse("音频播放启动失败。"))
                    return
                }
                startAudioProgressTracking(player: player, playerID: ObjectIdentifier(player), chunk: asset.chunk)
                AppLogger.info(
                    "audio play index=\(asset.index) start=\(asset.chunk.startOffset) file=\(asset.fileURL.lastPathComponent)",
                    category: "speech"
                )
            } catch {
                audioPlayer?.delegate = nil
                audioPlayer = nil
                activeAudioPlayerID = nil
                audioContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func stopActiveAudioPlayer() {
        audioPlayer?.stop()
        audioPlayer?.delegate = nil
        audioPlayer = nil
        activeAudioPlayerID = nil
        stopAudioProgressTracking()
        audioContinuation?.resume(throwing: CancellationError())
        audioContinuation = nil
    }

    private func startAudioProgressTracking(player: AVAudioPlayer, playerID: ObjectIdentifier, chunk: SpeechChunk) {
        stopAudioProgressTracking()
        let sessionID = playbackSessionID
        audioProgressTask = Task { [weak self, weak player] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self,
                          self.playbackSessionID == sessionID,
                          self.activeAudioPlayerID == playerID,
                          let player,
                          player.duration > 0,
                          player.isPlaying else { return }
                    let progress = min(0.98, max(0, player.currentTime / player.duration))
                    let span = max(0, chunk.endOffset - chunk.startOffset)
                    let estimatedOffset = chunk.startOffset + Int(Double(span) * progress)
                    if estimatedOffset > self.currentOffset {
                        self.currentOffset = estimatedOffset
                    }
                }
            }
        }
    }

    private func stopAudioProgressTracking() {
        audioProgressTask?.cancel()
        audioProgressTask = nil
    }

    private func removeAudioSessionDirectory() {
        guard let directory = audioSessionDirectory else { return }
        audioSessionDirectory = nil
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: directory)
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
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let baseOffset = self.systemUtteranceOffsets[utteranceID] else { return }
            self.currentOffset = baseOffset + characterRange.location
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.systemUtteranceOffsets.removeValue(forKey: utteranceID)
            if let continuation = self.speechContinuation {
                continuation.resume()
                self.speechContinuation = nil
            } else {
                self.didFinishChunk()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.systemUtteranceOffsets.removeValue(forKey: utteranceID)
            self.speechContinuation?.resume(throwing: CancellationError())
            self.speechContinuation = nil
            self.state = .idle
        }
    }
}

extension SpeechController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let playerID = ObjectIdentifier(player)
        Task { @MainActor in
            guard self.activeAudioPlayerID == playerID else { return }
            self.stopAudioProgressTracking()
            self.audioPlayer?.delegate = nil
            self.audioPlayer = nil
            self.activeAudioPlayerID = nil
            if flag {
                self.audioContinuation?.resume()
            } else {
                self.audioContinuation?.resume(throwing: ReaderError.invalidResponse("音频播放中断。"))
            }
            self.audioContinuation = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let playerID = ObjectIdentifier(player)
        Task { @MainActor in
            guard self.activeAudioPlayerID == playerID else { return }
            self.stopAudioProgressTracking()
            self.audioPlayer?.delegate = nil
            self.audioPlayer = nil
            self.activeAudioPlayerID = nil
            self.audioContinuation?.resume(throwing: error ?? ReaderError.invalidResponse("音频解码失败。"))
            self.audioContinuation = nil
        }
    }
}
