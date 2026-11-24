import Testing
@testable import Henge

struct StatusPresenterTests {
    @Test
    func hotkeyStatusTextHandlesRegistrationErrorAndFallbacks() {
        #expect(
            StatusPresenter.hotkeyStatusText(
                registrationError: "Shortcut failed.",
                hotkeyRegistered: true,
                accessibilityGranted: true
            ) == "Shortcut failed. The current shortcut remains active."
        )
        #expect(
            StatusPresenter.hotkeyStatusText(
                registrationError: "Shortcut failed.",
                hotkeyRegistered: false,
                accessibilityGranted: true
            ) == "Shortcut failed."
        )
        #expect(
            StatusPresenter.hotkeyStatusText(
                registrationError: nil,
                hotkeyRegistered: true,
                accessibilityGranted: false
            ).contains("Accessibility access is still required")
        )
        #expect(
            StatusPresenter.hotkeyStatusText(
                registrationError: nil,
                hotkeyRegistered: true,
                accessibilityGranted: true
            ).contains("registered and ready")
        )
        #expect(
            StatusPresenter.hotkeyStatusText(
                registrationError: nil,
                hotkeyRegistered: false,
                accessibilityGranted: true
            ).contains("inactive while Henge is disabled")
        )
    }

    @Test
    func launchAtLoginStatusTextHandlesErrorsAndAllStatuses() {
        #expect(
            StatusPresenter.launchAtLoginStatusText(error: "Login failed", status: .enabled) == "Login failed"
        )
        #expect(
            StatusPresenter.launchAtLoginStatusText(error: nil, status: .enabled) == "Launch at Login is enabled."
        )
        #expect(
            StatusPresenter.launchAtLoginStatusText(error: nil, status: .disabled) == "Launch at Login is disabled."
        )
        #expect(
            StatusPresenter.launchAtLoginStatusText(error: nil, status: .requiresApproval).contains("Approval required")
        )
    }

    @Test
    func lastProbeStatusTextFormatsFixOutcomeAndNil() {
        #expect(
            StatusPresenter.lastProbeStatusText(
                lastFixOutcome: .fixed(viaClipboard: false)
            ) == "Text corrected."
        )
        #expect(
            StatusPresenter.lastProbeStatusText(
                lastFixOutcome: nil
            ) == nil
        )
    }

    @Test
    func statusItemStateAndSymbolNameDeriveExpectedStates() {
        let disabled = StatusPresenter.statusItemState(
            isEnabled: false,
            accessibilityGranted: false,
            hotkeyRegistered: false
        )
        #expect(disabled == .disabled)
        #expect(StatusPresenter.statusItemSymbolName(for: disabled) == "cloud")

        let permission = StatusPresenter.statusItemState(
            isEnabled: true,
            accessibilityGranted: false,
            hotkeyRegistered: true
        )
        #expect(permission == .permissionRequired)
        #expect(StatusPresenter.statusItemSymbolName(for: permission) == "exclamationmark.cloud")

        let degraded = StatusPresenter.statusItemState(
            isEnabled: true,
            accessibilityGranted: true,
            hotkeyRegistered: false
        )
        #expect(degraded == .degraded)
        #expect(StatusPresenter.statusItemSymbolName(for: degraded) == "exclamationmark.cloud")

        let active = StatusPresenter.statusItemState(
            isEnabled: true,
            accessibilityGranted: true,
            hotkeyRegistered: true
        )
        #expect(active == .active)
        #expect(StatusPresenter.statusItemSymbolName(for: active) == "cloud.fill")
    }
}
