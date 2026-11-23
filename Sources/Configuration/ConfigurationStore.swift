import Foundation
import OSLog

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
    private let logger = Diagnostics.logger(.config)

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
            logger.info("\(DiagnosticsLabel.configLoadedDefaults.rawValue, privacy: .public) reason=missing")
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
            let nsError = error as NSError
            logger.warning("\(DiagnosticsLabel.configLoadedDefaults.rawValue, privacy: .public) reason=corrupt errorDomain=\(nsError.domain, privacy: .public) errorCode=\(nsError.code, privacy: .public)")
            backupCorruptConfiguration()

            let configuration = AppConfiguration.default
            save(configuration)
            return configuration
        }
    }

    func save(_ configuration: AppConfiguration) {
        ensureDirectoryExists()

        do {
            let normalizedConfiguration = try migrator.migrate(configuration)
            let data = try encoder.encode(normalizedConfiguration)
            try data.write(to: configurationURL, options: .atomic)
        } catch {
            let nsError = error as NSError
            logger.error("\(DiagnosticsLabel.configSaveFailed.rawValue, privacy: .public) stage=save errorDomain=\(nsError.domain, privacy: .public) errorCode=\(nsError.code, privacy: .public)")
        }
    }

    private func ensureDirectoryExists() {
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            let nsError = error as NSError
            logger.error("\(DiagnosticsLabel.configSaveFailed.rawValue, privacy: .public) stage=createDirectory errorDomain=\(nsError.domain, privacy: .public) errorCode=\(nsError.code, privacy: .public)")
        }
    }

    private func backupCorruptConfiguration() {
        guard fileManager.fileExists(atPath: configurationURL.path) else {
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = directoryURL.appendingPathComponent("config.corrupt-\(timestamp).json")

        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.moveItem(at: configurationURL, to: backupURL)
            logger.notice("\(DiagnosticsLabel.configBackupWritten.rawValue, privacy: .public)")
        } catch {
            let nsError = error as NSError
            logger.error("\(DiagnosticsLabel.configSaveFailed.rawValue, privacy: .public) stage=backup errorDomain=\(nsError.domain, privacy: .public) errorCode=\(nsError.code, privacy: .public)")
        }
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
