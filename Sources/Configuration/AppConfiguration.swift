struct AppConfiguration: Codable, Equatable {
    static let `default` = AppConfiguration(
        schemaVersion: 1,
        isEnabled: true,
        launchAtLogin: true,
        shortcut: .defaultFixText,
        excludedApplicationBundleIdentifiers: [],
        hasCompletedOnboarding: false
    )

    var schemaVersion: Int
    var isEnabled: Bool
    var launchAtLogin: Bool
    var shortcut: Shortcut
    var excludedApplicationBundleIdentifiers: [String]
    var hasCompletedOnboarding: Bool

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isEnabled
        case launchAtLogin
        case shortcut
        case excludedApplicationBundleIdentifiers
        case hasCompletedOnboarding
    }

    init(
        schemaVersion: Int = 1,
        isEnabled: Bool = true,
        launchAtLogin: Bool = true,
        shortcut: Shortcut = .defaultFixText,
        excludedApplicationBundleIdentifiers: [String] = [],
        hasCompletedOnboarding: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.launchAtLogin = launchAtLogin
        self.shortcut = shortcut
        self.excludedApplicationBundleIdentifiers = Array(Set(excludedApplicationBundleIdentifiers)).sorted()
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1,
            isEnabled: try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            launchAtLogin: try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true,
            shortcut: try values.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? .defaultFixText,
            excludedApplicationBundleIdentifiers: try values.decodeIfPresent([String].self, forKey: .excludedApplicationBundleIdentifiers) ?? [],
            hasCompletedOnboarding: try values.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        )
    }
}
