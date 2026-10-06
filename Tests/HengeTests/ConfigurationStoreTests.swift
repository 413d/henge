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

        #expect(loadedConfiguration == AppConfiguration())
        #expect(directoryContents.contains(where: { $0.lastPathComponent.starts(with: "config.corrupt-") }))
        #expect(directoryContents.contains(where: { $0.lastPathComponent == "config.json" }))
    }

    private func temporaryDirectoryURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return directoryURL
    }
}
