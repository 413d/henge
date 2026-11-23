import AppKit
import Foundation
import Testing
@testable import Henge

struct SingleInstanceGuardTests {
    @Test
    func otherInstanceIgnoresCurrentProcess() {
        #expect(
            SingleInstanceGuard.otherInstance(
                processIdentifiers: [101, 202],
                currentProcessIdentifier: 101
            ) == 202
        )
        #expect(
            SingleInstanceGuard.otherInstance(
                processIdentifiers: [101],
                currentProcessIdentifier: 101
            ) == nil
        )
    }

    @Test
    func otherInstancePicksEarliestRunning() {
        #expect(
            SingleInstanceGuard.otherInstance(
                processIdentifiers: [300, 150, 200],
                currentProcessIdentifier: 400
            ) == 150
        )
    }

    @Test
    func otherInstanceReturnsNilWhenAlone() {
        #expect(
            SingleInstanceGuard.otherInstance(
                processIdentifiers: [],
                currentProcessIdentifier: 101
            ) == nil
        )
        #expect(
            SingleInstanceGuard.otherInstance(
                processIdentifiers: [101, 101],
                currentProcessIdentifier: 101
            ) == nil
        )
    }

    @Test
    func enforceReturnsFalseWhenBundleIdentifierIsNilOrEmpty() {
        let peer = FakeRunningApplication(
            processIdentifier: 100,
            bundleIdentifier: "io.github.413d.Henge"
        )

        #expect(
            SingleInstanceGuard.enforce(
                currentProcessIdentifier: 200,
                bundleIdentifier: nil,
                runningApplications: [peer]
            ) == false
        )
        #expect(
            SingleInstanceGuard.enforce(
                currentProcessIdentifier: 200,
                bundleIdentifier: "",
                runningApplications: [peer]
            ) == false
        )
        #expect(peer.activateCallCount == 0)
    }

    @Test
    func enforceReturnsFalseWhenNoMatchingActivePeersExist() {
        let current = FakeRunningApplication(
            processIdentifier: 200,
            bundleIdentifier: "io.github.413d.Henge"
        )
        let unrelated = FakeRunningApplication(
            processIdentifier: 100,
            bundleIdentifier: "com.apple.Notes"
        )
        let terminatedPeer = FakeRunningApplication(
            processIdentifier: 150,
            bundleIdentifier: "io.github.413d.Henge",
            isTerminated: true
        )

        #expect(
            SingleInstanceGuard.enforce(
                currentProcessIdentifier: 200,
                bundleIdentifier: "io.github.413d.Henge",
                runningApplications: [current, unrelated, terminatedPeer]
            ) == false
        )
        #expect(
            SingleInstanceGuard.enforce(
                currentProcessIdentifier: 200,
                bundleIdentifier: "io.github.413d.Henge",
                runningApplications: []
            ) == false
        )
        #expect(current.activateCallCount == 0)
        #expect(unrelated.activateCallCount == 0)
        #expect(terminatedPeer.activateCallCount == 0)
    }

    @Test
    func enforceActivatesEarliestPeerAndReturnsTrueWhenPeerExists() {
        let current = FakeRunningApplication(
            processIdentifier: 500,
            bundleIdentifier: "io.github.413d.Henge"
        )
        let laterPeer = FakeRunningApplication(
            processIdentifier: 300,
            bundleIdentifier: "io.github.413d.Henge"
        )
        let earliestPeer = FakeRunningApplication(
            processIdentifier: 150,
            bundleIdentifier: "io.github.413d.Henge"
        )
        let unrelated = FakeRunningApplication(
            processIdentifier: 50,
            bundleIdentifier: "com.apple.Notes"
        )

        let shouldExit = SingleInstanceGuard.enforce(
            currentProcessIdentifier: 500,
            bundleIdentifier: "io.github.413d.Henge",
            runningApplications: [current, laterPeer, earliestPeer, unrelated]
        )

        #expect(shouldExit == true)
        #expect(earliestPeer.activateCallCount == 1)
        #expect(earliestPeer.lastActivateOptions == [.activateIgnoringOtherApps])
        #expect(laterPeer.activateCallCount == 0)
        #expect(current.activateCallCount == 0)
        #expect(unrelated.activateCallCount == 0)
    }
}

private final class FakeRunningApplication: NSRunningApplication, @unchecked Sendable {
    private let stubbedPID: pid_t
    private let stubbedBundleIdentifier: String?
    private let stubbedIsTerminated: Bool

    private(set) var activateCallCount = 0
    private(set) var lastActivateOptions: NSApplication.ActivationOptions?

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        isTerminated: Bool = false
    ) {
        self.stubbedPID = processIdentifier
        self.stubbedBundleIdentifier = bundleIdentifier
        self.stubbedIsTerminated = isTerminated
        super.init()
    }

    override var processIdentifier: pid_t { stubbedPID }
    override var bundleIdentifier: String? { stubbedBundleIdentifier }
    override var isTerminated: Bool { stubbedIsTerminated }

    override func activate(options: NSApplication.ActivationOptions = []) -> Bool {
        activateCallCount += 1
        lastActivateOptions = options
        return true
    }
}
