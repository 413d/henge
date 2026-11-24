import Foundation
import Testing
@testable import Henge

struct ActivationWaiterTests {
    @Test
    func waitReturnsImmediatelyWhenTargetIsAlreadyFrontmostAtSubscription() async {
        let notes = WorkspaceApplicationSnapshot(
            processIdentifier: 4100,
            bundleIdentifier: "com.apple.Notes",
            localizedName: "Notes",
            isTerminated: false
        )
        let source = ActivationTestWorkspaceSource(frontmost: notes)

        let start = Date()
        await ActivationWaiter.wait(
            bundleIdentifier: "com.apple.Notes",
            source: source,
            timeout: 3.0
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < 0.1)
        #expect(source.activeObserverCount == 0)
    }

    @Test
    @MainActor
    func prepareTargetApplicationForFixTextSettlesFocusPromptlyWithoutWaitingOutActivationTimeout() async {
        let notes = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let provider = ActivationTestApplicationProvider()
        var focusChecks = 0
        let activator = ApplicationActivator(
            applicationProvider: provider,
            hasFocusedElement: {
                focusChecks += 1
                return focusChecks >= 2
            }
        )

        let start = Date()
        let prepared = await activator.prepareTargetApplicationForFixText(notes)
        let elapsed = Date().timeIntervalSince(start)

        #expect(prepared == true)
        #expect(provider.activateCallCount == 1)
        #expect(provider.waitForActivationCallCount == 0)
        #expect(focusChecks == 2)
        #expect(elapsed < 1.0)
    }
}

private final class ActivationTestWorkspaceSource: WorkspaceApplicationSource, @unchecked Sendable {
    private let lock = NSLock()
    private var frontmost: WorkspaceApplicationSnapshot?
    private var observers: [UUID: @Sendable (WorkspaceApplicationSnapshot) -> Void] = [:]

    var activeObserverCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return observers.count
    }

    init(frontmost: WorkspaceApplicationSnapshot?) {
        self.frontmost = frontmost
    }

    func frontmostApplication() -> WorkspaceApplicationSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return frontmost
    }

    func runningApplication(processIdentifier: pid_t) -> WorkspaceApplicationSnapshot? {
        nil
    }

    func runningApplications(bundleIdentifier: String) -> [WorkspaceApplicationSnapshot] {
        []
    }

    func installedApplicationDisplayName(bundleIdentifier: String) -> String? {
        nil
    }

    func activateApplication(processIdentifier: pid_t) -> Bool {
        false
    }

    func observeActivations(_ handler: @escaping @Sendable (WorkspaceApplicationSnapshot) -> Void) -> AnyObject {
        let id = UUID()
        lock.lock()
        observers[id] = handler
        lock.unlock()
        return id as NSUUID
    }

    func stopObserving(_ token: AnyObject) {
        guard let id = token as? NSUUID else { return }
        lock.lock()
        observers.removeValue(forKey: id as UUID)
        lock.unlock()
    }
}

private final class ActivationTestApplicationProvider: ActiveApplicationProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var frontmostBundleID: String?
    private(set) var activateCallCount = 0
    private(set) var waitForActivationCallCount = 0

    func activeApplication() -> ApplicationIdentity? {
        nil
    }

    func application(bundleIdentifier: String) -> ApplicationIdentity? {
        nil
    }

    func isFrontmost(_ application: ApplicationIdentity) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return frontmostBundleID == application.bundleIdentifier
    }

    func activateApplication(_ application: ApplicationIdentity) -> Bool {
        lock.lock()
        activateCallCount += 1
        frontmostBundleID = application.bundleIdentifier
        lock.unlock()
        return true
    }

    func waitForActivation(of application: ApplicationIdentity, timeout: TimeInterval) async {
        lock.withLock {
            waitForActivationCallCount += 1
        }
        let nanoseconds = ActivationWaiter.sleepNanoseconds(for: timeout)
        guard nanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}
