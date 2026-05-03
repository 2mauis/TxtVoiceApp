import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var library: BookLibraryStore
    @EnvironmentObject private var settings: TTSSettingsStore
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var isShowingSettings = false

    private var txtTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let txt = UTType(filenameExtension: "txt") {
            types.append(txt)
        }
        return types
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.books.isEmpty {
                    InitialLibraryView(
                        engineSummary: settings.settings.activeEngineSummary,
                        importAction: { isImporting = true },
                        settingsAction: { isShowingSettings = true }
                    )
                } else {
                    VStack(spacing: 0) {
                        ModelStatusBar(
                            engineSummary: settings.settings.activeEngineSummary,
                            settingsAction: { isShowingSettings = true }
                        )

                        List {
                            ForEach(library.books) { book in
                                NavigationLink(value: book) {
                                    BookRow(book: book)
                                }
                            }
                            .onDelete(perform: delete)
                        }
                    }
                }
            }
            .navigationTitle("Txt Voice")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel("TTS 设置")

                        Button {
                            isImporting = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("导入 TXT")
                    }
                }
            }
            .navigationDestination(for: ImportedBook.self) { book in
                ReaderView(book: book)
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: txtTypes, allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .alert("导入失败", isPresented: .constant(errorMessage != nil)) {
                Button("好") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
                    .environmentObject(settings)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            _ = try library.importBook(from: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        offsets.map { library.books[$0] }.forEach { library.delete($0) }
    }
}

private struct InitialLibraryView: View {
    let engineSummary: String
    let importAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.blue)

                Text("TXT 语音书库")
                    .font(.largeTitle.weight(.semibold))

                Text("导入本地 TXT 小说，按章节拆分并后台生成朗读音频。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                ModelReadinessRow(
                    icon: "speaker.wave.2",
                    title: "当前朗读引擎",
                    detail: engineSummary
                )

                ModelReadinessRow(
                    icon: "waveform",
                    title: "本地 TTS 命令",
                    detail: "可选择 macOS 系统语音、Kokoro 或 Chatterbox，本地命令按章节后台生成音频。"
                )

                ModelReadinessRow(
                    icon: "text.badge.checkmark",
                    title: AppLicense.name,
                    detail: AppLicense.copyright
                )
            }
            .padding(16)
            .frame(maxWidth: 620)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 12) {
                Button(action: importAction) {
                    Label("导入 TXT", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)

                Button(action: settingsAction) {
                    Label("TTS 设置", systemImage: "slider.horizontal.3")
                }
            }

            Spacer(minLength: 24)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ModelStatusBar: View {
    let engineSummary: String
    let settingsAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(engineSummary, systemImage: "speaker.wave.2")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button(action: settingsAction) {
                Label("TTS 设置", systemImage: "slider.horizontal.3")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ModelReadinessRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct BookRow: View {
    var book: ImportedBook

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 10) {
                Label("\(book.chapterCount) 章", systemImage: "list.bullet")
                Label(book.encodingName, systemImage: "textformat")
                Label("\(book.characterCount) 字", systemImage: "number")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
