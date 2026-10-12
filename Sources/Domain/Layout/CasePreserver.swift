import Foundation

public protocol CasePreserving: Sendable {
    func preserveCase(original: Character, transformed: Character) -> Character
}

public struct DefaultCasePreserver: CasePreserving {
    public init() {}

    public func preserveCase(original: Character, transformed: Character) -> Character {
        let originalText = String(original)
        let transformedText = String(transformed)

        if originalText.isEmpty || transformedText.isEmpty {
            return transformed
        }

        let originalLower = originalText.lowercased()
        let originalUpper = originalText.uppercased()

        if originalText == originalLower {
            return transformedText.lowercased().first ?? transformed
        }

        if originalText == originalUpper {
            return transformedText.uppercased().first ?? transformed
        }

        return transformed
    }
}
