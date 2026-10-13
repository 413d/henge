import Foundation

public enum LoginItemStatus: Equatable {
    case enabled
    case disabled
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
}

public final class InMemoryLoginItemManager: LoginItemManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var storedStatus: LoginItemStatus

    public init(initialEnabled: Bool) {
        storedStatus = initialEnabled ? .enabled : .disabled
    }

    public var status: LoginItemStatus {
        lock.lock()
        defer { lock.unlock() }
        return storedStatus
    }

    public func setEnabled(_ enabled: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        storedStatus = enabled ? .enabled : .disabled
    }
}
