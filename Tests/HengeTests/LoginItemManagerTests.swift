import Foundation
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
}
