import ApplicationServices

enum FocusedElementProbe: Equatable {
    case unavailable(FocusedElementProbeFailure)
    case available(FocusedElementSnapshot)
}

enum FocusedElementProbeFailure: Error, Equatable {
    case missingPermission
    case noFocusedElement
    case accessibilityError(AXError)

    var description: String {
        switch self {
        case .missingPermission:
            return L10n.string(
                "fix_outcome.failed.missing_permission",
                defaultValue: "Accessibility access is required before Henge can inspect the focused element."
            )
        case .noFocusedElement:
            return L10n.string(
                "fix_outcome.failed.no_focused_element",
                defaultValue: "No focused text element is currently available for Henge to inspect."
            )
        case let .accessibilityError(error):
            return L10n.format(
                "probe.focused_element.accessibility_error",
                defaultValue: "Henge could not inspect the focused element (AXError %d).",
                error.rawValue
            )
        }
    }
}

struct FocusedElementSnapshot: Equatable {
    let role: String?
    let subrole: String?
    let isSecure: Bool

    var summary: String {
        switch (role, subrole) {
        case let (role?, subrole?) where !subrole.isEmpty:
            return "\(role) / \(subrole)"
        case let (role?, _):
            return role
        case let (_, subrole?) where !subrole.isEmpty:
            return subrole
        default:
            return L10n.string(
                "probe.focused_element.unknown_role",
                defaultValue: "unknown role"
            )
        }
    }
}

enum SelectionProbe: Equatable {
    case unavailable(SelectionProbeFailure)
    case available(SelectionSnapshot)
}

enum SelectionProbeFailure: Error, Equatable {
    case missingPermission
    case noFocusedElement
    case secureField
    case noSelection
    case unsupported
    case accessibilityError(AXError)

    var description: String {
        switch self {
        case .missingPermission:
            return L10n.string(
                "probe.selection.missing_permission",
                defaultValue: "Accessibility access is required before Henge can inspect the current selection."
            )
        case .noFocusedElement:
            return L10n.string(
                "probe.selection.no_focused_element",
                defaultValue: "No focused text element is currently available for selection inspection."
            )
        case .secureField:
            return L10n.string(
                "probe.selection.secure_field",
                defaultValue: "Focused secure text field detected. Henge did not inspect its selection."
            )
        case .noSelection:
            return L10n.string(
                "probe.selection.no_selection",
                defaultValue: "No text selection is currently available."
            )
        case .unsupported:
            return L10n.string(
                "probe.selection.unsupported",
                defaultValue: "The focused element does not expose a readable text selection through Accessibility."
            )
        case let .accessibilityError(error):
            return L10n.format(
                "probe.selection.accessibility_error",
                defaultValue: "Henge could not inspect the current selection (AXError %d).",
                error.rawValue
            )
        }
    }
}

struct SelectionSnapshot: Equatable {
    let text: String
    let range: SelectionRangeSnapshot
    var isCaretContext = false

    var summary: String {
        "Selection resolved: \(text.count) chars at [\(range.location), \(range.length)]."
    }
}

enum TextContextProbe: Equatable {
    case unavailable(SelectionProbeFailure)
    /// For a selection, `selection.text` is selected text and range is non-empty. Without
    /// a selection, `selection.text` is the element value and range is the caret offset.
    case available(TextContext)
}

struct SelectionRangeSnapshot: Equatable {
    let location: Int
    let length: Int
}

enum SelectionWriteResult: Equatable {
    case success(SelectionRangeSnapshot)
    case unavailable(SelectionWriteFailure)
}

enum SelectionWriteFailure: Equatable {
    case missingPermission
    case noFocusedElement
    case secureField
    case noSelection
    case unsupported
    case accessibilityError(AXError)
    case pasteUnverified
    case clipboardRestoreFailed
    case clipboardSuperseded

    var description: String {
        switch self {
        case .missingPermission:
            return L10n.string(
                "probe.write.missing_permission",
                defaultValue: "Accessibility access is required before Henge can replace the current selection."
            )
        case .noFocusedElement:
            return L10n.string(
                "probe.write.no_focused_element",
                defaultValue: "No focused text element is currently available for replacement."
            )
        case .secureField:
            return L10n.string(
                "probe.write.secure_field",
                defaultValue: "Focused secure text field detected. Henge left the selection untouched."
            )
        case .noSelection:
            return L10n.string(
                "probe.write.no_selection",
                defaultValue: "No text selection is currently available for replacement."
            )
        case .unsupported:
            return L10n.string(
                "probe.write.unsupported",
                defaultValue: "The focused element does not support direct selection replacement through Accessibility."
            )
        case let .accessibilityError(error):
            return L10n.format(
                "probe.write.accessibility_error",
                defaultValue: "Henge could not replace the current selection (AXError %d).",
                error.rawValue
            )
        case .pasteUnverified:
            return L10n.string(
                "fix_outcome.paste_unverified",
                defaultValue: "Henge attempted clipboard replacement, but could not verify that the text changed."
            )
        case .clipboardRestoreFailed:
            return L10n.string(
                "fix_outcome.failed.clipboard_restore_failed",
                defaultValue: "Henge could not restore the original clipboard contents after replacement."
            )
        case .clipboardSuperseded:
            return L10n.string(
                "fix_outcome.failed.clipboard_superseded",
                defaultValue: "Clipboard contents changed before restoration, so Henge kept the new clipboard contents."
            )
        }
    }
}

struct ResolvedFocusedElement {
    let element: AXUIElement
    let snapshot: FocusedElementSnapshot
}
