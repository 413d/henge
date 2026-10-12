import Foundation

public protocol LayoutDetecting {
    func detect(_ text: String) -> LayoutDetection
}

public struct LayoutDetection: Equatable {
    public let layout: Layout?
    public let confidence: DetectionConfidence

    public init(layout: Layout?, confidence: DetectionConfidence) {
        self.layout = layout
        self.confidence = confidence
    }
}

public enum DetectionConfidence: String, Equatable {
    case clear
    case neutral
    case ambiguous
}

public final class MajorityLayoutDetector: LayoutDetecting {
    public init() {}

    public func detect(_ text: String) -> LayoutDetection {
        var englishCount = 0
        var russianCount = 0

        for character in text {
            switch character {
            case let ch where isEnglishLetter(ch):
                englishCount += 1
            case let ch where isRussianLetter(ch):
                russianCount += 1
            default:
                continue
            }
        }

        if englishCount == 0 && russianCount == 0 {
            return LayoutDetection(layout: nil, confidence: .neutral)
        }

        if englishCount > russianCount {
            return LayoutDetection(layout: .english, confidence: .clear)
        }

        if russianCount > englishCount {
            return LayoutDetection(layout: .russian, confidence: .clear)
        }

        return LayoutDetection(layout: nil, confidence: .ambiguous)
    }

    private func isEnglishLetter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else {
            return false
        }

        let value = scalar.value
        let isBasicLatin = (0x0041...0x005A).contains(value) || (0x0061...0x007A).contains(value)
        return isBasicLatin
    }

    private func isRussianLetter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else {
            return false
        }

        let value = scalar.value
        let isCyrillic = (0x0400...0x04FF).contains(value) || (0x0500...0x052F).contains(value)
        return isCyrillic
    }
}
