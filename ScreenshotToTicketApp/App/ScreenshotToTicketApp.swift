import SwiftUI

@main
struct ScreenshotToTicketApp: App {
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(settings)
        }
    }
}
