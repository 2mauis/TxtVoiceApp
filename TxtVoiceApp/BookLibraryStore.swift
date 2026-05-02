import Foundation

@MainActor
final class BookLibraryStore: ObservableObject {
    @Published private(set) var books: [ImportedBook] = []

    private let fileManager: FileManager
    private let rootURL: URL
    private let importsURL: URL
    private let metadataURL: URL
    private let legacyRootURL: URL
    private let legacyImportsURL: URL
    private let legacyMetadataURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.rootURL = appSupportURL.appendingPathComponent("TxtVoiceApp", isDirectory: true)
        self.importsURL = rootURL.appendingPathComponent("Imports", isDirectory: true)
        self.metadataURL = rootURL.appendingPathComponent("library.json")
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.legacyRootURL = documentsURL.appendingPathComponent("TxtVoice", isDirectory: true)
        self.legacyImportsURL = legacyRootURL.appendingPathComponent("Imports", isDirectory: true)
        self.legacyMetadataURL = legacyRootURL.appendingPathComponent("library.json")
        createDirectories()
        migrateLegacyLibraryIfNeeded()
        load()
    }

    func importBook(from url: URL) throws -> ImportedBook {
        let canAccess = url.startAccessingSecurityScopedResource()
        defer {
            if canAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let decoded = try TextFileDecoder.decode(data)
        let chapters = ChapterParser.parse(decoded.text)
        let id = UUID()
        let storedFileName = "\(id.uuidString).txt"
        let destination = importsURL.appendingPathComponent(storedFileName)
        try data.write(to: destination, options: [.atomic])

        let book = ImportedBook(
            id: id,
            title: url.deletingPathExtension().lastPathComponent,
            originalFileName: url.lastPathComponent,
            storedFileName: storedFileName,
            encodingName: decoded.encodingName,
            characterCount: decoded.text.count,
            chapterCount: chapters.count,
            createdAt: Date(),
            lastReadOffset: 0
        )

        books.insert(book, at: 0)
        save()
        return book
    }

    func decodedText(for book: ImportedBook) throws -> DecodedText {
        let data = try Data(contentsOf: fileURL(for: book))
        return try TextFileDecoder.decode(data)
    }

    func book(id: UUID) -> ImportedBook? {
        books.first { $0.id == id }
    }

    func updateProgress(bookID: UUID, offset: Int) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        guard books[index].lastReadOffset != offset else { return }
        books[index].lastReadOffset = offset
        save()
    }

    func delete(_ book: ImportedBook) {
        try? fileManager.removeItem(at: fileURL(for: book))
        books.removeAll { $0.id == book.id }
        save()
    }

    private func fileURL(for book: ImportedBook) -> URL {
        importsURL.appendingPathComponent(book.storedFileName)
    }

    private func createDirectories() {
        try? fileManager.createDirectory(at: importsURL, withIntermediateDirectories: true)
    }

    private func migrateLegacyLibraryIfNeeded() {
        guard !fileManager.fileExists(atPath: metadataURL.path),
              fileManager.fileExists(atPath: legacyMetadataURL.path) else {
            return
        }

        try? fileManager.copyItem(at: legacyMetadataURL, to: metadataURL)

        guard let fileNames = try? fileManager.contentsOfDirectory(atPath: legacyImportsURL.path) else { return }
        for fileName in fileNames {
            let source = legacyImportsURL.appendingPathComponent(fileName)
            let destination = importsURL.appendingPathComponent(fileName)
            if !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.copyItem(at: source, to: destination)
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL) else {
            books = []
            return
        }

        books = (try? JSONDecoder.library.decode([ImportedBook].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder.pretty.encode(books) else { return }
        try? data.write(to: metadataURL, options: [.atomic])
    }
}

private extension JSONDecoder {
    static var library: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
