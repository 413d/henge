import AppKit
import CoreGraphics
import Foundation

protocol ClipboardReplacing {
    /// Copies the current selection, verifies it matches the expected source,
    /// pastes the replacement, and restores the original full-fidelity clipboard.
    func replaceSelection(expectedText: String, with replacement: String, verifyReplacement: () -> Bool) -> Bool
}

protocol ClipboardEventPosting {
    func postCommandKey(virtualKey: CGKeyCode) -> Bool
}

protocol ReplacementPasteboard {
    var changeCount: Int { get }
    func string() -> String?
    func clear()
    func setString(_ string: String) -> Bool
}

private struct AppKitReplacementPasteboard: ReplacementPasteboard {
    let pasteboard: NSPasteboard

    var changeCount: Int { pasteboard.changeCount }
    func string() -> String? { pasteboard.string(forType: .string) }
    func clear() { pasteboard.clearContents() }
    func setString(_ string: String) -> Bool { pasteboard.setString(string, forType: .string) }
}

struct SystemClipboardEventPoster: ClipboardEventPosting {
    func postCommandKey(virtualKey: CGKeyCode) -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

final class AppKitClipboardReplacement: ClipboardReplacing {
    private let clipboardManager: ClipboardManaging
    private let pasteboard: ReplacementPasteboard
    private let timeout: TimeInterval
    private let eventPoster: ClipboardEventPosting

    init(
        clipboardManager: ClipboardManaging,
        pasteboard: ReplacementPasteboard = AppKitReplacementPasteboard(pasteboard: .general),
        timeout: TimeInterval = 0.6,
        eventPoster: ClipboardEventPosting = SystemClipboardEventPoster()
    ) {
        self.clipboardManager = clipboardManager
        self.pasteboard = pasteboard
        self.timeout = timeout
        self.eventPoster = eventPoster
    }

    func replaceSelection(
        expectedText: String,
        with replacement: String,
        verifyReplacement: () -> Bool
    ) -> Bool {
        let originalClipboard = clipboardManager.snapshot()
        var didAttemptRestore = false
        defer {
            if !didAttemptRestore { _ = clipboardManager.restore(originalClipboard) }
        }

        let beforeCopyChangeCount = pasteboard.changeCount
        guard eventPoster.postCommandKey(virtualKey: 8), waitForClipboardChange(after: beforeCopyChangeCount),
              pasteboard.string() == expectedText else {
            return false
        }

        pasteboard.clear()
        guard pasteboard.setString(replacement), eventPoster.postCommandKey(virtualKey: 9) else {
            return false
        }

        let replacementCompleted = waitForReplacement(verifyReplacement)
        didAttemptRestore = true
        let clipboardRestored = clipboardManager.restore(originalClipboard)
        return replacementCompleted && clipboardRestored
    }

    private func waitForClipboardChange(after changeCount: Int) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != changeCount {
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }

    private func waitForReplacement(_ verifyReplacement: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if verifyReplacement() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return verifyReplacement()
    }

}
