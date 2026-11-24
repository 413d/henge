import AppKit
import ApplicationServices

final class AccessibilityTextService {
    private let clipboardReplacement: ClipboardReplacing
    private let applicationProvider: ActiveApplicationProviding
    private let permissionProbe: AccessibilityPermissionProbe
    private let focusedElementResolver: (() -> Result<ResolvedFocusedElement, FocusedElementProbeFailure>)?

    init(
        clipboardReplacement: ClipboardReplacing,
        applicationProvider: ActiveApplicationProviding = WorkspaceActiveApplicationProvider(),
        permissionProbe: AccessibilityPermissionProbe = AccessibilityPermissionProbe(),
        focusedElementResolver: (() -> Result<ResolvedFocusedElement, FocusedElementProbeFailure>)? = nil
    ) {
        self.clipboardReplacement = clipboardReplacement
        self.applicationProvider = applicationProvider
        self.permissionProbe = permissionProbe
        self.focusedElementResolver = focusedElementResolver
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

    func resolveFocusedElement() -> Result<ResolvedFocusedElement, FocusedElementProbeFailure> {
        if let focusedElementResolver {
            return focusedElementResolver()
        }

        guard permissionProbe.isTrusted() else {
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

        if let targetApplication = applicationProvider.activeApplication(),
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

    private func isFocusedElement(_ element: AXUIElement, in application: ApplicationIdentity) -> Bool {
        guard validatedProcessIdentifier(for: element, in: application) != nil else { return false }
        guard case let .success(currentElement) = resolveFocusedElement(),
              !currentElement.snapshot.isSecure,
              CFEqual(element, currentElement.element) else { return false }
        return applicationProvider.activeApplication()?.bundleIdentifier == application.bundleIdentifier
    }

    private func validatedProcessIdentifier(for element: AXUIElement, in application: ApplicationIdentity) -> pid_t? {
        guard applicationProvider.activeApplication()?.bundleIdentifier == application.bundleIdentifier else { return nil }
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
