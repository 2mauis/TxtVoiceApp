import Foundation

enum TTSEngineChoice: String, CaseIterable, Identifiable, Codable {
    case embeddedGemma4
    case gemma4Local
    case iosSystem
    case localCommand
    case localKokoro
    case kokoroCoreML
    case localChatterbox
    case openAICompatible
    case gemini
    case customEndpoint

    static var allCases: [TTSEngineChoice] {
        [
            .iosSystem,
            .localKokoro,
            .kokoroCoreML,
            .localChatterbox
        ]
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .embeddedGemma4:
            return "已弃用的文本模型"
        case .gemma4Local:
            return "本地 TTS Endpoint"
        case .iosSystem:
            return "macOS 系统语音"
        case .localCommand:
            return "本地 TTS 命令"
        case .localKokoro:
            return "Kokoro 本地 TTS"
        case .kokoroCoreML:
            return "Kokoro CoreML / ANE"
        case .localChatterbox:
            return "Chatterbox 本地 TTS"
        case .openAICompatible:
            return "OpenAI TTS"
        case .gemini:
            return "Gemini TTS"
        case .customEndpoint:
            return "自定义 TTS"
        }
    }
}

enum LocalTTSVoicePreset: String, CaseIterable, Identifiable, Codable {
    case female
    case male
    case uncle
    case matureFemale
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .female:
            return "女声"
        case .male:
            return "男声"
        case .uncle:
            return "大叔音"
        case .matureFemale:
            return "御姐音"
        case .custom:
            return "自定义"
        }
    }

    var kokoroVoice: String {
        switch self {
        case .female:
            return "zf_xiaoxiao"
        case .male:
            return "zm_yunxi"
        case .uncle:
            return "zm_yunjian"
        case .matureFemale:
            return "zf_xiaobei"
        case .custom:
            return "zf_xiaoxiao"
        }
    }
}

enum ChatterboxVoicePreset: String, CaseIterable, Identifiable, Codable {
    case female
    case male
    case uncle
    case matureFemale
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .female:
            return "女声"
        case .male:
            return "男声"
        case .uncle:
            return "大叔音"
        case .matureFemale:
            return "御姐音"
        case .custom:
            return "自定义"
        }
    }

    var defaultExaggeration: Double {
        switch self {
        case .female:
            return 0.45
        case .male:
            return 0.40
        case .uncle:
            return 0.35
        case .matureFemale:
            return 0.55
        case .custom:
            return 0.50
        }
    }

    var defaultCFGWeight: Double {
        switch self {
        case .female:
            return 0.45
        case .male:
            return 0.55
        case .uncle:
            return 0.60
        case .matureFemale:
            return 0.50
        case .custom:
            return 0.50
        }
    }
}

struct TTSSettings: Codable, Equatable {
    static let localPythonCommandPath = "/opt/homebrew/Caskroom/miniforge/base/envs/txtvoice-tts/bin/python"
    static let kokoroCondaCommandPath = localPythonCommandPath
    static let kokoroCondaArgumentsTemplate = "/Volumes/DATACS/work/code/TxtVoiceApp/scripts/local_tts_kokoro.py --input {input} --output {output} --voice {voice} --speed {speed}"
    static let kokoroCoreMLSwiftBinaryPath = "/Volumes/DATACS/work/code/TxtVoiceApp/vendor/kokoro-coreml/swift/.build/release/kokoro-bench"
    static let kokoroCoreMLModelsPath = "/Volumes/DATACS/work/code/TxtVoiceApp/vendor/kokoro-coreml/coreml"
    static let kokoroCoreMLHNSFWeightsPath = "/Volumes/DATACS/work/code/TxtVoiceApp/vendor/kokoro-coreml/outputs/txtvoice_coreml/hnsf_weights.json"
    static let kokoroCoreMLVoicesPath = "/Volumes/DATACS/work/code/TxtVoiceApp/vendor/kokoro-coreml/kokoro.js/voices"
    static let kokoroCoreMLCommandPath = localPythonCommandPath
    static let kokoroCoreMLArgumentsTemplate = "/Volumes/DATACS/work/code/TxtVoiceApp/scripts/local_tts_kokoro_coreml.py --input {input} --output {output} --voice {voice} --speed {speed} --language z --compute-units all"
    static let chatterboxCondaCommandPath = localPythonCommandPath
    static let chatterboxCondaArgumentsTemplate = "/Volumes/DATACS/work/code/TxtVoiceApp/scripts/local_tts_chatterbox.py --input {input} --output {output} --model multilingual --language zh --voice {chatterboxVoice} --exaggeration {exaggeration} --cfg-weight {cfgWeight}"
    static let kokoroOutputExtension = "wav"

    var engine: TTSEngineChoice = .iosSystem

    var gemma4EndpointURL: String = "http://127.0.0.1:8000/v1/audio/speech"
    var gemma4APIKey: String = ""
    var gemma4Model: String = "local-tts"
    var gemma4Voice: String = "default"
    var gemma4Instructions: String = "用自然、清晰、适合长篇中文小说的有声书风格朗读。"

