import ApplicationServices
import Carbon
import Cocoa

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

protocol AppRuntime {
    var hasAccessibilityPermission: Bool { get }
    var activeApplication: ApplicationIdentity? { get }
    func applicationIdentity(for bundleIdentifier: String) -> ApplicationIdentity?
    var layoutMapper: LayoutMapping { get }
    var clipboardManager: ClipboardManaging { get }

    func openAccessibilitySettings()
    func requestAccessibilityPermission()
    func setActivationHandler(_ handler: (@Sendable () -> Void)?)
    @MainActor
    func prepareTargetApplicationForFixText(_ application: ApplicationIdentity) async -> Bool
    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws
    func unregisterFixTextHotkey()
    func inspectFocusedElement() -> FocusedElementProbe
    func inspectTextContext(in application: ApplicationIdentity) -> TextContextProbe
    func replaceText(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult
    func replaceTextUsingClipboard(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult
}

extension AppRuntime {
    func requestAccessibilityPermission() {
        openAccessibilitySettings()
    }

    func setActivationHandler(_ handler: (@Sendable () -> Void)?) {}

    @MainActor
    func prepareTargetApplicationForFixText(_ application: ApplicationIdentity) async -> Bool {
        true
    }

    func applicationIdentity(for bundleIdentifier: String) -> ApplicationIdentity? {
        ApplicationIdentity(bundleIdentifier: bundleIdentifier, displayName: bundleIdentifier)
    }

    func replaceTextUsingClipboard(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult {
        .unavailable(.unsupported)
    }
}

enum HotkeyRegistrationError: Error {
    case unsupportedShortcut(String)
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
}

extension HotkeyRegistrationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .unsupportedShortcut(key):
            return L10n.format(
                "hotkey.error.unsupported_shortcut",
                defaultValue: "The shortcut key %@ is not supported by the current global hotkey backend.",
                key
            )
        case let .eventHandlerInstallationFailed(status):
            return L10n.format(
                "hotkey.error.event_handler_failed",
                defaultValue: "Henge could not install the global hotkey event handler (OSStatus %d).",
                status
            )
        case let .registrationFailed(status):
            return L10n.format(
                "hotkey.error.registration_failed",
                defaultValue: "Henge could not register the global hotkey (OSStatus %d).",
                status
            )
        }
    }
}

