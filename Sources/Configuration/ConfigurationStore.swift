import Foundation

protocol ConfigurationStore {
    func load() -> AppConfiguration
    func save(_ configuration: AppConfiguration)
}

final class InMemoryConfigurationStore: ConfigurationStore {
    private var configuration = AppConfiguration.default

    func load() -> AppConfiguration {
        configuration
    }

    func save(_ configuration: AppConfiguration) {
        self.configuration = configuration
    }
}

final class JSONConfigurationStore: ConfigurationStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let configurationURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let migrator: ConfigurationMigrator

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        migrator: ConfigurationMigrator = ConfigurationMigrator()
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? JSONConfigurationStore.defaultDirectoryURL(fileManager: fileManager)
        configurationURL = self.directoryURL.appendingPathComponent("config.json")
        self.encoder = encoder
        self.decoder = decoder
        self.migrator = migrator
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AppConfiguration {
        ensureDirectoryExists()

        guard fileManager.fileExists(atPath: configurationURL.path) else {
            let configuration = AppConfiguration.default
            save(configuration)
            return configuration
        }

        do {
            let data = try Data(contentsOf: configurationURL)
            if data.isEmpty {
                throw ConfigurationMigrationError.emptyFile
            }

            let decodedConfiguration = try decoder.decode(AppConfiguration.self, from: data)
            let migratedConfiguration = try migrator.migrate(decodedConfiguration)
            return migratedConfiguration
        } catch {
            backupCorruptConfiguration()

            let configuration = AppConfiguration.default
            save(configuration)
            return configuration
        }
    }

    func save(_ configuration: AppConfiguration) {
        ensureDirectoryExists()

        guard let normalizedConfiguration = try? migrator.migrate(configuration),
              let data = try? encoder.encode(normalizedConfiguration) else {
            return
        }

        try? data.write(to: configurationURL, options: .atomic)
    }

    private func ensureDirectoryExists() {
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func backupCorruptConfiguration() {
        guard fileManager.fileExists(atPath: configurationURL.path) else {
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = directoryURL.appendingPathComponent("config.corrupt-\(timestamp).json")

        try? fileManager.removeItem(at: backupURL)
        try? fileManager.moveItem(at: configurationURL, to: backupURL)
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let applicationSupportURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let baseURL = applicationSupportURL ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return baseURL.appendingPathComponent("Henge", isDirectory: true)
    }
}