    var systemVoiceIdentifier: String?
    var systemRate: Float = 0.48
    var systemPitch: Float = 1.0

    var localTTSCommandPath: String? = kokoroCondaCommandPath
    var localTTSArgumentsTemplate: String? = kokoroCondaArgumentsTemplate
    var localTTSOutputExtension: String? = kokoroOutputExtension
    var localTTSVoicePreset: LocalTTSVoicePreset = .female
    var localTTSCustomVoice: String = "zf_xiaoxiao"
    var localTTSSpeed: Double = 1.0
    var chatterboxVoicePreset: ChatterboxVoicePreset = .female
    var chatterboxVoicePath: String = ""
    var chatterboxExaggeration: Double = 0.5
    var chatterboxCFGWeight: Double = 0.5

    var openAIAPIKey: String = ""
    var openAIModel: String = "gpt-4o-mini-tts"
    var openAIVoice: String = "coral"
    var openAIInstructions: String = "用自然、稳定、适合长篇小说的中文有声书语气朗读。"

    var geminiAPIKey: String = ""
    var geminiModel: String = "gemini-2.5-flash-preview-tts"
    var geminiVoice: String = "Kore"
    var geminiStylePrompt: String = "请用自然、清晰、适合长篇中文小说的有声书风格朗读以下文本："

    var customEndpointURL: String = ""
    var customAPIKey: String = ""
    var customModel: String = ""
    var customVoice: String = ""

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        engine = try values.decodeIfPresent(TTSEngineChoice.self, forKey: .engine) ?? engine
        gemma4EndpointURL = try values.decodeIfPresent(String.self, forKey: .gemma4EndpointURL) ?? gemma4EndpointURL
        gemma4APIKey = try values.decodeIfPresent(String.self, forKey: .gemma4APIKey) ?? gemma4APIKey
        gemma4Model = try values.decodeIfPresent(String.self, forKey: .gemma4Model) ?? gemma4Model
        gemma4Voice = try values.decodeIfPresent(String.self, forKey: .gemma4Voice) ?? gemma4Voice
        gemma4Instructions = try values.decodeIfPresent(String.self, forKey: .gemma4Instructions) ?? gemma4Instructions
        systemVoiceIdentifier = try values.decodeIfPresent(String.self, forKey: .systemVoiceIdentifier) ?? systemVoiceIdentifier
        systemRate = try values.decodeIfPresent(Float.self, forKey: .systemRate) ?? systemRate
        systemPitch = try values.decodeIfPresent(Float.self, forKey: .systemPitch) ?? systemPitch
        localTTSCommandPath = try values.decodeIfPresent(String.self, forKey: .localTTSCommandPath) ?? localTTSCommandPath
        localTTSArgumentsTemplate = try values.decodeIfPresent(String.self, forKey: .localTTSArgumentsTemplate) ?? localTTSArgumentsTemplate
        localTTSOutputExtension = try values.decodeIfPresent(String.self, forKey: .localTTSOutputExtension) ?? localTTSOutputExtension
        localTTSVoicePreset = try values.decodeIfPresent(LocalTTSVoicePreset.self, forKey: .localTTSVoicePreset) ?? localTTSVoicePreset
        localTTSCustomVoice = try values.decodeIfPresent(String.self, forKey: .localTTSCustomVoice) ?? localTTSCustomVoice
        localTTSSpeed = try values.decodeIfPresent(Double.self, forKey: .localTTSSpeed) ?? localTTSSpeed
        chatterboxVoicePreset = try values.decodeIfPresent(ChatterboxVoicePreset.self, forKey: .chatterboxVoicePreset) ?? chatterboxVoicePreset
        openAIAPIKey = try values.decodeIfPresent(String.self, forKey: .openAIAPIKey) ?? openAIAPIKey
        openAIModel = try values.decodeIfPresent(String.self, forKey: .openAIModel) ?? openAIModel
        openAIVoice = try values.decodeIfPresent(String.self, forKey: .openAIVoice) ?? openAIVoice
        openAIInstructions = try values.decodeIfPresent(String.self, forKey: .openAIInstructions) ?? openAIInstructions
        geminiAPIKey = try values.decodeIfPresent(String.self, forKey: .geminiAPIKey) ?? geminiAPIKey
        geminiModel = try values.decodeIfPresent(String.self, forKey: .geminiModel) ?? geminiModel
        geminiVoice = try values.decodeIfPresent(String.self, forKey: .geminiVoice) ?? geminiVoice
        geminiStylePrompt = try values.decodeIfPresent(String.self, forKey: .geminiStylePrompt) ?? geminiStylePrompt
        customEndpointURL = try values.decodeIfPresent(String.self, forKey: .customEndpointURL) ?? customEndpointURL
        customAPIKey = try values.decodeIfPresent(String.self, forKey: .customAPIKey) ?? customAPIKey
        customModel = try values.decodeIfPresent(String.self, forKey: .customModel) ?? customModel
        customVoice = try values.decodeIfPresent(String.self, forKey: .customVoice) ?? customVoice
        chatterboxVoicePath = try values.decodeIfPresent(String.self, forKey: .chatterboxVoicePath) ?? chatterboxVoicePath
        chatterboxExaggeration = try values.decodeIfPresent(Double.self, forKey: .chatterboxExaggeration) ?? chatterboxExaggeration
        chatterboxCFGWeight = try values.decodeIfPresent(Double.self, forKey: .chatterboxCFGWeight) ?? chatterboxCFGWeight
    }
}

