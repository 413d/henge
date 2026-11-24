import ApplicationServices
import Foundation

/// Caches the Accessibility trust check. `AXIsProcessTrusted()` performs an IPC
/// round trip to `tccd`, so a short TTL keeps menu/status refreshes free while
/// still observing a freshly granted permission within a second.
final class AccessibilityPermissionProbe: @unchecked Sendable {
    static let defaultTimeToLive: TimeInterval = 1.0

    private let isTrustedProvider: @Sendable () -> Bool
    private let now: @Sendable () -> Date
    private let timeToLive: TimeInterval
    private let lock = NSLock()
    private var cachedResult: Bool?
    private var cachedAt: Date?

    init(
        timeToLive: TimeInterval = AccessibilityPermissionProbe.defaultTimeToLive,
        isTrustedProvider: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.timeToLive = timeToLive
        self.isTrustedProvider = isTrustedProvider
        self.now = now
    }

    func isTrusted() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let currentTime = now()
        if let cachedResult,
           let cachedAt {
            let elapsed = currentTime.timeIntervalSince(cachedAt)
            if elapsed >= 0, elapsed < timeToLive {
                return cachedResult
            }
        }

        let trusted = isTrustedProvider()
        cachedResult = trusted
        cachedAt = currentTime
        return trusted
    }

    func invalidate() {
        lock.lock()
        cachedResult = nil
        cachedAt = nil
        lock.unlock()
    }
}
