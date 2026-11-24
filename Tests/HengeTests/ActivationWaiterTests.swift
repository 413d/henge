import Foundation
import Testing
@testable import Henge

@Suite("ActivationWaiterTests")
struct ActivationWaiterTests {
    @Test
    func sleepNanosecondsHandlesEdgeCasesAndClampsToSixtySeconds() {
        #expect(ActivationWaiter.sleepNanoseconds(for: .infinity) == 0)
        #expect(ActivationWaiter.sleepNanoseconds(for: -.infinity) == 0)
        #expect(ActivationWaiter.sleepNanoseconds(for: .nan) == 0)
        #expect(ActivationWaiter.sleepNanoseconds(for: -1) == 0)
        #expect(ActivationWaiter.sleepNanoseconds(for: 0) == 0)
        #expect(ActivationWaiter.sleepNanoseconds(for: 1e12) == 60_000_000_000)
        #expect(ActivationWaiter.sleepNanoseconds(for: 60) == 60_000_000_000)
        #expect(ActivationWaiter.sleepNanoseconds(for: 0.3) == 300_000_000)
    }

    @Test
    func waitWithNanTimeoutReturnsPromptlyWithoutTrapping() async {
        let source = StubWorkspaceApplicationSource()
        let start = Date()
        await ActivationWaiter.wait(
            bundleIdentifier: "com.apple.Notes",
            source: source,
            timeout: .nan
        )
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.5)
    }

    @Test
    func waitForActivationWithNanTimeoutReturnsPromptlyWithoutTrapping() async {
        let provider = StubActiveApplicationProvider()
        let target = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let start = Date()
        await provider.waitForActivation(of: target, timeout: .nan)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.5)
    }
}

private final class StubWorkspaceApplicationSource: WorkspaceApplicationSource, @unchecked Sendable {
    private final class Token {}

    func frontmostApplication() -> WorkspaceApplicationSnapshot? { nil }
    func runningApplication(processIdentifier: pid_t) -> WorkspaceApplicationSnapshot? { nil }
    func runningApplications(bundleIdentifier: String) -> [WorkspaceApplicationSnapshot] { [] }
    func installedApplicationDisplayName(bundleIdentifier: String) -> String? { nil }
    func activateApplication(processIdentifier: pid_t) -> Bool { false }
    func observeActivations(_ handler: @escaping @Sendable (WorkspaceApplicationSnapshot) -> Void) -> AnyObject {
        Token()
    }
    func stopObserving(_ token: AnyObject) {}
}

private struct StubActiveApplicationProvider: ActiveApplicationProviding {
    func activeApplication() -> ApplicationIdentity? { nil }
    func application(bundleIdentifier: String) -> ApplicationIdentity? { nil }
}
