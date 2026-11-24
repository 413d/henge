import Foundation
import Testing
@testable import Henge

struct AccessibilityPermissionProbeTests {
    final class ClockBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _currentDate: Date

        init(currentDate: Date = Date(timeIntervalSince1970: 1_000_000)) {
            self._currentDate = currentDate
        }

        var currentDate: Date {
            lock.lock()
            defer { lock.unlock() }
            return _currentDate
        }

        func advance(by interval: TimeInterval) {
            lock.lock()
            _currentDate = _currentDate.addingTimeInterval(interval)
            lock.unlock()
        }
    }

    private final class StubApplicationProvider: ActiveApplicationProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (@Sendable () -> Void)?

        func activeApplication() -> ApplicationIdentity? { nil }
        func application(bundleIdentifier: String) -> ApplicationIdentity? { nil }
        func waitForActivation(of application: ApplicationIdentity, timeout: TimeInterval) async {}

        func setActivationHandler(_ handler: (@Sendable () -> Void)?) {
            lock.lock()
            self.handler = handler
            lock.unlock()
        }

        func simulateActivation() {
            lock.lock()
            let current = handler
            lock.unlock()
            current?()
        }
    }

    final class CountingTrustProvider: @unchecked Sendable {
        private let lock = NSLock()
        private var _callCount = 0
        private var _result: Bool

        init(initialResult: Bool = true) {
            self._result = initialResult
        }

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _callCount
        }

        func setResult(_ value: Bool) {
            lock.lock()
            defer { lock.unlock() }
            _result = value
        }

        func isTrusted() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            _callCount += 1
            return _result
        }
    }

    @Test
    func tenCallsInsideTTLCallProviderOnce() {
        let clock = ClockBox()
        let provider = CountingTrustProvider(initialResult: true)
        let probe = AccessibilityPermissionProbe(
            timeToLive: 1.0,
            isTrustedProvider: { provider.isTrusted() },
            now: { clock.currentDate }
        )

        for _ in 0..<10 {
            #expect(probe.isTrusted() == true)
        }

        #expect(provider.callCount == 1)
    }

    @Test
    func advancingPastTTLReQueriesProvider() {
        let clock = ClockBox()
        let provider = CountingTrustProvider(initialResult: true)
        let probe = AccessibilityPermissionProbe(
            timeToLive: 1.0,
            isTrustedProvider: { provider.isTrusted() },
            now: { clock.currentDate }
        )

        #expect(probe.isTrusted() == true)
        #expect(provider.callCount == 1)

        // Advance 0.5s: still inside TTL
        clock.advance(by: 0.5)
        #expect(probe.isTrusted() == true)
        #expect(provider.callCount == 1)

        // Change provider return value to false (revocation) and advance past TTL
        provider.setResult(false)
        clock.advance(by: 0.6) // total 1.1s > 1.0s

        #expect(probe.isTrusted() == false)
        #expect(provider.callCount == 2)
    }

    @Test
    func invalidateForcesImmediateReQueryInsideTTL() {
        let clock = ClockBox()
        let provider = CountingTrustProvider(initialResult: true)
        let probe = AccessibilityPermissionProbe(
            timeToLive: 1.0,
            isTrustedProvider: { provider.isTrusted() },
            now: { clock.currentDate }
        )

        #expect(probe.isTrusted() == true)
        #expect(provider.callCount == 1)

        probe.invalidate()

        #expect(probe.isTrusted() == true)
        #expect(provider.callCount == 2)
    }

    @Test
    func cachedFalseFlipsToTrueAfterInvalidateOrTTL() {
        let clock = ClockBox()
        let provider = CountingTrustProvider(initialResult: false)
        let probe = AccessibilityPermissionProbe(
            timeToLive: 1.0,
            isTrustedProvider: { provider.isTrusted() },
            now: { clock.currentDate }
        )

        #expect(probe.isTrusted() == false)
        #expect(provider.callCount == 1)

        // Still inside TTL, provider flips to true
        provider.setResult(true)
        #expect(probe.isTrusted() == false)
        #expect(provider.callCount == 1)

        // Invalidate forces refresh
        probe.invalidate()
        #expect(probe.isTrusted() == true)
        #expect(provider.callCount == 2)

        // Advance past TTL with new flip back to false
        provider.setResult(false)
        clock.advance(by: 1.1)
        #expect(probe.isTrusted() == false)
        #expect(provider.callCount == 3)
    }

    @Test
    func concurrentBurstSafety() async {
        let clock = ClockBox()
        let provider = CountingTrustProvider(initialResult: true)
        let probe = AccessibilityPermissionProbe(
            timeToLive: 1.0,
            isTrustedProvider: { provider.isTrusted() },
            now: { clock.currentDate }
        )

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    probe.isTrusted()
                }
            }

            for await result in group {
                #expect(result == true)
            }
        }

        #expect(provider.callCount >= 1)
    }

    @Test
    func liveAppRuntimeCachesPermissionAndInvalidatesOnActivation() {
        let clock = ClockBox()
        let provider = CountingTrustProvider(initialResult: false)
        let probe = AccessibilityPermissionProbe(
            timeToLive: 1.0,
            isTrustedProvider: { provider.isTrusted() },
            now: { clock.currentDate }
        )
        let appProvider = StubApplicationProvider()
        let runtime = LiveAppRuntime(
            clipboardManager: MockClipboardManager(),
            applicationProvider: appProvider,
            permissionProbe: probe
        )

        #expect(runtime.hasAccessibilityPermission == false)
        #expect(runtime.hasAccessibilityPermission == false)
        #expect(provider.callCount == 1)

        provider.setResult(true)
        // Still cached before activation
        #expect(runtime.hasAccessibilityPermission == false)
        #expect(provider.callCount == 1)

        final class Flag: @unchecked Sendable {
            private let lock = NSLock()
            private var value = false
            func set(_ newValue: Bool) { lock.lock(); value = newValue; lock.unlock() }
            func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
        }
        let observedGrantInHandler = Flag()

        runtime.setActivationHandler { [probe] in
            observedGrantInHandler.set(probe.isTrusted())
        }

        appProvider.simulateActivation()

        #expect(observedGrantInHandler.get() == true)
        #expect(runtime.hasAccessibilityPermission == true)
        #expect(provider.callCount == 2)
    }
}
