import SwiftUI

@main
struct ScreenshotToTicketApp: App {
    private enum Tab {
        case addTicket
        case settings
    }

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = SettingsStore()
    @StateObject private var shareImportCoordinator = ShareImportCoordinator()
    @State private var selectedTab: Tab = .addTicket

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                MainView()
                    .tag(Tab.addTicket)
                    .tabItem {
                        Label("Add ticket", systemImage: "house")
                    }

                SettingsView()
                    .tag(Tab.settings)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            .environmentObject(settings)
            .environmentObject(shareImportCoordinator)
            .onOpenURL { url in
                guard SharedMediaInbox.matchesImportTrigger(url) else { return }
                focusTicketFlowForSharedImport()
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, SharedMediaInbox.hasPendingMedia() else { return }
                focusTicketFlowForSharedImport()
            }
        }
    }

    private func focusTicketFlowForSharedImport() {
        selectedTab = .addTicket
        shareImportCoordinator.requestImport()
    }
}
