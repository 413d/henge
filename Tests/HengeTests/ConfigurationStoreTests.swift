import Foundation
import Testing
@testable import Henge

struct ConfigurationStoreTests {
    @Test
    func jsonStorePersistsConfigurationAcrossInstances() throws {
        let directoryURL = try temporaryDirectoryURL()
        let store = JSONConfigurationStore(directoryURL: directoryURL)
        let configuration = AppConfiguration(schemaVersion: 1, isEnabled: false, shortcut: .defaultFixText)

        store.save(configuration)

        let reloadedStore = JSONConfigurationStore(directoryURL: directoryURL)
        #expect(reloadedStore.load() == configuration)
    }

    @Test
    func jsonStoreBacksUpCorruptConfigAndFallsBackToDefaults() throws {
        let directoryURL = try temporaryDirectoryURL()
        let configURL = directoryURL.appendingPathComponent("config.json")

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try "not valid json".write(to: configURL, atomically: true, encoding: .utf8)

        let store = JSONConfigurationStore(directoryURL: directoryURL)
        let loadedConfiguration = store.load()
        let directoryContents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)

        #expect(loadedConfiguration == AppConfiguration.default)
        #expect(directoryContents.contains(where: { $0.lastPathComponent.starts(with: "config.corrupt-") }))
        #expect(directoryContents.contains(where: { $0.lastPathComponent == "config.json" }))
    }

    @Test
    func missingConfigFileCreatesDefaultConfiguration() throws {
        let directoryURL = try temporaryDirectoryURL()
        let store = JSONConfigurationStore(directoryURL: directoryURL)

        let loadedConfiguration = store.load()
        let configURL = directoryURL.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configURL)

        #expect(loadedConfiguration == AppConfiguration.default)
        #expect(!configData.isEmpty)
    }

    @Test
    func emptyConfigFileFallsBackToDefaults() throws {
        let directoryURL = try temporaryDirectoryURL()
        let configURL = directoryURL.appendingPathComponent("config.json")

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try "".write(to: configURL, atomically: true, encoding: .utf8)

        let store = JSONConfigurationStore(directoryURL: directoryURL)
        let loadedConfiguration = store.load()
        let directoryContents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)

        #expect(loadedConfiguration == AppConfiguration.default)
        #expect(directoryContents.contains(where: { $0.lastPathComponent.starts(with: "config.corrupt-") }))
    }

    @Test
    func unknownFieldsAreIgnoredAndDuplicateExceptionsAreNormalized() throws {
        let directoryURL = try temporaryDirectoryURL()
        let configURL = directoryURL.appendingPathComponent("config.json")
        let payload = """
        {
          "schemaVersion": 1,
          "isEnabled": false,
          "launchAtLogin": false,
          "shortcut": { "key": "X", "modifiers": { "rawValue": 2 } },
          "excludedApplicationBundleIdentifiers": ["com.example.Beta", "com.example.Alpha", "com.example.Alpha"],
          "unused": "ignored"
        }
        """

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try payload.write(to: configURL, atomically: true, encoding: .utf8)

        let loadedConfiguration = JSONConfigurationStore(directoryURL: directoryURL).load()

        #expect(loadedConfiguration.isEnabled == false)
        #expect(loadedConfiguration.launchAtLogin == false)
        #expect(loadedConfiguration.excludedApplicationBundleIdentifiers == ["com.example.Alpha", "com.example.Beta"])
    }

    @Test
    func defaultConfigurationIncludesLaunchAtLoginAndCanonicalValues() {
        let configuration = AppConfiguration.default

        #expect(configuration.isEnabled == true)
        #expect(configuration.launchAtLogin == true)
        #expect(configuration.shortcut == .defaultFixText)
        #expect(configuration.excludedApplicationBundleIdentifiers == [])
    }

    @Test
    func legacyConfigWithoutLaunchAtLoginDefaultsToEnabledStartup() throws {
        let directoryURL = try temporaryDirectoryURL()
        let configURL = directoryURL.appendingPathComponent("config.json")
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "isEnabled": false,
          "shortcut": { "key": "X", "modifiers": { "rawValue": 2 } },
          "excludedApplicationBundleIdentifiers": []
        }
        """

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try legacyJSON.write(to: configURL, atomically: true, encoding: .utf8)

        let loadedConfiguration = JSONConfigurationStore(directoryURL: directoryURL).load()

        #expect(loadedConfiguration.isEnabled == false)
        #expect(loadedConfiguration.launchAtLogin == true)
        #expect(loadedConfiguration.shortcut == .defaultFixText)
    }

    @Test
    func futureSchemaVersionFallsBackToDefaults() throws {
        let directoryURL = try temporaryDirectoryURL()
        let configURL = directoryURL.appendingPathComponent("config.json")
        let futureVersionJSON = """
        {
          "schemaVersion": 99,
          "isEnabled": true,
          "launchAtLogin": true,
          "shortcut": { "key": "X", "modifiers": { "rawValue": 2 } },
          "excludedApplicationBundleIdentifiers": ["com.example.Editor"]
        }
        """

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try futureVersionJSON.write(to: configURL, atomically: true, encoding: .utf8)

        let store = JSONConfigurationStore(directoryURL: directoryURL)
        let loadedConfiguration = store.load()
        let directoryContents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)

        #expect(loadedConfiguration == AppConfiguration.default)
        #expect(directoryContents.contains(where: { $0.lastPathComponent.starts(with: "config.corrupt-") }))
    }

    private func temporaryDirectoryURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return directoryURL
    }
}
