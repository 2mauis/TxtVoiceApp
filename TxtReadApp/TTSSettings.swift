import Foundation

enum TTSEngineChoice: String, CaseIterable, Identifiable, Codable {
    case iosSystem
    case localKokoro
    case aneKokoro

    static var allCases: [TTSEngineChoice] {
        [
            .iosSystem,
            .localKokoro,
            .aneKokoro
        ]
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .iosSystem:
            return "macOS 系统语音"
        case .localKokoro:
            return "Kokoro 本地 TTS"
        case .aneKokoro:
            return "Kokoro ANE CoreML"
        }
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case Self.iosSystem.rawValue:
            self = .iosSystem
        case Self.localKokoro.rawValue, "localCommand", "kokoro" + "Core" + "ML":
            self = .localKokoro
        case Self.aneKokoro.rawValue, "kokoroANE", "aneCoreML":
            self = .aneKokoro
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

struct TTSSettings: Codable, Equatable {
    static let localPythonCommandPath = "/opt/homebrew/Caskroom/miniforge/base/envs/txtnovelreader-kokoro/bin/python"
    static var kokoroCondaCommandPath: String {
        bundledPythonCommandPath ?? localPythonCommandPath
    }
    static var kokoroCondaArgumentsTemplate: String {
        "\(shellQuoted(kokoroScriptPath)) --input {input} --output {output} --voice {voice} --speed {speed}"
    }
    static let kokoroOutputExtension = "wav"

    private static var repositoryRootPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    private static var bundledLocalTTSRoot: URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let root = resourceURL.appendingPathComponent("LocalTTS", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        return root
    }

    private static var bundledPythonCommandPath: String? {
        guard let root = bundledLocalTTSRoot else { return nil }
        let python = root.appendingPathComponent("python-env/bin/python")
        guard FileManager.default.fileExists(atPath: python.path) else { return nil }
        return python.path
    }

    static var kokoroScriptPath: String {
        bundledOrRepositoryScriptPath("local_tts_kokoro.py")
    }

    private static func bundledOrRepositoryScriptPath(_ fileName: String) -> String {
        if let root = bundledLocalTTSRoot {
            let bundledScript = root.appendingPathComponent("scripts/\(fileName)")
            if FileManager.default.fileExists(atPath: bundledScript.path) {
                return bundledScript.path
            }
        }
        return "\(repositoryRootPath)/scripts/\(fileName)"
    }

    private static func shellQuoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
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
    }
}

extension TTSSettings {
    var activeEngineSummary: String {
        switch engine {
        case .iosSystem:
            return "\(engine.label) / \(systemVoicePreset.label)"
        case .localKokoro:
            return "\(engine.label) / \(resolvedLocalTTSVoice)"
        case .aneKokoro:
            return "\(engine.label) / \(resolvedLocalTTSVoice)"
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
        case .localKokoro:
            return Self.kokoroCondaCommandPath
        case .iosSystem, .aneKokoro:
            return localTTSCommandPath ?? Self.kokoroCondaCommandPath
        }
    }

    var effectiveLocalTTSArgumentsTemplate: String {
        switch engine {
        case .localKokoro:
            return Self.kokoroCondaArgumentsTemplate
        case .iosSystem, .aneKokoro:
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

    private let key = "txtreadapp.TTSSettings"
    private let legacyKey = "txtnovelreader.TTSSettings"

    init() {
        let data = UserDefaults.standard.data(forKey: key) ?? UserDefaults.standard.data(forKey: legacyKey)
        if let data,
            var decoded = try? JSONDecoder().decode(TTSSettings.self, from: data) {
            var shouldSaveMigratedSettings = false
            if decoded.localTTSArgumentsTemplate?.contains("{voice}") == false,
               decoded.localTTSArgumentsTemplate?.contains("local_tts_kokoro.py") == true {
                decoded.localTTSArgumentsTemplate = TTSSettings.kokoroCondaArgumentsTemplate
                shouldSaveMigratedSettings = true
            }
            if decoded.localTTSCommandPath?.contains("txtvoice-tts") == true {
                decoded.localTTSCommandPath = TTSSettings.kokoroCondaCommandPath
                shouldSaveMigratedSettings = true
            }
            if decoded.localTTSArgumentsTemplate?.contains("local_tts_kokoro.py") == true,
               decoded.localTTSArgumentsTemplate?.hasPrefix("\"") == false {
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
