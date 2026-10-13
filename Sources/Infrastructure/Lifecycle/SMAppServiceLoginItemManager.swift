import Dispatch
import Foundation
import ServiceManagement

public final class SMAppServiceLoginItemManager: LoginItemManaging, @unchecked Sendable {
    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    public var status: LoginItemStatus {
        switch service.status {
        case .enabled:
            return .enabled
        default:
            return .disabled
        }
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
}
