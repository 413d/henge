import AppKit
import Foundation

struct WorkspaceApplicationSnapshot: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
    let isTerminated: Bool

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        localizedName: String?,
        isTerminated: Bool
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.isTerminated = isTerminated
    }

    init(runningApplication: NSRunningApplication) {
        self.init(
            processIdentifier: runningApplication.processIdentifier,
            bundleIdentifier: runningApplication.bundleIdentifier,
            localizedName: runningApplication.localizedName,
            isTerminated: runningApplication.isTerminated
        )
    }
}

protocol WorkspaceApplicationSource: Sendable {
    func frontmostApplication() -> WorkspaceApplicationSnapshot?
    func runningApplication(processIdentifier: pid_t) -> WorkspaceApplicationSnapshot?
    func runningApplications(bundleIdentifier: String) -> [WorkspaceApplicationSnapshot]
    func installedApplicationDisplayName(bundleIdentifier: String) -> String?
    @discardableResult
    func activateApplication(processIdentifier: pid_t) -> Bool
    func observeActivations(_ handler: @escaping @Sendable (WorkspaceApplicationSnapshot) -> Void) -> AnyObject
    func stopObserving(_ token: AnyObject)
}

struct SystemWorkspaceApplicationSource: WorkspaceApplicationSource, Sendable {
    func frontmostApplication() -> WorkspaceApplicationSnapshot? {
        NSWorkspace.shared.frontmostApplication.map(WorkspaceApplicationSnapshot.init(runningApplication:))
    }

    func runningApplication(processIdentifier: pid_t) -> WorkspaceApplicationSnapshot? {
        NSRunningApplication(processIdentifier: processIdentifier).map(WorkspaceApplicationSnapshot.init(runningApplication:))
    }

    func runningApplications(bundleIdentifier: String) -> [WorkspaceApplicationSnapshot] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
            .map(WorkspaceApplicationSnapshot.init(runningApplication:))
    }

    func installedApplicationDisplayName(bundleIdentifier: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let bundle = Bundle(url: url) else {
            return nil
        }

        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
    }

    @discardableResult
    func activateApplication(processIdentifier: pid_t) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: processIdentifier),
              !application.isTerminated else {
            return false
        }

        return application.activate(options: [.activateIgnoringOtherApps])
    }

    func observeActivations(_ handler: @escaping @Sendable (WorkspaceApplicationSnapshot) -> Void) -> AnyObject {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            handler(WorkspaceApplicationSnapshot(runningApplication: application))
        }
    }

    func stopObserving(_ token: AnyObject) {
        NSWorkspace.shared.notificationCenter.removeObserver(token)
    }
}

protocol ActiveApplicationProviding: Sendable {
    func activeApplication() -> ApplicationIdentity?
    func application(bundleIdentifier: String) -> ApplicationIdentity?
    func activeProcessIdentifier(for application: ApplicationIdentity) -> pid_t?
    func isFrontmost(_ application: ApplicationIdentity) -> Bool
    @discardableResult
    func activateApplication(_ application: ApplicationIdentity) -> Bool
    func setActivationHandler(_ handler: (@Sendable () -> Void)?)
    func waitForActivation(of application: ApplicationIdentity, timeout: TimeInterval) async
}

extension ActiveApplicationProviding {
    func activeProcessIdentifier(for application: ApplicationIdentity) -> pid_t? {
        nil
    }

    func isFrontmost(_ application: ApplicationIdentity) -> Bool {
        activeApplication()?.bundleIdentifier == application.bundleIdentifier
    }

    @discardableResult
    func activateApplication(_ application: ApplicationIdentity) -> Bool {
        true
    }

    func setActivationHandler(_ handler: (@Sendable () -> Void)?) {}

