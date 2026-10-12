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

    public init(detector: LayoutDetecting, mapper: LayoutMapping) {
        self.detector = detector
        self.mapper = mapper
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

        return .transformed(mappedText)
    }
}
