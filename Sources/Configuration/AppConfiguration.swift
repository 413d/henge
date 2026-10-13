struct AppConfiguration: Codable, Equatable {
    static let `default` = AppConfiguration(
        schemaVersion: 1,
        isEnabled: true,
        launchAtLogin: true,
        shortcut: .defaultFixText,
        excludedApplicationBundleIdentifiers: []
    )

    var schemaVersion: Int
    var isEnabled: Bool
    var launchAtLogin: Bool
    var shortcut: Shortcut
    var excludedApplicationBundleIdentifiers: [String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isEnabled
        case launchAtLogin
        case shortcut
        case excludedApplicationBundleIdentifiers
    }

    init(
        schemaVersion: Int = 1,
        isEnabled: Bool = true,
        launchAtLogin: Bool = true,
        shortcut: Shortcut = .defaultFixText,
        excludedApplicationBundleIdentifiers: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.launchAtLogin = launchAtLogin
        self.shortcut = shortcut
        self.excludedApplicationBundleIdentifiers = Array(Set(excludedApplicationBundleIdentifiers)).sorted()
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        shortcut = try values.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? .defaultFixText
        excludedApplicationBundleIdentifiers = Array(
            Set(try values.decodeIfPresent([String].self, forKey: .excludedApplicationBundleIdentifiers) ?? [])
        ).sorted()
    }
}
