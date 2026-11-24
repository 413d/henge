import Foundation

enum FixTextAvailability: Equatable {
    case available
    case deferred(String)
}

protocol FixTextUseCaseProtocol {
    var availability: FixTextAvailability { get }

    @discardableResult
    func execute(excludingApplicationBundleIdentifiers: [String]) -> FixOutcome
}

extension FixTextUseCaseProtocol {
    @discardableResult
    func execute() -> FixOutcome {
        execute(excludingApplicationBundleIdentifiers: [])
    }
}

struct DeferredFixTextUseCase: FixTextUseCaseProtocol {
    let availability: FixTextAvailability = .deferred(
        L10n.string(
            "fix_text.availability.deferred",
            defaultValue: "Text correction remains unavailable while Milestone 1 native hotkey and text-integration spikes are being validated."
        )
    )

    @discardableResult
    func execute(excludingApplicationBundleIdentifiers: [String]) -> FixOutcome {
        .unsupported
    }
}

struct LiveFixTextUseCase: FixTextUseCaseProtocol {
    let availability: FixTextAvailability = .available

    private let runtime: AppRuntime
    private let transformer: TextTransforming
    private let wordBoundaryDetector: WordBoundaryDetecting
    private let exceptionMatcher: ExceptionMatcher

    init(
        runtime: AppRuntime,
        transformer: TextTransforming,
        wordBoundaryDetector: WordBoundaryDetecting = DefaultWordBoundaryDetector(),
        exceptionMatcher: ExceptionMatcher = ExceptionMatcher()
    ) {
        self.runtime = runtime
        self.transformer = transformer
        self.wordBoundaryDetector = wordBoundaryDetector
        self.exceptionMatcher = exceptionMatcher
    }

    @discardableResult
    func execute(excludingApplicationBundleIdentifiers: [String]) -> FixOutcome {
        guard let application = runtime.activeApplication else {
            return .failed(.noActiveApplication)
        }
        guard !exceptionMatcher.contains(application, in: Set(excludingApplicationBundleIdentifiers)) else {
            return .excluded
        }

        let resolvedContext: TextContext
        switch runtime.inspectTextContext(in: application) {
        case let .available(context):
            resolvedContext = context
        case let .unavailable(reason):
            return outcome(from: reason)
        }

        let context = resolvedContext.selection
        let targetRange: SelectionRangeSnapshot
        let targetText: String
        if context.isCaretContext {
            guard let caretOffset = characterOffset(forUTF16Offset: context.range.location, in: context.text),
                  let boundary = wordBoundaryDetector.detect(in: context.text, caretOffset: caretOffset),
                  let range = utf16Range(forCharacterRange: boundary.range, in: context.text) else {
                return .nothingToFix
            }
            targetRange = range
            targetText = boundary.text
        } else {
            targetRange = context.range
            targetText = context.text
        }

        guard case let .transformed(replacement) = transformer.transform(targetText) else {
            return .nothingToFix
        }

        let directResult = runtime.replaceText(
            resolvedContext.target,
            range: targetRange,
            context: context,
            expectedText: targetText,
            with: replacement
        )
        switch directResult {
        case .success:
            return .fixed(viaClipboard: false)
        case .unavailable(.unsupported):
            break
        case let .unavailable(reason):
            return outcome(from: reason)
        }

        let clipboardResult = runtime.replaceTextUsingClipboard(
            resolvedContext.target,
            range: targetRange,
            context: context,
            expectedText: targetText,
            with: replacement
        )
        switch clipboardResult {
        case .success:
            return .fixed(viaClipboard: true)
        case let .unavailable(reason):
            return outcome(from: reason)
        }
    }

    private func outcome(from failure: SelectionProbeFailure) -> FixOutcome {
        switch failure {
        case .missingPermission:
            return .failed(.missingPermission)
        case .noFocusedElement:
            return .failed(.noFocusedElement)
        case .secureField:
            return .secureField
        case .noSelection:
            return .nothingToFix
        case .unsupported:
            return .unsupported
        case let .accessibilityError(error):
            return .failed(.accessibilityError(error.rawValue))
        }
    }

    private func outcome(from failure: SelectionWriteFailure) -> FixOutcome {
        switch failure {
        case .missingPermission:
            return .failed(.missingPermission)
        case .noFocusedElement:
            return .failed(.noFocusedElement)
        case .secureField:
            return .secureField
        case .noSelection:
            return .nothingToFix
        case .unsupported:
            return .unsupported
        case let .accessibilityError(error):
            return .failed(.accessibilityError(error.rawValue))
        case .pasteUnverified:
            return .pasteUnverified
        case .clipboardRestoreFailed:
            return .failed(.clipboardRestoreFailed)
        case .clipboardSuperseded:
            return .failed(.clipboardSuperseded)
        }
    }

    /// Converts a UTF-16 offset (as reported by the Accessibility API) into a character
    /// offset, or `nil` when the offset does not land on a character boundary.
    private func characterOffset(forUTF16Offset offset: Int, in text: String) -> Int? {
        guard offset >= 0, offset <= text.utf16.count else { return nil }
        let utf16Index = String.Index(utf16Offset: offset, in: text)
        guard let characterIndex = utf16Index.samePosition(in: text) else { return nil }
        return text.distance(from: text.startIndex, to: characterIndex)
    }

    /// Converts a character range into a UTF-16 `SelectionRangeSnapshot` without
    /// materializing the text as an array.
    private func utf16Range(forCharacterRange range: Range<Int>, in text: String) -> SelectionRangeSnapshot? {
        guard range.lowerBound >= 0, range.upperBound <= text.count else { return nil }
        let start = text.index(text.startIndex, offsetBy: range.lowerBound)
        let end = text.index(start, offsetBy: range.count)
        let location = start.utf16Offset(in: text)
        let length = end.utf16Offset(in: text) - location
        guard location >= 0, length >= 0 else { return nil }
        return SelectionRangeSnapshot(location: location, length: length)
    }
}
