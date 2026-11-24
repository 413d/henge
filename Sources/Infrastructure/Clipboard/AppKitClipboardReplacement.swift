import AppKit
import CoreGraphics
import Foundation

enum ClipboardReplacementResult: Equatable {
    case success
    case pasteUnverified
    case restoreFailed
    case superseded
    case failed
}

protocol ClipboardReplacing {
    /// Copies the current selection, verifies it matches the expected source,
    /// pastes the replacement, and restores the original full-fidelity clipboard.
    func replaceSelection(
        expectedText: String,
        with replacement: String,
        processIdentifier: pid_t,
        validateTarget: () -> Bool,
        verifyReplacement: () -> Bool
    ) -> ClipboardReplacementResult
}

protocol ClipboardEventPosting {
    func postCommandKey(virtualKey: CGKeyCode, to processIdentifier: pid_t) -> Bool
}

protocol ReplacementPasteboard {
    var changeCount: Int { get }
    func string() -> String?
    /// Writes plain text along with org.nspasteboard.TransientType and org.nspasteboard.ConcealedType markers.
    func setTransientString(_ string: String) -> Bool
}

struct AppKitReplacementPasteboard: ReplacementPasteboard {
    let pasteboard: NSPasteboard

    var changeCount: Int { pasteboard.changeCount }
    func string() -> String? { pasteboard.string(forType: .string) }

    func setTransientString(_ string: String) -> Bool {
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}

struct SystemClipboardEventPoster: ClipboardEventPosting {
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
    private let operationBudget: TimeInterval
    private let eventPoster: ClipboardEventPosting
    private let logger = Diagnostics.logger(.clipboard)

    init(
        clipboardManager: ClipboardManaging,
        pasteboard: ReplacementPasteboard = AppKitReplacementPasteboard(pasteboard: .general),
        operationBudget: TimeInterval = 0.45,
        eventPoster: ClipboardEventPosting = SystemClipboardEventPoster()
    ) {
        self.clipboardManager = clipboardManager
        self.pasteboard = pasteboard
        self.operationBudget = operationBudget
        self.eventPoster = eventPoster
    }

    func replaceSelection(
        expectedText: String,
        with replacement: String,
        processIdentifier: pid_t = 0,
        validateTarget: () -> Bool = { true },
        verifyReplacement: () -> Bool
    ) -> ClipboardReplacementResult {
        let original = clipboardManager.snapshot()
        guard original.isRestorable else {
            let typeNames = Diagnostics.pasteboardTypeNames(original.oversizedTypes)?.joined(separator: ",") ?? "redacted"
            logger.warning("\(DiagnosticsLabel.snapshotSkippedOversized.rawValue, privacy: .public) types=\(typeNames, privacy: .public)")
            return .failed
        }

        let outcome = performReplacement(
            expectedText: expectedText,
            with: replacement,
            processIdentifier: processIdentifier,
            validateTarget: validateTarget,
            verifyReplacement: verifyReplacement
        )
        guard outcome != .superseded else {
            logger.info("\(DiagnosticsLabel.replacementSuperseded.rawValue, privacy: .public)")
            return .superseded
        }
        guard clipboardManager.restore(original) else {
            logger.error("\(DiagnosticsLabel.restoreFailed.rawValue, privacy: .public)")
            return .restoreFailed
        }
        return outcome
    }

    private func performReplacement(
        expectedText: String,
        with replacement: String,
        processIdentifier: pid_t,
        validateTarget: () -> Bool,
        verifyReplacement: () -> Bool
    ) -> ClipboardReplacementResult {
        let overallDeadline = Date().addingTimeInterval(operationBudget)
        let copyBudget = operationBudget <= 0.25 ? operationBudget / 2 : min(0.20, operationBudget / 2)
        let copyDeadline = min(overallDeadline, Date().addingTimeInterval(copyBudget))

        guard copyAndVerifySelection(
            expectedText: expectedText,
            processIdentifier: processIdentifier,
            validateTarget: validateTarget,
            deadline: copyDeadline
        ) else {
            return .failed
        }

        return writeTransientAndPaste(
            replacement: replacement,
            processIdentifier: processIdentifier,
            validateTarget: validateTarget,
            verifyReplacement: verifyReplacement,
            deadline: overallDeadline
        )
    }

    private func copyAndVerifySelection(
        expectedText: String,
        processIdentifier: pid_t,
        validateTarget: () -> Bool,
        deadline: Date
    ) -> Bool {
        let beforeCopyChangeCount = pasteboard.changeCount
        guard validateTarget(),
              eventPoster.postCommandKey(virtualKey: 8, to: processIdentifier),
              poll(until: { [pasteboard] in pasteboard.changeCount != beforeCopyChangeCount }, deadline: deadline),
              validateTarget(),
              pasteboard.string() == expectedText else {
            logger.warning("\(DiagnosticsLabel.replacementFailed.rawValue, privacy: .public) stage=copy")
            return false
        }
        return true
    }

    private func writeTransientAndPaste(
        replacement: String,
        processIdentifier: pid_t,
        validateTarget: () -> Bool,
        verifyReplacement: () -> Bool,
        deadline: Date
    ) -> ClipboardReplacementResult {
        guard pasteboard.setTransientString(replacement) else {
            logger.warning("\(DiagnosticsLabel.replacementFailed.rawValue, privacy: .public) stage=write")
            return .failed
        }
        let ownedChangeCount = pasteboard.changeCount

        guard validateTarget(), eventPoster.postCommandKey(virtualKey: 9, to: processIdentifier) else {
            if isSuperseded(ownedChangeCount: ownedChangeCount) {
                return .superseded
            }
            logger.warning("\(DiagnosticsLabel.replacementFailed.rawValue, privacy: .public) stage=paste")
            return .failed
        }

        let verified = poll(until: verifyReplacement, deadline: deadline)
        guard !isSuperseded(ownedChangeCount: ownedChangeCount) else {
            return .superseded
        }
        if !verified {
            logger.warning("\(DiagnosticsLabel.pasteUnverified.rawValue, privacy: .public)")
            return .pasteUnverified
        }
        return .success
    }

    private func isSuperseded(ownedChangeCount: Int) -> Bool {
        pasteboard.changeCount != ownedChangeCount
    }

    private func poll(until condition: () -> Bool, deadline: Date) -> Bool {
        while Date() < deadline {
            if condition() {
                return true
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            Thread.sleep(forTimeInterval: min(0.01, remaining))
        }
        return condition()
    }

}
