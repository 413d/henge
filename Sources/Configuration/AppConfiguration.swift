struct AppConfiguration: Codable, Equatable {
    var schemaVersion = 1
    var isEnabled = true
    var shortcut = Shortcut.defaultFixText
    var excludedApplicationBundleIdentifiers: [String] = []

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isEnabled
        case shortcut
        case excludedApplicationBundleIdentifiers
    }

    init(
        schemaVersion: Int = 1,
        isEnabled: Bool = true,
        shortcut: Shortcut = .defaultFixText,
        excludedApplicationBundleIdentifiers: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.shortcut = shortcut
        self.excludedApplicationBundleIdentifiers = Array(Set(excludedApplicationBundleIdentifiers)).sorted()
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        shortcut = try values.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? .defaultFixText
        excludedApplicationBundleIdentifiers = Array(
            Set(try values.decodeIfPresent([String].self, forKey: .excludedApplicationBundleIdentifiers) ?? [])
        ).sorted()
    }
}