final class LiveAppRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool {
        permissionProbe.isTrusted()
    }

    let layoutMapper: LayoutMapping
    let clipboardManager: ClipboardManaging
    private let clipboardReplacement: ClipboardReplacing
    private let applicationProvider: ActiveApplicationProviding
    private let permissionProbe: AccessibilityPermissionProbe
    private let focusedElementResolver: (() -> Result<ResolvedFocusedElement, FocusedElementProbeFailure>)?
    private let globalHotkeyCenter = GlobalHotkeyCenter()

    var activeApplication: ApplicationIdentity? {
        applicationProvider.activeApplication()
    }

    func applicationIdentity(for bundleIdentifier: String) -> ApplicationIdentity? {
        applicationProvider.application(bundleIdentifier: bundleIdentifier)
    }

    func setActivationHandler(_ handler: (@Sendable () -> Void)?) {
        guard let handler else {
            applicationProvider.setActivationHandler(nil)
            return
        }

        let permissionProbe = permissionProbe
        applicationProvider.setActivationHandler {
            permissionProbe.invalidate()
            handler()
        }
    }

    init(
        layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper(),
        clipboardManager: ClipboardManaging = AppKitClipboardManager(),
        clipboardReplacement: ClipboardReplacing? = nil,
        applicationProvider: ActiveApplicationProviding = WorkspaceActiveApplicationProvider(),
        permissionProbe: AccessibilityPermissionProbe = AccessibilityPermissionProbe(),
        focusedElementResolver: (() -> Result<ResolvedFocusedElement, FocusedElementProbeFailure>)? = nil
    ) {
        self.layoutMapper = layoutMapper
        self.clipboardManager = clipboardManager
        self.clipboardReplacement = clipboardReplacement ?? AppKitClipboardReplacement(clipboardManager: clipboardManager)
        self.applicationProvider = applicationProvider
        self.permissionProbe = permissionProbe
        self.focusedElementResolver = focusedElementResolver
    }

    func openAccessibilitySettings() {
        permissionProbe.invalidate()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        let openURL: @Sendable () -> Void = {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(url, configuration: configuration)
        }

        if Thread.isMainThread, RunLoop.main.currentMode == .eventTracking {
            RunLoop.main.perform(inModes: [.default]) {
                openURL()
            }
        } else {
            openURL()
        }
    }

    func requestAccessibilityPermission() {
        if !AXIsProcessTrusted() {
            // kAXTrustedCheckOptionPrompt is the literal "AXTrustedCheckOptionPrompt"
            // (Swift 6 concurrency: the exported var is not sendable-safe).
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        permissionProbe.invalidate()
        openAccessibilitySettings()
    }

    @MainActor
    func prepareTargetApplicationForFixText(_ application: ApplicationIdentity) async -> Bool {
        if RunLoop.main.currentMode == .eventTracking {
            await withCheckedContinuation { continuation in
                RunLoop.main.perform(inModes: [.default]) {
                    continuation.resume()
                }
            }
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        if applicationProvider.isFrontmost(application),
           NSApplication.shared.isActive == false,
           case .success = resolveFocusedElement() {
            return true
        }

        guard applicationProvider.activateApplication(application) else {
            return false
        }

        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            if applicationProvider.isFrontmost(application),
               case .success = resolveFocusedElement() {
                return true
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            await applicationProvider.waitForActivation(of: application, timeout: remaining)
        }

        return applicationProvider.isFrontmost(application)
    }

    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {
        try globalHotkeyCenter.register(shortcut: shortcut, handler: handler)
    }

    func unregisterFixTextHotkey() {
        globalHotkeyCenter.unregister()
    }

    func inspectFocusedElement() -> FocusedElementProbe {
        switch resolveFocusedElement() {
        case let .failure(reason):
            return .unavailable(reason)
        case let .success(resolvedElement):
            return .available(resolvedElement.snapshot)
        }
    }

    func inspectTextContext(in application: ApplicationIdentity) -> TextContextProbe {
        switch resolveFocusedElement() {
        case let .failure(reason):
            return .unavailable(selectionFailure(from: reason))
        case let .success(resolvedElement) where resolvedElement.snapshot.isSecure:
            return .unavailable(.secureField)
        case let .success(resolvedElement):
            guard validatedProcessIdentifier(for: resolvedElement.element, in: application) != nil else {
                return .unavailable(.noFocusedElement)
            }
            let rangeResult = copySelectedTextRange(from: resolvedElement.element)
            guard case let .success(range) = rangeResult else {
                if case let .failure(error) = rangeResult {
                    return .unavailable(error)
                }
                return .unavailable(.unsupported)
            }

            if range.length > 0 {
                switch readSelectedText(from: resolvedElement.element, range: range) {
                case let .available(snapshot):
                    let target = TextTarget(
                        application: application,
                        snapshot: resolvedElement.snapshot,
                        element: resolvedElement.element
                    )
                    return .available(TextContext(target: target, selection: snapshot))
                case let .unavailable(reason):
                    return .unavailable(reason)
                }
            }

            guard let text = copyStringAttribute(kAXValueAttribute as CFString, from: resolvedElement.element) else {
                return .unavailable(.unsupported)
            }
            let target = TextTarget(
                application: application,
                snapshot: resolvedElement.snapshot,
                element: resolvedElement.element
            )
            return .available(
                TextContext(
                    target: target,
                    selection: SelectionSnapshot(text: text, range: range, isCaretContext: true)
                )
            )
        }
    }

    func replaceText(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult {
        guard let element = target.element else { return .unavailable(.unsupported) }
        guard !target.snapshot.isSecure else { return .unavailable(.secureField) }
        guard isFocusedElement(element, in: target.application) else { return .unavailable(.unsupported) }
        guard isCurrentTextContext(context: context, targetRange: range, expectedText: expectedText, element: element) else {
            return .unavailable(.unsupported)
        }

        let rangeStatus = context.isCaretContext || range != context.range
            ? setSelectedTextRange(range, on: element)
            : .success
        guard rangeStatus == .success else {
            return .unavailable(writeFailure(from: rangeStatus))
        }

        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        guard status == .success else {
            _ = setSelectedTextRange(context.range, on: element)
            return .unavailable(writeFailure(from: status))
        }
        _ = setSelectedTextRange(
            SelectionRangeSnapshot(location: range.location + text.utf16.count, length: 0),
            on: element
        )
        return .success(SelectionRangeSnapshot(location: range.location, length: text.utf16.count))
    }

    func replaceTextUsingClipboard(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult {
        guard let element = target.element else { return .unavailable(.unsupported) }
        guard !target.snapshot.isSecure else { return .unavailable(.secureField) }
        guard isFocusedElement(element, in: target.application) else { return .unavailable(.unsupported) }
        guard isCurrentTextContext(context: context, targetRange: range, expectedText: expectedText, element: element) else {
            return .unavailable(.unsupported)
        }

        let rangeStatus = context.isCaretContext || range != context.range
            ? setSelectedTextRange(range, on: element)
            : .success
        guard rangeStatus == .success else {
            return .unavailable(.unsupported)
        }
        guard let targetPID = validatedProcessIdentifier(for: element, in: target.application) else {
            return .unavailable(.unsupported)
        }
        let replacementResult = clipboardReplacement.replaceSelection(
            expectedText: expectedText,
            with: text,
            processIdentifier: targetPID,
            validateTarget: { [self] in isFocusedElement(element, in: target.application) },
            verifyReplacement: { [self] in
                guard let currentText = copyStringAttribute(kAXValueAttribute as CFString, from: element) else {
                    return false
                }
                return substring(
                    in: SelectionRangeSnapshot(location: range.location, length: text.utf16.count),
                    of: currentText
                ) == text
            }
        )
        switch replacementResult {
        case .success:
            return .success(SelectionRangeSnapshot(location: range.location, length: text.utf16.count))
        case .pasteUnverified:
            return .unavailable(.pasteUnverified)
        case .restoreFailed:
            return .unavailable(.clipboardRestoreFailed)
        case .superseded:
            return .unavailable(.clipboardSuperseded)
        case .failed:
            return .unavailable(.unsupported)
        }
    }

    private func isFocusedElement(_ element: AXUIElement, in application: ApplicationIdentity) -> Bool {
        guard validatedProcessIdentifier(for: element, in: application) != nil else { return false }
        guard case let .success(currentElement) = resolveFocusedElement(),
              !currentElement.snapshot.isSecure,
              CFEqual(element, currentElement.element) else { return false }
        return activeApplication?.bundleIdentifier == application.bundleIdentifier
    }

    private func validatedProcessIdentifier(for element: AXUIElement, in application: ApplicationIdentity) -> pid_t? {
        guard activeApplication?.bundleIdentifier == application.bundleIdentifier else { return nil }
        var targetPID: pid_t = 0
        guard AXUIElementGetPid(element, &targetPID) == .success,
              targetPID != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        if NSRunningApplication(processIdentifier: targetPID)?.bundleIdentifier == application.bundleIdentifier {
            return targetPID
        }
        if applicationProvider.activeProcessIdentifier(for: application) == targetPID {
            return targetPID
        }
        return nil
    }

    private func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard status == .success else {
            return nil
        }

        return value as? String
    }

    private func makeResolvedFocusedElement(from focusedElement: AXUIElement) -> ResolvedFocusedElement {
        let role = copyStringAttribute(kAXRoleAttribute as CFString, from: focusedElement)
        let subrole = copyStringAttribute(kAXSubroleAttribute as CFString, from: focusedElement)
        let isSecure = role == "AXSecureTextField" || subrole == "AXSecureTextField"

        return ResolvedFocusedElement(
            element: focusedElement,
            snapshot: FocusedElementSnapshot(
                role: role,
                subrole: subrole,
                isSecure: isSecure
            )
        )
    }

    private func resolveFocusedElement() -> Result<ResolvedFocusedElement, FocusedElementProbeFailure> {
        if let focusedElementResolver {
            return focusedElementResolver()
        }

        guard hasAccessibilityPermission else {
            return .failure(.missingPermission)
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )

        if status == .success,
           let focusedElementValue,
           CFGetTypeID(focusedElementValue) == AXUIElementGetTypeID() {
            let focusedElement = unsafeDowncast(focusedElementValue, to: AXUIElement.self)
            var elementPID: pid_t = 0
            if AXUIElementGetPid(focusedElement, &elementPID) == .success, elementPID != ownPID {
                return .success(makeResolvedFocusedElement(from: focusedElement))
            }
        }

        if let targetApplication = activeApplication,
           let targetPID = applicationProvider.activeProcessIdentifier(for: targetApplication),
           targetPID != ownPID {
            let appElement = AXUIElementCreateApplication(targetPID)
            var appFocusedValue: CFTypeRef?
            let appStatus = AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                &appFocusedValue
            )
            if appStatus == .success,
               let appFocusedValue,
               CFGetTypeID(appFocusedValue) == AXUIElementGetTypeID() {
                let focusedElement = unsafeDowncast(appFocusedValue, to: AXUIElement.self)
                return .success(makeResolvedFocusedElement(from: focusedElement))
            }
        }

        switch status {
        case .success, .noValue, .attributeUnsupported:
            return .failure(.noFocusedElement)
        default:
            return .failure(.accessibilityError(status))
        }
    }

    private func readSelectedText(from element: AXUIElement, range: SelectionRangeSnapshot) -> SelectionProbe {
        var selectedTextValue: CFTypeRef?
        let textStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        guard textStatus == .success else {
            switch textStatus {
            case .attributeUnsupported: return .unavailable(.unsupported)
            case .noValue: return .unavailable(.noSelection)
            default: return .unavailable(.accessibilityError(textStatus))
            }
        }
        guard let text = selectedTextValue as? String else {
            return .unavailable(.unsupported)
        }
        return .available(SelectionSnapshot(text: text, range: range))
    }

    private func isCurrentTextContext(context: SelectionSnapshot, targetRange: SelectionRangeSnapshot, expectedText: String, element: AXUIElement) -> Bool {
        guard let currentRange = copySelectedTextRangeForWrite(from: element), currentRange == context.range else {
            return false
        }
        if context.isCaretContext {
            guard let currentText = copyStringAttribute(kAXValueAttribute as CFString, from: element), currentText == context.text else {
                return false
            }
            return substring(in: targetRange, of: currentText) == expectedText
        }
        var selectedTextValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success else {
            return false
        }
        return (selectedTextValue as? String) == context.text
            && targetRange == context.range
            && expectedText == context.text
    }

    private func substring(in range: SelectionRangeSnapshot, of text: String) -> String? {
        guard range.location >= 0, range.length >= 0,
              let start = String.Index(utf16Offset: range.location, in: text).samePosition(in: text),
              let end = String.Index(utf16Offset: range.location + range.length, in: text).samePosition(in: text),
              start <= end else { return nil }
        return String(text[start..<end])
    }

    private func copySelectedTextRangeForWrite(from element: AXUIElement) -> SelectionRangeSnapshot? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard status == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }
        let typedValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(typedValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(typedValue, .cfRange, &range) else { return nil }
        return SelectionRangeSnapshot(location: range.location, length: range.length)
    }

    private func setSelectedTextRange(_ range: SelectionRangeSnapshot, on element: AXUIElement) -> AXError {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
    }

    private func writeFailure(from error: AXError) -> SelectionWriteFailure {
        switch error {
        case .attributeUnsupported: return .unsupported
        case .noValue: return .noSelection
        default: return .accessibilityError(error)
        }
    }

    private func copySelectedTextRange(from element: AXUIElement) -> Result<SelectionRangeSnapshot, SelectionProbeFailure> {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard status == .success else {
            switch status {
            case .attributeUnsupported:
                return .failure(.unsupported)
            case .noValue:
                return .failure(.noSelection)
            default:
                return .failure(.accessibilityError(status))
            }
        }

        guard let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return .failure(.unsupported)
        }

        let typedValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(typedValue) == .cfRange else {
            return .failure(.unsupported)
        }

        var range = CFRange()
        guard AXValueGetValue(typedValue, .cfRange, &range) else {
            return .failure(.unsupported)
        }

        return .success(SelectionRangeSnapshot(location: range.location, length: range.length))
    }

    private func selectionFailure(from focusedElementFailure: FocusedElementProbeFailure) -> SelectionProbeFailure {
        switch focusedElementFailure {
        case .missingPermission:
            return .missingPermission
        case .noFocusedElement:
            return .noFocusedElement
        case let .accessibilityError(error):
            return .accessibilityError(error)
        }
    }
}

