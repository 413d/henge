import Foundation
import ServiceManagement
import Testing
@testable import Henge

struct LoginItemManagerTests {
    @Test
    func inMemoryLoginItemManagerTracksEnabledState() throws {
        let manager: any LoginItemManaging = InMemoryLoginItemManager(initialEnabled: true)

        #expect(manager.status == .enabled)

        try manager.setEnabled(false)

        #expect(manager.status == .disabled)
    }

    @Test
    func loginItemManagingBehavesAsIdempotentToggle() throws {
        let manager = InMemoryLoginItemManager(initialEnabled: false)

        #expect(manager.status == .disabled)

        try manager.setEnabled(false)
        try manager.setEnabled(false)

        #expect(manager.status == .disabled)
    }

    @Test
    func smAppServiceLoginItemManagerMapsServiceStatusesIncludingRequiresApproval() {
        #expect(SMAppServiceLoginItemManager.mapStatus(.enabled) == .enabled)
        #expect(SMAppServiceLoginItemManager.mapStatus(.requiresApproval) == .requiresApproval)
        #expect(SMAppServiceLoginItemManager.mapStatus(.notRegistered) == .disabled)
        #expect(SMAppServiceLoginItemManager.mapStatus(.notFound) == .disabled)

        let requiresApprovalManager = SMAppServiceLoginItemManager(statusProvider: { .requiresApproval })
        #expect(requiresApprovalManager.status == .requiresApproval)
    }

    @Test
    func inMemoryLoginItemManagerTracksOpenLoginItemSettingsCalls() {
        let manager = InMemoryLoginItemManager(initialStatus: .requiresApproval)

        #expect(manager.status == .requiresApproval)
        #expect(manager.openLoginItemSettingsCallCount == 0)

        manager.openLoginItemSettings()

        #expect(manager.openLoginItemSettingsCallCount == 1)
    }
}
