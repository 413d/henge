import Foundation

struct ApplicationIdentity: Equatable, Hashable {
    let bundleIdentifier: String
    let displayName: String

    init?(bundleIdentifier: String?, displayName: String?) {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return nil
        }

        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? bundleIdentifier
    }
}

struct ExceptionMatcher {
    func contains(_ application: ApplicationIdentity, in excludedBundleIdentifiers: Set<String>) -> Bool {
        excludedBundleIdentifiers.contains(application.bundleIdentifier)
    }
}

struct ExceptionManager {
    func add(_ application: ApplicationIdentity, to bundleIdentifiers: [String]) -> [String] {
        guard !bundleIdentifiers.contains(application.bundleIdentifier) else {
            return bundleIdentifiers
        }
        return bundleIdentifiers + [application.bundleIdentifier]
    }

    func remove(bundleIdentifier: String, from bundleIdentifiers: [String]) -> [String] {
        bundleIdentifiers.filter { $0 != bundleIdentifier }
    }
}