struct ResolvedFocusedElement {
    let element: AXUIElement
    let snapshot: FocusedElementSnapshot
}

private final class GlobalHotkeyCenter {
    private let hotkeyID = EventHotKeyID(signature: 0x484E4745, id: 1)

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var currentShortcut: Shortcut?
    private var handler: (() -> Void)?

    deinit {
        unregister()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(shortcut: Shortcut, handler: @escaping () -> Void) throws {
        try installEventHandlerIfNeeded()

        let hotkey = try CarbonHotkey(shortcut: shortcut)

        if hotKey != nil, currentShortcut == shortcut {
            self.handler = handler
            return
        }

        var newHotKey: EventHotKeyRef?

        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKey
        )

        guard status == noErr else {
            throw HotkeyRegistrationError.registrationFailed(status)
        }

        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = newHotKey
        currentShortcut = shortcut
        self.handler = handler
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }

        currentShortcut = nil
        handler = nil
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                let center = Unmanaged<GlobalHotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                return center.handleHotKeyEvent(event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            throw HotkeyRegistrationError.eventHandlerInstallationFailed(status)
        }
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var registeredHotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &registeredHotkeyID
        )

        guard status == noErr else {
            return status
        }

        guard registeredHotkeyID.signature == hotkeyID.signature, registeredHotkeyID.id == hotkeyID.id else {
            return noErr
        }

        handler?()

        return noErr
    }
}

