import SwiftUI

@main
struct HengeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = HengeCoordinator(environment: .live())

    var body: some Scene {
        MenuBarExtra("Henge", systemImage: coordinator.statusItemSymbolName) {
            MenuBarView()
                .environmentObject(coordinator)
        }

        Settings {
            SettingsView()
                .environmentObject(coordinator)
        }
    }
}
