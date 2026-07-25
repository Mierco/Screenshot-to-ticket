import SwiftUI

@main
struct ScreenshotToTicketApp: App {
    @StateObject private var settings = SettingsStore()
    @State private var selectedTab = AppTab.addTicket

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                MainView {
                    selectedTab = .settings
                }
                    .tabItem {
                        Label("Add ticket", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .tag(AppTab.addTicket)

                SettingsView {
                    selectedTab = .addTicket
                }
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(AppTab.settings)
            }
            .environmentObject(settings)
        }
    }
}

private enum AppTab {
    case addTicket
    case settings
}
