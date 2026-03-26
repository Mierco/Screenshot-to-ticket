import SwiftUI

@main
struct ScreenshotToTicketApp: App {
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                MainView()
                    .tabItem {
                        Label("Add ticket", systemImage: "plus.rectangle.on.rectangle")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            .environmentObject(settings)
        }
    }
}
