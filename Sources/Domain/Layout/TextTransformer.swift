import Foundation

public protocol TextTransforming {
    func transform(_ text: String) -> TransformationResult
}

public enum TransformationResult: Equatable {
    case transformed(String)
    case noOp(NoOpReason)
}

public enum NoOpReason: String, Equatable {
    case emptyText
    case neutralText
    case ambiguousDirection
    case unchanged
}

public struct SimpleTextTransformer: TextTransforming {
    private let detector: LayoutDetecting
    private let mapper: LayoutMapping
    private let casePreserver: CasePreserving

    public init(
        detector: LayoutDetecting,
        mapper: LayoutMapping,
        casePreserver: CasePreserving = DefaultCasePreserver()
    ) {
        self.detector = detector
        self.mapper = mapper
        self.casePreserver = casePreserver
    }

    public func transform(_ text: String) -> TransformationResult {
        guard !text.isEmpty else {
            return .noOp(.emptyText)
        }

        let detection = detector.detect(text)

        guard let sourceLayout = detection.layout else {
            if detection.confidence == .ambiguous {
                return .noOp(.ambiguousDirection)
            }
            return .noOp(.neutralText)
        }

        let targetLayout: Layout = sourceLayout == .english ? .russian : .english
        let mappedText = mapper.map(text: text, from: sourceLayout, to: targetLayout)

        if mappedText == text {
            return .noOp(.unchanged)
        }

        let originalCharacters = Array(text)
        let mappedCharacters = Array(mappedText)

        guard mappedCharacters.count == originalCharacters.count else {
            return .transformed(mappedText)
        }

        var resolved = ""
        resolved.reserveCapacity(mappedCharacters.count)

        for index in 0..<mappedCharacters.count {
            let original = originalCharacters[index]
            let mapped = mappedCharacters[index]

            if original.isLetter && mapped.isLetter {
                resolved.append(casePreserver.preserveCase(original: original, transformed: mapped))
            } else {
                resolved.append(mapped)
            }
        }

        if resolved == text {
            return .noOp(.unchanged)
        }

        return .transformed(resolved)
    }
}
