import Foundation

struct Shortcut: Codable, Equatable {
    struct Modifiers: Codable, OptionSet, Equatable {
        let rawValue: Int

        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)
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
