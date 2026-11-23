import AppKit
import CoreGraphics
import Foundation

protocol ClipboardReplacing {
    /// Copies the current selection, verifies it matches the expected source,
    /// pastes the replacement, and restores the original full-fidelity clipboard.
    func replaceSelection(expectedText: String, with replacement: String, verifyReplacement: () -> Bool) -> Bool
    func replaceSelection(expectedText: String, with replacement: String, validateTarget: () -> Bool, verifyReplacement: () -> Bool) -> Bool
    func replaceSelection(expectedText: String, with replacement: String, processIdentifier: pid_t, validateTarget: () -> Bool, verifyReplacement: () -> Bool) -> Bool
}

extension ClipboardReplacing {
    func replaceSelection(expectedText: String, with replacement: String, validateTarget: () -> Bool, verifyReplacement: () -> Bool) -> Bool {
        guard validateTarget() else { return false }
        return replaceSelection(expectedText: expectedText, with: replacement, verifyReplacement: verifyReplacement)
    }

    func replaceSelection(expectedText: String, with replacement: String, processIdentifier: pid_t, validateTarget: () -> Bool, verifyReplacement: () -> Bool) -> Bool {
        replaceSelection(expectedText: expectedText, with: replacement, validateTarget: validateTarget, verifyReplacement: verifyReplacement)
    }
}

protocol ClipboardEventPosting {
    func postCommandKey(virtualKey: CGKeyCode) -> Bool
    func postCommandKey(virtualKey: CGKeyCode, to processIdentifier: pid_t) -> Bool
}

extension ClipboardEventPosting {
    func postCommandKey(virtualKey: CGKeyCode, to processIdentifier: pid_t) -> Bool {
        postCommandKey(virtualKey: virtualKey)
    }
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
        postCommandKey(virtualKey: virtualKey, to: 0)
    }

    func postCommandKey(virtualKey: CGKeyCode, to processIdentifier: pid_t) -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        if processIdentifier > 0 {
            down.postToPid(processIdentifier)
            up.postToPid(processIdentifier)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }
}

final class AppKitClipboardReplacement: ClipboardReplacing {
    private let clipboardManager: ClipboardManaging
    private let pasteboard: ReplacementPasteboard
    private let timeout: TimeInterval
    private let eventPoster: ClipboardEventPosting
    private let logger = Diagnostics.logger(.clipboard)

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
        replaceSelection(expectedText: expectedText, with: replacement, validateTarget: { true }, verifyReplacement: verifyReplacement)
    }

    func replaceSelection(
        expectedText: String,
        with replacement: String,
        validateTarget: () -> Bool,
        verifyReplacement: () -> Bool
    ) -> Bool {
        replaceSelection(expectedText: expectedText, with: replacement, processIdentifier: 0, validateTarget: validateTarget, verifyReplacement: verifyReplacement)
    }

    func replaceSelection(
        expectedText: String,
        with replacement: String,
        processIdentifier: pid_t,
        validateTarget: () -> Bool,
        verifyReplacement: () -> Bool
    ) -> Bool {
        let originalClipboard = clipboardManager.snapshot()
        guard originalClipboard.isRestorable else {
            let typeNames = Diagnostics.pasteboardTypeNames(originalClipboard.oversizedTypes)?.joined(separator: ",") ?? "redacted"
            logger.warning("\(DiagnosticsLabel.snapshotSkippedOversized.rawValue, privacy: .public) types=\(typeNames, privacy: .public)")
            return false
        }
        var didAttemptRestore = false
        defer {
            if !didAttemptRestore { _ = clipboardManager.restore(originalClipboard) }
        }

        let beforeCopyChangeCount = pasteboard.changeCount
        guard validateTarget(), postCommandKey(virtualKey: 8, processIdentifier: processIdentifier), waitForClipboardChange(after: beforeCopyChangeCount),
              validateTarget(), pasteboard.string() == expectedText else {
            return false
        }

        pasteboard.clear()
        guard pasteboard.setString(replacement), validateTarget(), postCommandKey(virtualKey: 9, processIdentifier: processIdentifier) else {
            return false
        }

        let replacementCompleted = waitForReplacement(verifyReplacement)
        didAttemptRestore = true
        let clipboardRestored = clipboardManager.restore(originalClipboard)
        return replacementCompleted && clipboardRestored
    }

    private func postCommandKey(virtualKey: CGKeyCode, processIdentifier: pid_t) -> Bool {
        if processIdentifier > 0 {
            return eventPoster.postCommandKey(virtualKey: virtualKey, to: processIdentifier)
        }
        return eventPoster.postCommandKey(virtualKey: virtualKey)
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
