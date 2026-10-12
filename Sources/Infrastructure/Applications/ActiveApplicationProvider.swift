import AppKit

protocol ActiveApplicationProviding {
    func activeApplication() -> ApplicationIdentity?
    func application(bundleIdentifier: String) -> ApplicationIdentity?
}

struct WorkspaceActiveApplicationProvider: ActiveApplicationProviding {
    func activeApplication() -> ApplicationIdentity? {
        let application = NSWorkspace.shared.frontmostApplication
        return ApplicationIdentity(bundleIdentifier: application?.bundleIdentifier, displayName: application?.localizedName)
    }

    func application(bundleIdentifier: String) -> ApplicationIdentity? {
        if let runningApplication = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
           let identity = ApplicationIdentity(bundleIdentifier: runningApplication.bundleIdentifier, displayName: runningApplication.localizedName) {
            return identity
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let bundle = Bundle(url: url) else {
            return nil
        }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        return ApplicationIdentity(bundleIdentifier: bundleIdentifier, displayName: name)
    }
}
