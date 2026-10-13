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
        normalized.excludedApplicationBundleIdentifiers = Array(Set(normalized.excludedApplicationBundleIdentifiers)).sorted()
        return normalized
    }
}
