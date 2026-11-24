import Foundation

enum ConfigurationMigrationError: Error {
    case unsupportedFutureVersion(Int)
    case emptyFile
}

struct ConfigurationMigrator {
    let currentSchemaVersion = 1

    func migrate(_ configuration: AppConfiguration) throws -> AppConfiguration {
        guard configuration.schemaVersion <= currentSchemaVersion else {
            throw ConfigurationMigrationError.unsupportedFutureVersion(configuration.schemaVersion)
        }

        var normalized = configuration
        normalized.schemaVersion = currentSchemaVersion
        if normalized.shortcut.keyCode == nil,
           normalized.shortcut.key.caseInsensitiveCompare(Shortcut.defaultFixText.key) == .orderedSame,
           normalized.shortcut.modifiers == Shortcut.defaultFixText.modifiers {
            normalized.shortcut = .defaultFixText
        }
        return normalized
    }
}
