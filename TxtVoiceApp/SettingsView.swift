import AVFoundation
import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TTSSettingsStore
    @State private var localTTSTestStatus = ""
    @State private var isTestingLocalTTS = false
    @State private var testAudioPlayer: AVAudioPlayer?

    private var chineseVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("zh") }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsSection(title: "朗读引擎") {
                        SettingsRow("引擎") {
                            Picker("", selection: $store.settings.engine) {
                                ForEach(TTSEngineChoice.allCases) { engine in
                                    Text(engine.label).tag(engine)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 240, alignment: .leading)
                        }
                    }

                    switch store.settings.engine {
                    case .embeddedGemma4:
                        EmptyView()

                    case .gemma4Local:
                        EmptyView()

                    case .iosSystem:
                        systemVoiceSection

                    case .localCommand:
                        kokoroSection

                    case .localKokoro:
                        kokoroSection

                    case .kokoroCoreML:
                        kokoroSection

                    case .localChatterbox:
                        chatterboxSection

                    case .openAICompatible:
                        EmptyView()

                    case .gemini:
                        EmptyView()

                    case .customEndpoint:
                        EmptyView()
                    }

                    diagnosticsSection
                }
                .padding(24)
            }
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 640, idealHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var kokoroSection: some View {
        SettingsSection(title: "Kokoro 本地 TTS") {
            SettingsRow("音色") {
                Picker("", selection: $store.settings.localTTSVoicePreset) {
                    ForEach(LocalTTSVoicePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 420, alignment: .leading)
            }

            if store.settings.localTTSVoicePreset == .custom {
                SettingsRow("Voice ID") {
                    TextField("", text: $store.settings.localTTSCustomVoice)
                        .textFieldStyle(.roundedBorder)
                }
            }

            SettingsRow("语速") {
                HStack(spacing: 10) {
                    Image(systemName: "tortoise")
                        .foregroundStyle(.secondary)
                    Slider(value: $store.settings.localTTSSpeed, in: 0.70...1.30)
                    Image(systemName: "hare")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2fx", store.settings.localTTSSpeed))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }

            SettingsRow("测试") {
                localTTSTestButton
            }

            if !localTTSTestStatus.isEmpty {
                SettingsRow("测试结果") {
                    Text(localTTSTestStatus)
                        .font(.callout)
                        .foregroundStyle(localTTSTestStatus.hasPrefix("成功") ? .green : .secondary)
                        .lineLimit(3)
                }
            }
        }
    }

    private var chatterboxSection: some View {
        SettingsSection(title: "Chatterbox 本地 TTS") {
            SettingsRow("音色") {
                Picker("", selection: $store.settings.chatterboxVoicePreset) {
                    ForEach(ChatterboxVoicePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 420, alignment: .leading)
                .onChange(of: store.settings.chatterboxVoicePreset) { _, preset in
                    applyChatterboxPreset(preset)
                }
            }

            if store.settings.chatterboxVoicePreset == .custom {
                SettingsRow("参考音频") {
                    HStack(spacing: 10) {
                        TextField("可选：用于声音克隆的 wav 文件路径", text: $store.settings.chatterboxVoicePath)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            chooseChatterboxVoiceFile()
                        } label: {
                            Label("选择", systemImage: "waveform")
                        }
                    }
                }
            }

            SettingsRow("表现强度") {
                HStack(spacing: 10) {
                    Slider(value: $store.settings.chatterboxExaggeration, in: 0.25...0.90)
                    Text(String(format: "%.2f", store.settings.chatterboxExaggeration))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                }
            }

            SettingsRow("CFG") {
                HStack(spacing: 10) {
                    Slider(value: $store.settings.chatterboxCFGWeight, in: 0.20...0.90)
                    Text(String(format: "%.2f", store.settings.chatterboxCFGWeight))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                }
            }

            SettingsRow("测试") {
                localTTSTestButton
            }

            if !localTTSTestStatus.isEmpty {
                SettingsRow("测试结果") {
                    Text(localTTSTestStatus)
                        .font(.callout)
                        .foregroundStyle(localTTSTestStatus.hasPrefix("成功") ? .green : .secondary)
                        .lineLimit(3)
                }
            }
        }
    }

    private func applyChatterboxPreset(_ preset: ChatterboxVoicePreset) {
        store.settings.chatterboxExaggeration = preset.defaultExaggeration
        store.settings.chatterboxCFGWeight = preset.defaultCFGWeight
        if preset != .custom {
            store.settings.chatterboxVoicePath = ""
        }
    }

    private var localTTSTestButton: some View {
        HStack(spacing: 10) {
            Button {
                Task { await testLocalTTSCommand() }
            } label: {
                Label(isTestingLocalTTS ? "测试中" : "测试播放", systemImage: "speaker.wave.2")
            }
            .disabled(isTestingLocalTTS)

            if isTestingLocalTTS {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var systemVoiceSection: some View {
        SettingsSection(title: "macOS 系统语音") {
            SettingsRow("声音") {
                Picker("", selection: systemVoiceBinding) {
                    Text("自动").tag("")
                    ForEach(chineseVoices, id: \.identifier) { voice in
                        Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 360, alignment: .leading)
            }

            SettingsRow("语速") {
                HStack(spacing: 10) {
                    Image(systemName: "tortoise")
                        .foregroundStyle(.secondary)
                    Slider(value: systemRateBinding, in: 0.25...0.62)
                    Image(systemName: "hare")
                        .foregroundStyle(.secondary)
                }
            }

            SettingsRow("音高") {
                Slider(value: systemPitchBinding, in: 0.8...1.25)
            }
        }
    }

    private var diagnosticsSection: some View {
        SettingsSection(title: "调试日志") {
            SettingsRow("日志文件") {
                HStack(spacing: 10) {
                    Text(AppLogger.logURL.path)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("在 Finder 显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppLogger.logURL])
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TTS 设置")
                    .font(.title2.weight(.semibold))
                Text("配置 macOS 系统语音、Kokoro 和 Chatterbox 本地 TTS。")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("完成") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func optionalTextBinding(_ keyPath: WritableKeyPath<TTSSettings, String?>) -> Binding<String> {
        Binding {
            store.settings[keyPath: keyPath] ?? ""
        } set: { value in
            store.settings[keyPath: keyPath] = value
        }
    }

    private var systemVoiceBinding: Binding<String> {
        Binding {
            store.settings.systemVoiceIdentifier ?? ""
        } set: { value in
            store.settings.systemVoiceIdentifier = value.isEmpty ? nil : value
        }
    }

    private var systemRateBinding: Binding<Double> {
        Binding {
            Double(store.settings.systemRate)
        } set: { value in
            store.settings.systemRate = Float(value)
        }
    }

    private var systemPitchBinding: Binding<Double> {
        Binding {
            Double(store.settings.systemPitch)
        } set: { value in
            store.settings.systemPitch = Float(value)
        }
    }

    private func chooseChatterboxVoiceFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .wav]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.chatterboxVoicePath = url.path
        }
    }

    private func testLocalTTSCommand() async {
        isTestingLocalTTS = true
        localTTSTestStatus = "正在调用 \(store.settings.engine.label)..."
        defer { isTestingLocalTTS = false }

        do {
            let audio: Data
            if store.settings.engine == .kokoroCoreML {
                audio = try await KokoroCoreMLDirectClient.synthesize(
                    text: "你好，这是 TxtVoiceApp 本地语音测试。",
                    settings: store.settings
                )
            } else {
                audio = try await LocalTTSCommandClient.synthesize(
                    text: "你好，这是 TxtVoiceApp 本地语音测试。",
                    settings: store.settings
                )
            }
            let player = try AVAudioPlayer(data: audio)
            player.prepareToPlay()
            player.play()
            testAudioPlayer = player
            localTTSTestStatus = "成功：本地 TTS 已生成并播放测试音频。"
        } catch {
            localTTSTestStatus = "失败：\(error.localizedDescription)"
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(spacing: 8) {
                content
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
