import Foundation

/// Pure formatting functions translating application state and fix outcomes
/// into localized status text and menu-bar icon states.
struct StatusPresenter {
    static func hotkeyStatusText(
        registrationError: String?,
        hotkeyRegistered: Bool,
        accessibilityGranted: Bool
    ) -> String {
        if let hotkeyRegistrationError = registrationError {
            return hotkeyRegistered
                ? L10n.format(
                    "hotkey.status.error_with_active_fallback",
                    defaultValue: "%@ The current shortcut remains active.",
                    hotkeyRegistrationError
                )
                : hotkeyRegistrationError
        }

        if hotkeyRegistered, !accessibilityGranted {
            return L10n.string(
                "hotkey.status.registered_accessibility_required",
                defaultValue: "Global shortcut is registered, but Accessibility access is still required for text operations."
            )
        }

        return hotkeyRegistered
            ? L10n.string(
                "hotkey.status.registered_ready",
                defaultValue: "Global shortcut is registered and ready for native validation."
            )
            : L10n.string(
                "hotkey.status.inactive_disabled",
                defaultValue: "Global shortcut is inactive while Henge is disabled."
            )
    }

    static func launchAtLoginStatusText(
        error: String?,
        status: LoginItemStatus
    ) -> String {
        if let error {
            return error
        }

        switch status {
        case .enabled:
            return L10n.string(
                "launch_at_login.status.enabled",
                defaultValue: "Launch at Login is enabled."
            )
        case .disabled:
            return L10n.string(
                "launch_at_login.status.disabled",
                defaultValue: "Launch at Login is disabled."
            )
        case .requiresApproval:
            return L10n.string(
                "launch_at_login.status.requires_approval",
                defaultValue: "Approval required in System Settings → Login Items."
            )
        }
    }

    static func lastProbeStatusText(
        lastFixOutcome: FixOutcome?,
        lastProbeSummary: String?
    ) -> String? {
        if let outcome = lastFixOutcome {
            return statusText(for: outcome)
        }
        return lastProbeSummary
    }

    static func focusedElementResolvedText(summary: String) -> String {
        L10n.format(
            "probe.status.focused_element_resolved",
            defaultValue: "Focused element resolved: %@.",
            summary
        )
    }

    static func statusText(for outcome: FixOutcome) -> String? {
        switch outcome {
        case .fixed(viaClipboard: false):
            return L10n.string("fix_outcome.fixed_direct", defaultValue: "Text corrected.")
        case .fixed(viaClipboard: true):
            return L10n.string(
                "fix_outcome.fixed_clipboard",
                defaultValue: "Text corrected using the clipboard fallback."
            )
        case .nothingToFix:
            return L10n.string(
                "fix_outcome.nothing_to_fix",
                defaultValue: "Nothing to fix in the current text."
            )
        case .secureField:
            return L10n.string(
                "fix_outcome.secure_field",
                defaultValue: "Focused secure text field detected. Henge left the content untouched."
            )
        case .excluded:
            return nil
        case .unsupported:
            return L10n.string(
                "fix_outcome.unsupported",
                defaultValue: "The focused element does not support text replacement."
            )
        case .pasteUnverified:
            return L10n.string(
                "fix_outcome.paste_unverified",
                defaultValue: "Henge attempted clipboard replacement, but could not verify that the text changed."
            )
        case let .failed(reason):
            switch reason {
            case .noActiveApplication:
                return L10n.string(
                    "fix_outcome.failed.no_active_application",
                    defaultValue: "Henge could not identify the active application and left the text untouched."
                )
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
            case let .accessibilityError(code):
                return L10n.format(
                    "fix_outcome.failed.accessibility_error",
                    defaultValue: "Henge could not inspect or update the focused element (AXError %d).",
                    code
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
            case let .focusLost(applicationName):
                return L10n.format(
                    "fix_outcome.failed.focus_lost",
                    defaultValue: "Henge could not restore focus to %@ and left the text untouched.",
                    applicationName
                )
            }
        }
    }

    static func statusItemState(
        isEnabled: Bool,
        accessibilityGranted: Bool,
        hotkeyRegistered: Bool
    ) -> MenuBarIconState {
        guard isEnabled else {
            return .disabled
        }

        if !accessibilityGranted {
            return .permissionRequired
        }

        if !hotkeyRegistered {
            return .degraded
        }

        return .active
    }

    static func statusItemSymbolName(for state: MenuBarIconState) -> String {
        switch state {
        case .disabled:
            return "cloud"
        case .permissionRequired, .degraded:
            return "exclamationmark.cloud"
        case .active:
            return "cloud.fill"
        }
    }
}
