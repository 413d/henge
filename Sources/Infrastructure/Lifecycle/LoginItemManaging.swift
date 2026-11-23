import Foundation

public enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
}

public enum LoginItemUpdateError: LocalizedError, Equatable {
    case updateFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .updateFailed(reason):
            return reason
        }
    }
}

public protocol LoginItemManaging: Sendable {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
    func openLoginItemSettings()
}

public final class InMemoryLoginItemManager: LoginItemManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var storedStatus: LoginItemStatus
    private var openLoginItemSettingsCallCountStorage = 0

    public init(initialEnabled: Bool) {
        storedStatus = initialEnabled ? .enabled : .disabled
    }

    public init(initialStatus: LoginItemStatus) {
        storedStatus = initialStatus
    }

    public var status: LoginItemStatus {
        lock.lock()
        defer { lock.unlock() }
        return storedStatus
    }

    public var openLoginItemSettingsCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return openLoginItemSettingsCallCountStorage
    }

    public func setEnabled(_ enabled: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        storedStatus = enabled ? .enabled : .disabled
    }

    public func openLoginItemSettings() {
        lock.lock()
        defer { lock.unlock() }
        openLoginItemSettingsCallCountStorage += 1
    }
}
