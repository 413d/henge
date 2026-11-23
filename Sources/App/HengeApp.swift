import SwiftUI

@main
enum HengeMain {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            exit(HengeProbeRunner.run(arguments: CommandLine.arguments))
        }

        if SingleInstanceGuard.enforce() {
            exit(0)
        }

        HengeApp.main()
    }
}

struct HengeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator: HengeCoordinator
    private let menuBarLifecycleObserver: MenuBarLifecycleObserver

    init() {
        let settingsWindowController = SettingsWindowController()
        let lifecycleObserver = MenuBarLifecycleObserver()
        let coordinator = HengeCoordinator(
            environment: .live(),
            presentSettings: {
                settingsWindowController.showWindow()
            }
        )
        settingsWindowController.bind(coordinator: coordinator)
        lifecycleObserver.bind(coordinator: coordinator)
        menuBarLifecycleObserver = lifecycleObserver
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(coordinator)
        } label: {
            MenuBarIconLabel(symbolName: coordinator.statusItemSymbolName)
        }
    }
}
