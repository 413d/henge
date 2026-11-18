import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        requestAccessibilityPromptIfNeeded()
    }

    /// Shows the system Accessibility consent prompt once on launch when permission
    /// is missing. macOS remembers a denied prompt and does not repeat it, so this
    /// cannot loop.
    private func requestAccessibilityPromptIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        // kAXTrustedCheckOptionPrompt is the literal "AXTrustedCheckOptionPrompt"
        // (Swift 6 concurrency: the exported var is not sendable-safe).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