struct CarbonHotkey {
    let keyCode: UInt32
    let modifiers: UInt32

    private static let specialKeyLabels: [UInt32: String] = [
        UInt32(kVK_Return): "↩",
        UInt32(kVK_ANSI_KeypadEnter): "↩",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
    ]

    private static let ansiKeyLabels: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_ANSI_Backslash): "\\",
    ]

    /// Carbon HIToolbox key codes are a platform concern, so support for a
    /// shortcut key is decided here rather than in the domain model.
    static func isSupported(key: String) -> Bool {
        keyCode(for: key) != nil
    }

    static func isSupported(keyCode: UInt32) -> Bool {
        specialKeyLabels[keyCode] != nil || ansiKeyLabels[keyCode] != nil
    }

    static func isSupported(shortcut: Shortcut) -> Bool {
        if let explicitKeyCode = shortcut.keyCode {
            return isSupported(keyCode: explicitKeyCode)
        }
        return keyCode(for: shortcut.key) != nil
    }

    static func displayKey(forKeyCode keyCode: UInt32) -> String? {
        if let special = specialKeyLabels[keyCode] {
            return special
        }

        guard let fallback = ansiKeyLabels[keyCode] else {
            return nil
        }

        return asciiCapableKeyLabel(forKeyCode: UInt16(keyCode)) ?? fallback
    }

    init(shortcut: Shortcut) throws {
        let resolvedKeyCode: UInt32
        if let explicitKeyCode = shortcut.keyCode {
            guard Self.isSupported(keyCode: explicitKeyCode) else {
                throw HotkeyRegistrationError.unsupportedShortcut(shortcut.key)
            }
            resolvedKeyCode = explicitKeyCode
        } else if let mappedKeyCode = Self.keyCode(for: shortcut.key) {
            resolvedKeyCode = mappedKeyCode
        } else {
            throw HotkeyRegistrationError.unsupportedShortcut(shortcut.key)
        }

        self.keyCode = resolvedKeyCode
        modifiers = Self.modifiers(for: shortcut.modifiers)
    }

    private static var isRunningInTestingEnvironment: Bool {
        let processName = ProcessInfo.processInfo.processName.lowercased()
        if processName.contains("test") || processName.contains("testing-helper") {
            return true
        }
        return ProcessInfo.processInfo.arguments.contains {
            let lower = $0.lowercased()
            return lower.contains("testing-helper") || lower.contains(".xctest")
        }
    }

    private static func asciiCapableKeyLabel(forKeyCode keyCode: UInt16) -> String? {
        guard !isRunningInTestingEnvironment, Thread.isMainThread else {
            return nil
        }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let cfData = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue()
        guard let layoutBytes = CFDataGetBytePtr(cfData) else {
            return nil
        }
        let keyboardLayout = UnsafeRawPointer(layoutBytes).bindMemory(to: UCKeyboardLayout.self, capacity: 1)
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var actualLength = 0
        var unicodeString = [UniChar](repeating: 0, count: maxLength)

        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxLength,
            &actualLength,
            &unicodeString
        )

        guard status == noErr, actualLength > 0 else {
            return nil
        }

        let translated = String(utf16CodeUnits: unicodeString, count: actualLength)
        guard translated.count == 1,
              let scalar = translated.unicodeScalars.first,
              scalar.value >= 0x21 && scalar.value <= 0x7E else {
            return nil
        }

        return translated.uppercased()
    }

    private static func modifiers(for modifiers: Shortcut.Modifiers) -> UInt32 {
        var carbonModifiers: UInt32 = 0

        if modifiers.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }

        if modifiers.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }

        if modifiers.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }

        if modifiers.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }

        return carbonModifiers
    }

    private static func keyCode(for key: String) -> UInt32? {
        if key.count == 1 {
            switch key.uppercased() {
            case "A": return UInt32(kVK_ANSI_A)
            case "B": return UInt32(kVK_ANSI_B)
            case "C": return UInt32(kVK_ANSI_C)
            case "D": return UInt32(kVK_ANSI_D)
            case "E": return UInt32(kVK_ANSI_E)
            case "F": return UInt32(kVK_ANSI_F)
            case "G": return UInt32(kVK_ANSI_G)
            case "H": return UInt32(kVK_ANSI_H)
            case "I": return UInt32(kVK_ANSI_I)
            case "J": return UInt32(kVK_ANSI_J)
            case "K": return UInt32(kVK_ANSI_K)
            case "L": return UInt32(kVK_ANSI_L)
            case "M": return UInt32(kVK_ANSI_M)
            case "N": return UInt32(kVK_ANSI_N)
            case "O": return UInt32(kVK_ANSI_O)
            case "P": return UInt32(kVK_ANSI_P)
            case "Q": return UInt32(kVK_ANSI_Q)
            case "R": return UInt32(kVK_ANSI_R)
            case "S": return UInt32(kVK_ANSI_S)
            case "T": return UInt32(kVK_ANSI_T)
            case "U": return UInt32(kVK_ANSI_U)
            case "V": return UInt32(kVK_ANSI_V)
            case "W": return UInt32(kVK_ANSI_W)
            case "X": return UInt32(kVK_ANSI_X)
            case "Y": return UInt32(kVK_ANSI_Y)
            case "Z": return UInt32(kVK_ANSI_Z)
            case "0": return UInt32(kVK_ANSI_0)
            case "1": return UInt32(kVK_ANSI_1)
            case "2": return UInt32(kVK_ANSI_2)
            case "3": return UInt32(kVK_ANSI_3)
            case "4": return UInt32(kVK_ANSI_4)
            case "5": return UInt32(kVK_ANSI_5)
            case "6": return UInt32(kVK_ANSI_6)
            case "7": return UInt32(kVK_ANSI_7)
            case "8": return UInt32(kVK_ANSI_8)
            case "9": return UInt32(kVK_ANSI_9)
            case "-": return UInt32(kVK_ANSI_Minus)
            case "=": return UInt32(kVK_ANSI_Equal)
            case "[": return UInt32(kVK_ANSI_LeftBracket)
            case "]": return UInt32(kVK_ANSI_RightBracket)
            case ";": return UInt32(kVK_ANSI_Semicolon)
            case "'": return UInt32(kVK_ANSI_Quote)
            case ",": return UInt32(kVK_ANSI_Comma)
            case ".": return UInt32(kVK_ANSI_Period)
            case "/": return UInt32(kVK_ANSI_Slash)
            case "`": return UInt32(kVK_ANSI_Grave)
            case "\\": return UInt32(kVK_ANSI_Backslash)
            case " ": return UInt32(kVK_Space)
            case "↩": return UInt32(kVK_Return)
            case "←": return UInt32(kVK_LeftArrow)
            case "→": return UInt32(kVK_RightArrow)
            case "↑": return UInt32(kVK_UpArrow)
            case "↓": return UInt32(kVK_DownArrow)
            default: return nil
            }
        }

        switch key.lowercased() {
        case "space": return UInt32(kVK_Space)
        case "return", "enter": return UInt32(kVK_Return)
        case "left", "leftarrow": return UInt32(kVK_LeftArrow)
        case "right", "rightarrow": return UInt32(kVK_RightArrow)
        case "up", "uparrow": return UInt32(kVK_UpArrow)
        case "down", "downarrow": return UInt32(kVK_DownArrow)
        case "f1": return UInt32(kVK_F1)
        case "f2": return UInt32(kVK_F2)
        case "f3": return UInt32(kVK_F3)
        case "f4": return UInt32(kVK_F4)
        case "f5": return UInt32(kVK_F5)
        case "f6": return UInt32(kVK_F6)
        case "f7": return UInt32(kVK_F7)
        case "f8": return UInt32(kVK_F8)
        case "f9": return UInt32(kVK_F9)
        case "f10": return UInt32(kVK_F10)
        case "f11": return UInt32(kVK_F11)
        case "f12": return UInt32(kVK_F12)
        default: return nil
        }
    }
}
