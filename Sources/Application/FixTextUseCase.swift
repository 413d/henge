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

        let context: SelectionSnapshot
        switch runtime.inspectTextContext() {
        case let .available(resolvedContext):
            context = resolvedContext
        case let .unavailable(reason):
            return outcome(from: reason)
        }

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
            in: targetRange,
            context: context,
            expectedText: targetText,
            with: replacement,
            in: application
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
            in: targetRange,
            context: context,
            expectedText: targetText,
            with: replacement,
            in: application
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

    private func characterOffset(forUTF16Offset offset: Int, in text: String) -> Int? {
        guard offset >= 0 else { return nil }
        var utf16Offset = 0
        for (characterOffset, character) in text.enumerated() {
            if utf16Offset == offset { return characterOffset }
            utf16Offset += String(character).utf16.count
            if utf16Offset > offset { return nil }
        }
        return utf16Offset == offset ? text.count : nil
    }

    private func utf16Range(forCharacterRange range: Range<Int>, in text: String) -> SelectionRangeSnapshot? {
        let characters = Array(text)
        guard range.lowerBound >= 0, range.upperBound <= characters.count else { return nil }
        let location = characters[..<range.lowerBound].reduce(0) { $0 + String($1).utf16.count }
        let length = characters[range].reduce(0) { $0 + String($1).utf16.count }
        return SelectionRangeSnapshot(location: location, length: length)
    }
}