extension TTSSettings {
    var activeEngineSummary: String {
        switch engine {
        case .embeddedGemma4:
            return engine.label
        case .gemma4Local:
            return "\(engine.label) / \(gemma4Model)"
        case .iosSystem:
            return engine.label
        case .localCommand:
            let command = localTTSCommandPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let command, !command.isEmpty {
                return "\(engine.label) / \(resolvedLocalTTSVoice) / \(command)"
            }
            return engine.label
        case .localKokoro:
            return "\(engine.label) / \(resolvedLocalTTSVoice)"
        case .kokoroCoreML:
            return "\(engine.label) / \(resolvedLocalTTSVoice)"
        case .localChatterbox:
            let voice = chatterboxVoicePath.trimmingCharacters(in: .whitespacesAndNewlines)
            return voice.isEmpty ? "\(engine.label) / \(chatterboxVoicePreset.label)" : "\(engine.label) / \(chatterboxVoicePreset.label) / voice ref"
        case .openAICompatible:
            return "\(engine.label) / \(openAIModel)"
        case .gemini:
            return "\(engine.label) / \(geminiModel)"
        case .customEndpoint:
            return customModel.isEmpty ? engine.label : "\(engine.label) / \(customModel)"
        }
    }

    var resolvedLocalTTSVoice: String {
        let custom = localTTSCustomVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        if localTTSVoicePreset == .custom, !custom.isEmpty {
            return custom
        }
        return localTTSVoicePreset.kokoroVoice
    }

    var effectiveLocalTTSCommandPath: String {
        switch engine {
        case .localChatterbox:
            return Self.chatterboxCondaCommandPath
        case .kokoroCoreML:
            return ""
        case .localKokoro:
            return Self.kokoroCondaCommandPath
        default:
            return localTTSCommandPath ?? Self.kokoroCondaCommandPath
        }
    }

    var effectiveLocalTTSArgumentsTemplate: String {
        switch engine {
        case .localChatterbox:
            return Self.chatterboxCondaArgumentsTemplate
        case .kokoroCoreML:
            return ""
        case .localKokoro:
            return Self.kokoroCondaArgumentsTemplate
        default:
            return localTTSArgumentsTemplate ?? Self.kokoroCondaArgumentsTemplate
        }
    }

    var effectiveLocalTTSOutputExtension: String {
        localTTSOutputExtension ?? Self.kokoroOutputExtension
    }
}

@MainActor
final class TTSSettingsStore: ObservableObject {
    @Published var settings: TTSSettings {
        didSet { save() }
    }

    private let key = "TxtVoice.TTSSettings"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           var decoded = try? JSONDecoder().decode(TTSSettings.self, from: data) {
            var shouldSaveMigratedSettings = false
            if decoded.gemma4Model == "gemma-4-tts" || decoded.gemma4Model == "gemma4:e4b" {
                decoded.gemma4Model = "local-tts"
                shouldSaveMigratedSettings = true
            }
            if decoded.gemma4EndpointURL == "http://127.0.0.1:8080/v1/audio/speech" {
                decoded.gemma4EndpointURL = "http://127.0.0.1:8000/v1/audio/speech"
                shouldSaveMigratedSettings = true
            }
            if decoded.engine == .embeddedGemma4 ||
                decoded.engine == .gemma4Local ||
                decoded.engine == .customEndpoint ||
                decoded.engine == .openAICompatible ||
                decoded.engine == .gemini {
                decoded.engine = .iosSystem
                shouldSaveMigratedSettings = true
            }
            if decoded.engine == .localCommand {
                decoded.engine = .localKokoro
                shouldSaveMigratedSettings = true
            }
            if decoded.localTTSArgumentsTemplate?.contains("local_tts_chatterbox.py") == true {
                decoded.localTTSArgumentsTemplate = TTSSettings.kokoroCondaArgumentsTemplate
                shouldSaveMigratedSettings = true
            }
            if decoded.localTTSArgumentsTemplate?.contains("{voice}") == false,
               decoded.localTTSArgumentsTemplate?.contains("local_tts_kokoro.py") == true {
                decoded.localTTSArgumentsTemplate = TTSSettings.kokoroCondaArgumentsTemplate
                shouldSaveMigratedSettings = true
            }
            self.settings = decoded
            if shouldSaveMigratedSettings {
                save()
            }
        } else {
            self.settings = TTSSettings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
