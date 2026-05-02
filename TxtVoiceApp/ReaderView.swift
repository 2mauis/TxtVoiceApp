import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var library: BookLibraryStore
    @EnvironmentObject private var speech: SpeechController
    @EnvironmentObject private var settingsStore: TTSSettingsStore

    var book: ImportedBook

    @State private var text = ""
    @State private var encodingName = ""
    @State private var chapters: [Chapter] = []
    @State private var selectedChapter: Chapter?
    @State private var errorMessage: String?
    @State private var isShowingSettings = false
    @State private var settingsBeforeOpeningSheet: TTSSettings?

    private var displayText: String {
        guard let selectedChapter else { return text }
        return ChapterParser.slice(text, chapter: selectedChapter)
    }

    var body: some View {
        VStack(spacing: 0) {
            playbackPanel

            Divider()

            ScrollView {
                Text(displayText.isEmpty ? " " : displayText)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(7)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .navigationTitle(book.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(chapters) { chapter in
                        Button(chapter.title) {
                            selectedChapter = chapter
                            library.updateProgress(bookID: book.id, offset: chapter.startOffset)
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .disabled(chapters.isEmpty)
                .accessibilityLabel("章节")

                Button {
                    settingsBeforeOpeningSheet = settingsStore.settings
                    isShowingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("TTS 设置")
            }
        }
        .sheet(isPresented: $isShowingSettings, onDismiss: applySettingsChangeIfNeeded) {
            SettingsView()
        }
        .alert("读取失败", isPresented: .constant(errorMessage != nil)) {
            Button("好") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: load)
        .onDisappear {
            library.updateProgress(bookID: book.id, offset: speech.currentOffset)
        }
        .onChange(of: speech.currentOffset) { _, offset in
            guard offset > 0 else { return }
            library.updateProgress(bookID: book.id, offset: offset)
            if let chapter = chapter(containing: offset), chapter.id != selectedChapter?.id {
                selectedChapter = chapter
            }
        }
        .onChange(of: speech.lastCompletion) { _, completion in
            handlePlaybackCompletion(completion)
        }
    }

    private var playbackPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    jumpToChapter(delta: -1)
                } label: {
                    Image(systemName: "chevron.left.to.line")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!canJumpToPreviousChapter)
                .accessibilityLabel("上一章")

                Button {
                    if speech.state == .paused {
                        speech.pauseOrResume()
                    } else {
                        startReading()
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    speech.pauseOrResume()
                } label: {
                    Image(systemName: speech.state == .paused ? "playpause.fill" : "pause.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(speech.state == .idle)

                Button {
                    speech.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(speech.state == .idle)

                Button {
                    jumpToChapter(delta: 1)
                } label: {
                    Image(systemName: "chevron.right.to.line")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!canJumpToNextChapter)
                .accessibilityLabel("下一章")

                Spacer()

                Text(settingsStore.settings.activeEngineSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(speech.state.label)
                    .font(.subheadline.weight(.semibold))

                Text(currentLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var currentLine: String {
        if !speech.currentSnippet.isEmpty {
            return speech.currentSnippet.replacingOccurrences(of: "\n", with: " ")
        }

        if let selectedChapter {
            return "\(selectedChapter.title) · \(encodingName)"
        }

        return "\(chapters.count) 章 · \(encodingName)"
    }

    private var selectedChapterIndex: Int? {
        guard let selectedChapter else { return nil }
        return chapters.firstIndex { $0.id == selectedChapter.id }
    }

    private var canJumpToPreviousChapter: Bool {
        guard let selectedChapterIndex else { return false }
        return selectedChapterIndex > 0
    }

    private var canJumpToNextChapter: Bool {
        guard let selectedChapterIndex else { return false }
        return selectedChapterIndex + 1 < chapters.count
    }

    private func load() {
        do {
            let decoded = try library.decodedText(for: book)
            let latestBook = library.book(id: book.id) ?? book
            text = decoded.text
            encodingName = decoded.encodingName
            chapters = ChapterParser.parse(decoded.text)
            selectedChapter = chapter(containing: latestBook.lastReadOffset) ?? chapters.first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startReading() {
        guard !text.isEmpty else { return }
        let latestOffset = library.book(id: book.id)?.lastReadOffset ?? book.lastReadOffset
        let offset: Int
        if let selectedChapter, latestOffset >= selectedChapter.startOffset, latestOffset < selectedChapter.endOffset {
            offset = latestOffset
        } else {
            offset = selectedChapter?.startOffset ?? latestOffset
        }
        let endOffset = selectedChapter?.endOffset
        library.updateProgress(bookID: book.id, offset: offset)
        speech.speak(text: text, startingAt: offset, endingAt: endOffset, settings: settingsStore.settings)
    }

    private func jumpToChapter(delta: Int) {
        guard !chapters.isEmpty else { return }

        let currentIndex: Int
        if let selectedChapterIndex {
            currentIndex = selectedChapterIndex
        } else if let chapter = chapter(containing: library.book(id: book.id)?.lastReadOffset ?? book.lastReadOffset),
                  let index = chapters.firstIndex(where: { $0.id == chapter.id }) {
            currentIndex = index
        } else {
            currentIndex = 0
        }

        let targetIndex = currentIndex + delta
        guard chapters.indices.contains(targetIndex) else { return }

        let target = chapters[targetIndex]
        let shouldContinueSpeaking = speech.state != .idle
        speech.stop()
        openChapter(target, autoplay: shouldContinueSpeaking)
    }

    private func handlePlaybackCompletion(_ completion: SpeechController.PlaybackCompletion?) {
        guard let completion, !text.isEmpty, !chapters.isEmpty else { return }
        library.updateProgress(bookID: book.id, offset: completion.offset)

        let completedProbeOffset = max(0, completion.offset - 1)
        guard let completedChapter = chapter(containing: completedProbeOffset),
              let completedIndex = chapters.firstIndex(where: { $0.id == completedChapter.id }),
              completion.offset >= completedChapter.endOffset else {
            return
        }

        let nextIndex = completedIndex + 1
        guard chapters.indices.contains(nextIndex) else { return }
        openChapter(chapters[nextIndex], autoplay: true)
    }

    private func openChapter(_ chapter: Chapter, autoplay: Bool) {
        selectedChapter = chapter
        library.updateProgress(bookID: book.id, offset: chapter.startOffset)

        if autoplay {
            speech.speak(text: text, startingAt: chapter.startOffset, endingAt: chapter.endOffset, settings: settingsStore.settings)
        }
    }

    private func applySettingsChangeIfNeeded() {
        defer { settingsBeforeOpeningSheet = nil }
        guard settingsBeforeOpeningSheet != settingsStore.settings else { return }
        guard speech.state != .idle else { return }
        speech.stop()
    }

    private func chapter(containing offset: Int) -> Chapter? {
        chapters.first { chapter in
            offset >= chapter.startOffset && offset < chapter.endOffset
        }
    }
}
