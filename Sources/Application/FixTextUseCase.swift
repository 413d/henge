import Foundation

final class FixTextStatusChannel: @unchecked Sendable {
    private let lock = NSLock()
    private var latestMessage: String?

    init() {}

    func report(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        latestMessage = message
    }

    func take() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let message = latestMessage
        latestMessage = nil
        return message
    }
}

enum FixTextAvailability: Equatable {
    case available
    case deferred(String)
}

protocol FixTextUseCaseProtocol {
    var availability: FixTextAvailability { get }

    func execute(excludingApplicationBundleIdentifiers: Set<String>)
}

extension FixTextUseCaseProtocol {
    func execute() {
        execute(excludingApplicationBundleIdentifiers: [])
    }
}

struct DeferredFixTextUseCase: FixTextUseCaseProtocol {
    let availability: FixTextAvailability = .deferred(
        "Text correction remains unavailable while Milestone 1 native hotkey and text-integration spikes are being validated."
    )

    func execute(excludingApplicationBundleIdentifiers: Set<String>) {
    }
}

struct LiveFixTextUseCase: FixTextUseCaseProtocol {
    let availability: FixTextAvailability = .available

    private let runtime: AppRuntime
    private let transformer: TextTransforming
    private let wordBoundaryDetector: WordBoundaryDetecting
    private let exceptionMatcher: ExceptionMatcher
    private let statusChannel: FixTextStatusChannel

    init(
        runtime: AppRuntime,
        transformer: TextTransforming,
        wordBoundaryDetector: WordBoundaryDetecting = DefaultWordBoundaryDetector(),
        exceptionMatcher: ExceptionMatcher = ExceptionMatcher(),
        statusChannel: FixTextStatusChannel = FixTextStatusChannel()
    ) {
        self.runtime = runtime
        self.transformer = transformer
        self.wordBoundaryDetector = wordBoundaryDetector
        self.exceptionMatcher = exceptionMatcher
        self.statusChannel = statusChannel
    }

    func execute(excludingApplicationBundleIdentifiers: Set<String>) {
        guard let application = runtime.activeApplication,
              !exceptionMatcher.contains(application, in: excludingApplicationBundleIdentifiers) else {
            return
        }

        guard case let .available(context) = runtime.inspectTextContext() else { return }

        let targetRange: SelectionRangeSnapshot
        let targetText: String
        if context.isCaretContext {
            guard let caretOffset = characterOffset(forUTF16Offset: context.range.location, in: context.text),
                  let boundary = wordBoundaryDetector.detect(in: context.text, caretOffset: caretOffset),
                  let range = utf16Range(forCharacterRange: boundary.range, in: context.text) else {
                return
            }
            targetRange = range
            targetText = boundary.text
        } else {
            targetRange = context.range
            targetText = context.text
        }

        guard case let .transformed(replacement) = transformer.transform(targetText) else { return }

        let directResult = runtime.replaceText(
            in: targetRange,
            context: context,
            expectedText: targetText,
            with: replacement,
            in: application
        )
        switch directResult {
        case .success:
            statusChannel.report("Text corrected.")
            return
        case .unavailable(.unsupported):
            break
        case .unavailable:
            return
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
            statusChannel.report("Text corrected using the clipboard fallback.")
        case .unavailable(.clipboardRestoreFailed):
            statusChannel.report(SelectionWriteFailure.clipboardRestoreFailed.description)
        case .unavailable(.pasteUnverified):
            statusChannel.report(SelectionWriteFailure.pasteUnverified.description)
        case .unavailable(.clipboardSuperseded):
            break
        case .unavailable:
            break
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
