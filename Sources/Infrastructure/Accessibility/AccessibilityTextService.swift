import AppKit
import ApplicationServices

protocol AccessibilityElementAccessing {
    func copyAttributeValue(_ attribute: CFString, from element: AXUIElement) -> (AXError, CFTypeRef?)
    func setAttributeValue(_ attribute: CFString, value: CFTypeRef, on element: AXUIElement) -> AXError
}

struct SystemAccessibilityElementAccessor: AccessibilityElementAccessing {
    func copyAttributeValue(_ attribute: CFString, from element: AXUIElement) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        return (status, value)
    }

    func setAttributeValue(_ attribute: CFString, value: CFTypeRef, on element: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(element, attribute, value)
    }
}

final class AccessibilityTextService {
    private let clipboardReplacement: ClipboardReplacing
    private let applicationProvider: ActiveApplicationProviding
    private let permissionProbe: AccessibilityPermissionProbe
    private let elementAccessor: AccessibilityElementAccessing
    private let focusedElementResolver: (() -> Result<ResolvedFocusedElement, FocusedElementProbeFailure>)?

    init(
        clipboardReplacement: ClipboardReplacing,
        applicationProvider: ActiveApplicationProviding = WorkspaceActiveApplicationProvider(),
        permissionProbe: AccessibilityPermissionProbe = AccessibilityPermissionProbe(),
        elementAccessor: AccessibilityElementAccessing = SystemAccessibilityElementAccessor(),
        focusedElementResolver: (() -> Result<ResolvedFocusedElement, FocusedElementProbeFailure>)? = nil
    ) {
        self.clipboardReplacement = clipboardReplacement
        self.applicationProvider = applicationProvider
        self.permissionProbe = permissionProbe
        self.elementAccessor = elementAccessor
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
                case let .success(snapshot):
                    let target = TextTarget(
                        application: application,
                        snapshot: resolvedElement.snapshot,
                        element: resolvedElement.element
                    )
                    return .available(TextContext(target: target, selection: snapshot))
                case let .failure(reason):
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
        let element: AXUIElement
        switch prepareElementForWrite(target, range: range, context: context, expectedText: expectedText) {
        case let .success(preparedElement):
            element = preparedElement
        case let .failure(reason):
            return .unavailable(.probe(reason))
        }

        let replacedRange = SelectionRangeSnapshot(location: range.location, length: text.utf16.count)
        let status = elementAccessor.setAttributeValue(
            kAXSelectedTextAttribute as CFString,
            value: text as CFString,
            on: element
        )
        switch status {
        case .success:
            _ = setSelectedTextRange(
                SelectionRangeSnapshot(location: range.location + text.utf16.count, length: 0),
                on: element
            )
            return .success(replacedRange, viaClipboard: false)

        case .attributeUnsupported:
            guard let targetPID = validatedProcessIdentifier(for: element, in: target.application) else {
                _ = setSelectedTextRange(context.range, on: element)
                return .unavailable(.noFocusedElement)
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
                    return substring(in: replacedRange, of: currentText) == text
                }
            )
            switch replacementResult {
            case .success:
                return .success(replacedRange, viaClipboard: true)
            case .pasteUnverified:
                return .unavailable(.pasteUnverified)
            case .restoreFailed:
                return .unavailable(.clipboardRestoreFailed)
            case .superseded:
                return .unavailable(.clipboardSuperseded)
            case .failed:
                _ = setSelectedTextRange(context.range, on: element)
                return .unavailable(.unsupported)
            }

        default:
            _ = setSelectedTextRange(context.range, on: element)
            return .unavailable(.probe(selectionFailure(from: status)))
        }
    }

    private func prepareElementForWrite(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String
    ) -> Result<AXUIElement, SelectionProbeFailure> {
        guard let element = target.element else { return .failure(.unsupported) }
        guard !target.snapshot.isSecure else { return .failure(.secureField) }
        if let focusFailure = validateFocus(for: element, in: target.application) {
            return .failure(focusFailure)
        }
        guard isCurrentTextContext(context: context, targetRange: range, expectedText: expectedText, element: element) else {
            return .failure(.noSelection)
        }

        let rangeStatus = context.isCaretContext || range != context.range
            ? setSelectedTextRange(range, on: element)
            : .success
        guard rangeStatus == .success else {
            return .failure(selectionFailure(from: rangeStatus))
        }
        return .success(element)
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
        let (status, focusedElementValue) = elementAccessor.copyAttributeValue(
            kAXFocusedUIElementAttribute as CFString,
            from: systemWideElement
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
            let (appStatus, appFocusedValue) = elementAccessor.copyAttributeValue(
                kAXFocusedUIElementAttribute as CFString,
                from: appElement
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

    private func validateFocus(for element: AXUIElement, in application: ApplicationIdentity) -> SelectionProbeFailure? {
        guard validatedProcessIdentifier(for: element, in: application) != nil else {
            return .noFocusedElement
        }
        switch resolveFocusedElement() {
        case let .failure(reason):
            return selectionFailure(from: reason)
        case let .success(currentElement):
            if currentElement.snapshot.isSecure {
                return .secureField
            }
            guard CFEqual(element, currentElement.element),
                  applicationProvider.activeApplication()?.bundleIdentifier == application.bundleIdentifier else {
                return .noFocusedElement
            }
            return nil
        }
    }

    private func isFocusedElement(_ element: AXUIElement, in application: ApplicationIdentity) -> Bool {
        validateFocus(for: element, in: application) == nil
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
        let (status, value) = elementAccessor.copyAttributeValue(attribute, from: element)
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

    private func readSelectedText(from element: AXUIElement, range: SelectionRangeSnapshot) -> Result<SelectionSnapshot, SelectionProbeFailure> {
        let (textStatus, selectedTextValue) = elementAccessor.copyAttributeValue(
            kAXSelectedTextAttribute as CFString,
            from: element
        )
        guard textStatus == .success else {
            return .failure(selectionFailure(from: textStatus))
        }
        guard let text = selectedTextValue as? String else {
            return .failure(.unsupported)
        }
        return .success(SelectionSnapshot(text: text, range: range))
    }

    private func isCurrentTextContext(context: SelectionSnapshot, targetRange: SelectionRangeSnapshot, expectedText: String, element: AXUIElement) -> Bool {
        guard let currentRange = try? copySelectedTextRange(from: element).get(), currentRange == context.range else {
            return false
        }
        if context.isCaretContext {
            guard let currentText = copyStringAttribute(kAXValueAttribute as CFString, from: element), currentText == context.text else {
                return false
            }
            return substring(in: targetRange, of: currentText) == expectedText
        }
        guard let selectedText = copyStringAttribute(kAXSelectedTextAttribute as CFString, from: element) else {
            return false
        }
        return selectedText == context.text
            && targetRange == context.range
            && expectedText == context.text
    }

    private func substring(in range: SelectionRangeSnapshot, of text: String) -> String? {
        Self.substring(in: range, of: text)
    }

    /// Extracts the UTF-16 range from `text`, returning `nil` when the range is
    /// negative, out of bounds, or does not land on character boundaries. The
    /// upper-bound check matters: `String.Index(utf16Offset:in:)` traps when the
    /// offset exceeds the string's UTF-16 length, and the text polled during
    /// paste verification can be shorter than the range captured before the paste.
    static func substring(in range: SelectionRangeSnapshot, of text: String) -> String? {
        let utf16Count = text.utf16.count
        guard range.location >= 0, range.length >= 0,
              range.location <= utf16Count,
              range.length <= utf16Count - range.location,
              let start = String.Index(utf16Offset: range.location, in: text).samePosition(in: text),
              let end = String.Index(utf16Offset: range.location + range.length, in: text).samePosition(in: text),
              start <= end else { return nil }
        return String(text[start..<end])
    }

    private func setSelectedTextRange(_ range: SelectionRangeSnapshot, on element: AXUIElement) -> AXError {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return .failure }
        return elementAccessor.setAttributeValue(kAXSelectedTextRangeAttribute as CFString, value: value, on: element)
    }

    private func copySelectedTextRange(from element: AXUIElement) -> Result<SelectionRangeSnapshot, SelectionProbeFailure> {
        let (status, value) = elementAccessor.copyAttributeValue(
            kAXSelectedTextRangeAttribute as CFString,
            from: element
        )

        guard status == .success else {
            return .failure(selectionFailure(from: status))
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

    private func selectionFailure(from error: AXError) -> SelectionProbeFailure {
        switch error {
        case .attributeUnsupported:
            return .unsupported
        case .noValue:
            return .noSelection
        default:
            return .accessibilityError(error)
        }
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
