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
    @State private var readingParagraphs: [ReadingParagraph] = []
    @State private var focusedParagraphID: Int?
    @State private var visibleParagraphID: Int?
    @State private var manualPlaybackStartOffset: Int?
    @State private var errorMessage: String?
    @State private var isShowingSettings = false
    @State private var settingsBeforeOpeningSheet: TTSSettings?
    @State private var lastPersistedOffset = 0
    @State private var lastProgressPersistedAt = Date.distantPast
    @State private var scrollToPlaybackRequest = UUID()
    @AppStorage("txtreadapp.followPlayback") private var followPlayback = true

    var body: some View {
        VStack(spacing: 0) {
            playbackPanel

            Divider()

            readingPane
        }
        .navigationTitle(book.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(chapters) { chapter in
                        Button(chapter.title) {
                            openChapter(chapter, autoplay: false)
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
            lastPersistedOffset = speech.currentOffset
            lastProgressPersistedAt = Date()
        }
        .onChange(of: speech.currentOffset) { _, offset in
            guard offset > 0 else { return }
            persistProgressIfNeeded(offset)
            guard followPlayback else { return }
            if let chapter = chapter(near: offset), chapter.id != selectedChapter?.id {
                selectChapter(chapter)
            }
            focusReadingWindow(at: offset)
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

                Button {
                    returnToCurrentPlayback()
                } label: {
                    Label("回到播放", systemImage: "scope")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(speech.currentOffset <= 0)
                .help("回到当前播放")
                .accessibilityLabel("回到当前播放")

                Button {
                    playFromCurrentReadingPosition()
                } label: {
                    Label("从此播放", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(text.isEmpty)
                .help("从当前阅读位置播放")
                .accessibilityLabel("从当前阅读位置播放")

                Spacer()

                Text(settingsStore.settings.activeEngineSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("跟随", isOn: $followPlayback)
                    .toggleStyle(.switch)
                    .font(.caption)
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

    private var readingPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if readingParagraphs.isEmpty {
                        Text(" ")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(readingParagraphs) { paragraph in
                            Text(paragraph.text)
                                .font(.system(.body, design: .serif))
                                .lineSpacing(7)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, paragraph.startsParagraph ? 10 : 0)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 8)
                                .background {
                                    if paragraph.id == focusedParagraphID {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.14))
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    setManualPlaybackStart(paragraph.startOffset)
                                }
                                .overlay {
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: VisibleParagraphPreferenceKey.self,
                                            value: [paragraph.id: geometry.frame(in: .named("readerScroll")).minY]
                                        )
                                    }
                                }
                                .id(paragraph.id)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .coordinateSpace(name: "readerScroll")
            .onPreferenceChange(VisibleParagraphPreferenceKey.self, perform: updateVisibleParagraph)
            .onAppear {
                focusReadingWindow(at: library.book(id: book.id)?.lastReadOffset ?? book.lastReadOffset, proxy: proxy, animated: false)
            }
            .onChange(of: focusedParagraphID) { _, paragraphID in
                guard followPlayback, let paragraphID else { return }
                scrollToParagraph(paragraphID, proxy: proxy, animated: true)
            }
            .onChange(of: selectedChapter?.id) { _, _ in
                guard followPlayback, let focusedParagraphID else { return }
                scrollToParagraph(focusedParagraphID, proxy: proxy, animated: false)
            }
            .onChange(of: scrollToPlaybackRequest) { _, _ in
                guard let focusedParagraphID else { return }
                scrollToParagraph(focusedParagraphID, proxy: proxy, animated: true)
            }
        }
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

    private var currentReadingStartOffset: Int? {
        manualPlaybackStartOffset
            ?? visibleReadingStartOffset
            ?? focusedParagraphID
            ?? selectedChapter?.startOffset
            ?? library.book(id: book.id)?.lastReadOffset
            ?? book.lastReadOffset
    }

    private var visibleReadingStartOffset: Int? {
        guard let visibleParagraphID,
              readingParagraphs.contains(where: { $0.id == visibleParagraphID }) else {
            return nil
        }
        return visibleParagraphID
    }

    private func load() {
        do {
            let decoded = try library.decodedText(for: book)
            let latestBook = library.book(id: book.id) ?? book
            text = decoded.text
            encodingName = decoded.encodingName
            chapters = ChapterParser.parse(decoded.text)
            selectChapter(chapter(near: latestBook.lastReadOffset) ?? chapters.first)
            focusReadingWindow(at: latestBook.lastReadOffset)
            lastPersistedOffset = latestBook.lastReadOffset
            lastProgressPersistedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startReading() {
        guard !text.isEmpty else { return }
        let latestOffset = library.book(id: book.id)?.lastReadOffset ?? book.lastReadOffset
        let offset: Int
        if let manualPlaybackStartOffset {
            offset = manualPlaybackStartOffset
        } else if let visibleReadingStartOffset {
            offset = visibleReadingStartOffset
        } else if let selectedChapter, latestOffset >= selectedChapter.startOffset, latestOffset < selectedChapter.endOffset {
            offset = latestOffset
        } else {
            offset = selectedChapter?.startOffset ?? latestOffset
        }
        startPlayback(at: offset)
    }

    private func jumpToChapter(delta: Int) {
        guard !chapters.isEmpty else { return }

        let currentIndex: Int
        if let selectedChapterIndex {
            currentIndex = selectedChapterIndex
        } else if let chapter = chapter(near: library.book(id: book.id)?.lastReadOffset ?? book.lastReadOffset),
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

    private func openChapter(_ chapter: Chapter, autoplay: Bool) {
        selectChapter(chapter)
        library.updateProgress(bookID: book.id, offset: chapter.startOffset)
        setManualPlaybackStart(chapter.startOffset)

        if autoplay {
            startPlayback(at: chapter.startOffset)
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

    private func chapter(near offset: Int) -> Chapter? {
        let lastTextOffset = max(0, text.utf16.count - 1)
        let safeOffset = max(0, min(offset, lastTextOffset))
        return chapter(containing: safeOffset)
    }

    private var chapterBoundaryOffsets: [Int] {
        chapters.map(\.startOffset)
    }

    private func startPlayback(at offset: Int) {
        guard !text.isEmpty else { return }
        let safeOffset = max(0, min(offset, text.utf16.count))
        if let chapter = chapter(near: safeOffset), chapter.id != selectedChapter?.id {
            selectChapter(chapter)
        }
        setManualPlaybackStart(safeOffset)
        library.updateProgress(bookID: book.id, offset: safeOffset)
        speech.speak(
            text: text,
            startingAt: safeOffset,
            boundaryOffsets: chapterBoundaryOffsets,
            settings: settingsStore.settings
        )
    }

    private func returnToCurrentPlayback() {
        let offset = speech.currentOffset
        guard offset > 0 else { return }
        if let chapter = chapter(near: offset), chapter.id != selectedChapter?.id {
            selectChapter(chapter)
        }
        setManualPlaybackStart(offset)
        scrollToPlaybackRequest = UUID()
    }

    private func playFromCurrentReadingPosition() {
        guard let offset = currentReadingStartOffset else { return }
        startPlayback(at: offset)
    }

    private func persistProgressIfNeeded(_ offset: Int) {
        let now = Date()
        let offsetDelta = abs(offset - lastPersistedOffset)
        guard offsetDelta >= 120 || now.timeIntervalSince(lastProgressPersistedAt) >= 2 else { return }
        library.updateProgress(bookID: book.id, offset: offset)
        lastPersistedOffset = offset
        lastProgressPersistedAt = now
    }

    private func selectChapter(_ chapter: Chapter?) {
        selectedChapter = chapter
        readingParagraphs = makeReadingParagraphs(for: chapter)
        visibleParagraphID = nil
        manualPlaybackStartOffset = nil
    }

    private func focusReadingWindow(at offset: Int, proxy: ScrollViewProxy? = nil, animated: Bool = true) {
        guard let paragraphID = readingParagraphs.first(where: { paragraph in
            offset >= paragraph.startOffset && offset < paragraph.endOffset
        })?.id ?? readingParagraphs.last(where: { offset >= $0.endOffset })?.id ?? readingParagraphs.first?.id else {
            focusedParagraphID = nil
            return
        }

        focusedParagraphID = paragraphID
        guard followPlayback, let proxy else { return }
        let action = {
            proxy.scrollTo(paragraphID, anchor: .center)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.25), action)
        } else {
            action()
        }
    }

    private func scrollToParagraph(_ paragraphID: Int, proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            let action = {
                proxy.scrollTo(paragraphID, anchor: .center)
            }
            if animated {
                withAnimation(.easeInOut(duration: 0.25), action)
            } else {
                action()
            }
        }
    }

    private func setManualPlaybackStart(_ offset: Int) {
        manualPlaybackStartOffset = offset
        focusReadingWindow(at: offset)
    }

    private func updateVisibleParagraph(_ positions: [Int: CGFloat]) {
        guard !positions.isEmpty else { return }
        let nextID = positions
            .filter { $0.value >= 0 }
            .min { $0.value < $1.value }?.key
            ?? positions.min { abs($0.value) < abs($1.value) }?.key
        guard let nextID, nextID != visibleParagraphID else { return }
        visibleParagraphID = nextID
    }

    private func makeReadingParagraphs(for chapter: Chapter?) -> [ReadingParagraph] {
        guard !text.isEmpty else { return [] }
        let textLength = text.utf16.count
        let startOffset = max(0, min(chapter?.startOffset ?? 0, textLength))
        let endOffset = max(startOffset, min(chapter?.endOffset ?? textLength, textLength))
        var segmentStartIndex = String.Index(utf16Offset: startOffset, in: text)
        let endIndex = String.Index(utf16Offset: endOffset, in: text)
        var cursor = segmentStartIndex
        var segmentStartOffset = startOffset
        var cursorOffset = startOffset
        var paragraphs: [ReadingParagraph] = []
        var nextSegmentStartsParagraph = true
        let maxSegmentLength = 180

        func appendSegment(upTo segmentEndIndex: String.Index, endOffset: Int) {
            let raw = String(text[segmentStartIndex..<segmentEndIndex])
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let leadingTrimOffset = raw.leadingHorizontalWhitespaceUTF16Count
            paragraphs.append(ReadingParagraph(
                text: trimmed,
                startOffset: segmentStartOffset + leadingTrimOffset,
                endOffset: endOffset,
                startsParagraph: nextSegmentStartsParagraph
            ))
            nextSegmentStartsParagraph = false
        }

        while cursor < endIndex {
            let character = text[cursor]
            let characterLength = String(character).utf16.count
            if String(character).rangeOfCharacter(from: .newlines) != nil {
                appendSegment(upTo: cursor, endOffset: cursorOffset)
                cursorOffset += characterLength
                text.formIndex(after: &cursor)
                segmentStartIndex = cursor
                segmentStartOffset = cursorOffset
                nextSegmentStartsParagraph = true
            } else {
                text.formIndex(after: &cursor)
                cursorOffset += characterLength
                let segmentLength = cursorOffset - segmentStartOffset
                if character.isSentenceTerminator || segmentLength >= maxSegmentLength {
                    appendSegment(upTo: cursor, endOffset: cursorOffset)
                    segmentStartIndex = cursor
                    segmentStartOffset = cursorOffset
                }
            }
        }

        appendSegment(upTo: endIndex, endOffset: endOffset)
        return paragraphs
    }
}

private struct ReadingParagraph: Identifiable, Equatable {
    var id: Int { startOffset }
    var text: String
    var startOffset: Int
    var endOffset: Int
    var startsParagraph: Bool
}

private struct VisibleParagraphPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension String {
    var leadingHorizontalWhitespaceUTF16Count: Int {
        var count = 0
        for character in self {
            guard character.isWhitespace, !character.isNewline else { break }
            count += String(character).utf16.count
        }
        return count
    }
}

private extension Character {
    var isSentenceTerminator: Bool {
        "。！？!?；;：:…".contains(self)
    }
}
