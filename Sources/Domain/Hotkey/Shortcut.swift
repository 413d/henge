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
    let keyCode: UInt32?

    static let defaultFixText = Shortcut(key: "X", modifiers: [.option], keyCode: 7)

    init(key: String, modifiers: Modifiers, keyCode: UInt32? = nil) {
        self.key = key
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case modifiers
        case keyCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        modifiers = try container.decode(Modifiers.self, forKey: .modifiers)
        keyCode = try container.decodeIfPresent(UInt32.self, forKey: .keyCode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
    }

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

        return prefix + formattedKey
    }

    private var formattedKey: String {
        if key.count == 1 {
            return key.uppercased()
        }

        switch key.lowercased() {
        case "space":
            return "Space"
        case "return", "enter":
            return "↩"
        case "left", "leftarrow":
            return "←"
        case "right", "rightarrow":
            return "→"
        case "up", "uparrow":
            return "↑"
        case "down", "downarrow":
            return "↓"
        case "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12":
            return key.uppercased()
        default:
            return key
        }
    }
}
