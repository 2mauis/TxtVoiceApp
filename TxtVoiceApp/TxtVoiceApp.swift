import SwiftUI

@main
struct TxtNovelReaderApp: App {
    @StateObject private var library = BookLibraryStore()
    @StateObject private var speech = SpeechController()
    @StateObject private var settings = TTSSettingsStore()

    init() {
        AppLogger.info("app launch logURL=\(AppLogger.logURL.path)", category: "app")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(speech)
                .environmentObject(settings)
        }
    }
}
