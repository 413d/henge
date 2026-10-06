import ApplicationServices
import Cocoa

protocol AppRuntime {
    var hasAccessibilityPermission: Bool { get }

    func openAccessibilitySettings()
}

struct LiveAppRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
