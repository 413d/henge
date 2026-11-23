import Foundation

enum FixFailureReason: Equatable, Sendable {
    case noActiveApplication
    case missingPermission
    case noFocusedElement
    case accessibilityError(Int32)
    case clipboardRestoreFailed
    case clipboardSuperseded
    case focusLost(applicationName: String)
}

enum FixOutcome: Equatable, Sendable {
    case fixed(viaClipboard: Bool)
    case nothingToFix
    case secureField
    case excluded
    case unsupported
    case pasteUnverified
    case failed(FixFailureReason)
}
