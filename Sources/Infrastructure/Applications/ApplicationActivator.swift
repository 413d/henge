import AppKit
import Foundation

enum ActivationWaiter {
    private final class ActivationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isResumed = false
        private var continuation: CheckedContinuation<Void, Never>?

        func setContinuation(_ continuation: CheckedContinuation<Void, Never>) {
            lock.lock()
            if isResumed {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func resume() {
            lock.lock()
            guard !isResumed else {
                lock.unlock()
                return
            }
            isResumed = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume()
        }
    }

    static func sleepNanoseconds(for timeout: TimeInterval) -> UInt64 {
        guard timeout.isFinite, timeout > 0 else { return 0 }
        let clamped = min(timeout, 60.0)
        return UInt64((clamped * 1_000_000_000).rounded())
    }

    static func wait(
        bundleIdentifier: String,
        source: WorkspaceApplicationSource,
        timeout: TimeInterval
    ) async {
        let nanoseconds = sleepNanoseconds(for: timeout)
        guard nanoseconds > 0 else { return }

        let gate = ActivationGate()
        let token = source.observeActivations { snapshot in
            guard !snapshot.isTerminated,
                  snapshot.bundleIdentifier == bundleIdentifier else {
                return
            }
            gate.resume()
        }
        defer { source.stopObserving(token) }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: nanoseconds)
            gate.resume()
        }
        defer { timeoutTask.cancel() }

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.setContinuation(continuation)
            }
        } onCancel: {
            gate.resume()
        }
    }
}

final class ApplicationActivator {
    private let applicationProvider: ActiveApplicationProviding
    private let hasFocusedElement: () -> Bool

    init(
        applicationProvider: ActiveApplicationProviding,
        hasFocusedElement: @escaping () -> Bool
    ) {
        self.applicationProvider = applicationProvider
        self.hasFocusedElement = hasFocusedElement
    }

    @MainActor
    func prepareTargetApplicationForFixText(_ application: ApplicationIdentity) async -> Bool {
        if RunLoop.main.currentMode == .eventTracking {
            await withCheckedContinuation { continuation in
                RunLoop.main.perform(inModes: [.default]) {
                    continuation.resume()
                }
            }
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        if applicationProvider.isFrontmost(application),
           NSApplication.shared.isActive == false,
           hasFocusedElement() {
            return true
        }

        guard applicationProvider.activateApplication(application) else {
            return false
        }

        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            if applicationProvider.isFrontmost(application),
               hasFocusedElement() {
                return true
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            await applicationProvider.waitForActivation(of: application, timeout: remaining)
        }

        return applicationProvider.isFrontmost(application)
    }
}