    func waitForActivation(of application: ApplicationIdentity, timeout: TimeInterval) async {
        guard timeout > 0 else { return }
        let nanoseconds = UInt64(min(timeout * 1_000_000_000, Double(UInt64.max - 1)).rounded())
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

final class WorkspaceActiveApplicationProvider: ActiveApplicationProviding, @unchecked Sendable {
    private struct TrackedApplication {
        let identity: ApplicationIdentity
        let processIdentifier: pid_t
    }

    private let workspace: WorkspaceApplicationSource
    private let selfBundleIdentifier: String?
    private let lock = NSLock()
    private var lastExternalApplication: TrackedApplication?
    private var activationHandler: (@Sendable () -> Void)?
    private var observerToken: AnyObject?

    init(
        workspace: WorkspaceApplicationSource = SystemWorkspaceApplicationSource(),
        selfBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.workspace = workspace
        self.selfBundleIdentifier = selfBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let frontmost = workspace.frontmostApplication() {
            recordActivation(frontmost)
        }

        observerToken = workspace.observeActivations { [weak self] snapshot in
            self?.recordActivation(snapshot)
        }
    }

    deinit {
        if let observerToken {
            workspace.stopObserving(observerToken)
        }
    }

    func activeApplication() -> ApplicationIdentity? {
        if let frontmost = workspace.frontmostApplication(),
           !frontmost.isTerminated,
           let identity = externalIdentity(from: frontmost) {
            storeTracked(TrackedApplication(identity: identity, processIdentifier: frontmost.processIdentifier))
            return identity
        }

        guard let tracked = loadValidTrackedApplication() else {
            return nil
        }

        return tracked.identity
    }

    func application(bundleIdentifier: String) -> ApplicationIdentity? {
        if let runningApplication = workspace.runningApplications(bundleIdentifier: bundleIdentifier).first,
           let identity = ApplicationIdentity(bundleIdentifier: runningApplication.bundleIdentifier, displayName: runningApplication.localizedName) {
            return identity
        }

        guard let displayName = workspace.installedApplicationDisplayName(bundleIdentifier: bundleIdentifier) else {
            return nil
        }

        return ApplicationIdentity(bundleIdentifier: bundleIdentifier, displayName: displayName)
    }

    func activeProcessIdentifier(for application: ApplicationIdentity) -> pid_t? {
        if let frontmost = workspace.frontmostApplication(),
           !frontmost.isTerminated,
           frontmost.bundleIdentifier == application.bundleIdentifier {
            return frontmost.processIdentifier
        }

        if let tracked = loadValidTrackedApplication(),
           tracked.identity.bundleIdentifier == application.bundleIdentifier {
            return tracked.processIdentifier
        }

        return workspace.runningApplications(bundleIdentifier: application.bundleIdentifier)
            .first?
            .processIdentifier
    }

    func isFrontmost(_ application: ApplicationIdentity) -> Bool {
        guard let frontmost = workspace.frontmostApplication(),
              !frontmost.isTerminated else {
            return false
        }

        return frontmost.bundleIdentifier == application.bundleIdentifier
    }

    @discardableResult
    func activateApplication(_ application: ApplicationIdentity) -> Bool {
        guard let pid = activeProcessIdentifier(for: application) else {
            return false
        }

        return workspace.activateApplication(processIdentifier: pid)
    }

    func setActivationHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        activationHandler = handler
        lock.unlock()
    }

    func waitForActivation(of application: ApplicationIdentity, timeout: TimeInterval) async {
        await ActivationWaiter.wait(
            bundleIdentifier: application.bundleIdentifier,
            source: workspace,
            timeout: timeout
        )
    }

    private func recordActivation(_ snapshot: WorkspaceApplicationSnapshot) {
        guard !snapshot.isTerminated,
              let identity = externalIdentity(from: snapshot) else {
            return
        }

        storeTracked(TrackedApplication(identity: identity, processIdentifier: snapshot.processIdentifier))
        lock.lock()
        let handler = activationHandler
        lock.unlock()
        handler?()
    }

    private func externalIdentity(from snapshot: WorkspaceApplicationSnapshot) -> ApplicationIdentity? {
        guard let identity = ApplicationIdentity(bundleIdentifier: snapshot.bundleIdentifier, displayName: snapshot.localizedName) else {
            return nil
        }

        if let selfBundleIdentifier, !selfBundleIdentifier.isEmpty, identity.bundleIdentifier == selfBundleIdentifier {
            return nil
        }

        return identity
    }

    private func storeTracked(_ tracked: TrackedApplication?) {
        lock.lock()
        lastExternalApplication = tracked
        lock.unlock()
    }

    private func loadValidTrackedApplication() -> TrackedApplication? {
        lock.lock()
        let tracked = lastExternalApplication
        lock.unlock()

        guard let tracked else {
            return nil
        }

        guard let running = workspace.runningApplication(processIdentifier: tracked.processIdentifier),
              !running.isTerminated,
              running.bundleIdentifier == tracked.identity.bundleIdentifier else {
            storeTracked(nil)
            return nil
        }

        if let refreshed = ApplicationIdentity(bundleIdentifier: running.bundleIdentifier, displayName: running.localizedName) {
            let updated = TrackedApplication(identity: refreshed, processIdentifier: tracked.processIdentifier)
            storeTracked(updated)
            return updated
        }

        return tracked
    }
}
