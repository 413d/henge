import Dispatch
import Foundation
import ServiceManagement

public final class SMAppServiceLoginItemManager: LoginItemManaging, @unchecked Sendable {
    private let service: SMAppService
    private let statusProvider: (@Sendable () -> SMAppService.Status)?

    public init(service: SMAppService = .mainApp) {
        self.service = service
        statusProvider = nil
    }

    init(
        service: SMAppService = .mainApp,
        statusProvider: @escaping @Sendable () -> SMAppService.Status
    ) {
        self.service = service
        self.statusProvider = statusProvider
    }

    public var status: LoginItemStatus {
        Self.mapStatus(statusProvider?() ?? service.status)
    }

    public func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            throw LoginItemUpdateError.updateFailed(error.localizedDescription)
        }
    }

    public func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func mapStatus(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .disabled
        @unknown default:
            return .disabled
        }
    }
}
