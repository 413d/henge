import Foundation

struct Shortcut: Codable, Equatable {
    struct Modifiers: OptionSet, Equatable, Codable {
        let rawValue: Int

        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        private enum CodingKeys: String, CodingKey {
            case rawValue
        }

        init(from decoder: Decoder) throws {
            let keyedContainer = try? decoder.container(keyedBy: CodingKeys.self)
            if let value = try keyedContainer?.decodeIfPresent(Int.self, forKey: .rawValue) {
                self.rawValue = value
                return
            }

            let singleValueContainer = try decoder.singleValueContainer()
            self.rawValue = try singleValueContainer.decode(Int.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rawValue, forKey: .rawValue)
        }
    }

    let key: String
    let modifiers: Modifiers

    static let defaultFixText = Shortcut(key: "X", modifiers: [.option])

    var displayString: String {
        let orderedModifiers: [(Modifiers, String)] = [
            (.control, "⌃"),
            (.option, "⌥"),
            (.shift, "⇧"),
            (.command, "⌘"),
        ]

        let prefix = orderedModifiers
            .filter { modifiers.contains($0.0) }
            .map(\.1)
            .joined()

        return prefix + key.uppercased()
    }
}
