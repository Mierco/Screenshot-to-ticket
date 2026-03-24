import SwiftUI

@main
struct ScreenshotToTicketApp: App {
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                MainView()
                    .accessibilityIdentifier("tab.addTicket.content")
                    .tabItem {
                        Label("Add ticket", systemImage: "house")
                    }

                SettingsView()
                    .accessibilityIdentifier("tab.settings.content")
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            .environmentObject(settings)
        }
    }
}
