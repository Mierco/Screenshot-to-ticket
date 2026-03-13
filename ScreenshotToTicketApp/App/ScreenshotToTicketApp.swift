import SwiftUI

@main
struct ScreenshotToTicketApp: App {
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                MainView()
                    .tabItem {
                        Text("Add ticket")
                    }

                SettingsView()
                    .tabItem {
                        Text("Settings")
                    }
            }
            .environmentObject(settings)
        }
    }
}
