import Foundation

enum TTSEngineChoice: String, CaseIterable, Identifiable, Codable {
    case iosSystem
    case localKokoro
    case localChatterbox

    static var allCases: [TTSEngineChoice] {
        [
            .iosSystem,
            .localKokoro,
            .localChatterbox
        ]
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .iosSystem:
            return "macOS 系统语音"
        case .localKokoro:
            return "Kokoro 本地 TTS"
        case .localChatterbox:
            return "Chatterbox 本地 TTS"
        }
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case Self.iosSystem.rawValue:
            self = .iosSystem
        case Self.localKokoro.rawValue, "localCommand", "kokoro" + "Core" + "ML":
            self = .localKokoro
        case Self.localChatterbox.rawValue:
            self = .localChatterbox
        default:
            self = .iosSystem
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

enum SystemVoicePreset: String, CaseIterable, Identifiable, Codable {
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

    var defaultRate: Float {
        switch self {
        case .female:
            return 0.48
        case .male:
            return 0.46
        case .uncle:
            return 0.38
        case .matureFemale:
            return 0.45
        case .custom:
            return 0.48
        }
    }

    var defaultPitch: Float {
        switch self {
        case .female:
            return 1.05
        case .male:
            return 0.92
        case .uncle:
            return 0.78
        case .matureFemale:
            return 0.88
        case .custom:
            return 1.0
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
    static var kokoroCondaArgumentsTemplate: String {
        "\(repositoryRootPath)/scripts/local_tts_kokoro.py --input {input} --output {output} --voice {voice} --speed {speed}"
    }
    static let chatterboxCondaCommandPath = localPythonCommandPath
    static var chatterboxCondaArgumentsTemplate: String {
        "\(repositoryRootPath)/scripts/local_tts_chatterbox.py --input {input} --output {output} --model multilingual --language zh --voice {chatterboxVoice} --exaggeration {exaggeration} --cfg-weight {cfgWeight}"
    }
    static let kokoroOutputExtension = "wav"

    private static var repositoryRootPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    var engine: TTSEngineChoice = .iosSystem

    var systemVoicePreset: SystemVoicePreset = .female
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

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        engine = try values.decodeIfPresent(TTSEngineChoice.self, forKey: .engine) ?? engine
        systemVoicePreset = try values.decodeIfPresent(SystemVoicePreset.self, forKey: .systemVoicePreset) ?? systemVoicePreset
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
        chatterboxVoicePath = try values.decodeIfPresent(String.self, forKey: .chatterboxVoicePath) ?? chatterboxVoicePath
        chatterboxExaggeration = try values.decodeIfPresent(Double.self, forKey: .chatterboxExaggeration) ?? chatterboxExaggeration
        chatterboxCFGWeight = try values.decodeIfPresent(Double.self, forKey: .chatterboxCFGWeight) ?? chatterboxCFGWeight
    }
}

extension TTSSettings {
    var activeEngineSummary: String {
        switch engine {
        case .iosSystem:
            return "\(engine.label) / \(systemVoicePreset.label)"
        case .localKokoro:
            return "\(engine.label) / \(resolvedLocalTTSVoice)"
        case .localChatterbox:
            let voice = chatterboxVoicePath.trimmingCharacters(in: .whitespacesAndNewlines)
            return voice.isEmpty ? "\(engine.label) / \(chatterboxVoicePreset.label)" : "\(engine.label) / \(chatterboxVoicePreset.label) / voice ref"
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
        case .localKokoro:
            return Self.kokoroCondaCommandPath
        case .iosSystem:
            return localTTSCommandPath ?? Self.kokoroCondaCommandPath
        }
    }

    var effectiveLocalTTSArgumentsTemplate: String {
        switch engine {
        case .localChatterbox:
            return Self.chatterboxCondaArgumentsTemplate
        case .localKokoro:
            return Self.kokoroCondaArgumentsTemplate
        case .iosSystem:
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

    private let key = "txtnovelreader.TTSSettings"
    private let legacyKey = "TxtVoice.TTSSettings"

    init() {
        let data = UserDefaults.standard.data(forKey: key) ?? UserDefaults.standard.data(forKey: legacyKey)
        if let data,
           var decoded = try? JSONDecoder().decode(TTSSettings.self, from: data) {
            var shouldSaveMigratedSettings = false
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
            if shouldSaveMigratedSettings || UserDefaults.standard.data(forKey: key) == nil {
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
