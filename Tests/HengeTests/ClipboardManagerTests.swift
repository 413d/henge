import Testing
import Foundation
@testable import Henge

final class MockClipboardManager: ClipboardManaging, @unchecked Sendable {
    private var currentItems: [PasteboardItemSnapshot] = []
    private var changeCount: Int = 0

    func setMockItem(_ representations: [String: Data]) {
        changeCount += 1
        currentItems = [PasteboardItemSnapshot(representations: representations)]
    }

    func setMockItems(_ items: [[String: Data]]) {
        changeCount += 1
        currentItems = items.map { PasteboardItemSnapshot(representations: $0) }
    }

    func snapshot() -> ClipboardSnapshot {
        ClipboardSnapshot(changeCount: changeCount, items: currentItems)
    }

    func restore(_ snapshot: ClipboardSnapshot) -> Bool {
        changeCount += 1
        currentItems = snapshot.items
        return true
    }
}

struct ClipboardManagerTests {
    @Test
    func mockClipboardCapturesAndRestoresItems() {
        let manager = MockClipboardManager()

        let initial = manager.snapshot()
        #expect(initial.items.isEmpty)

        manager.setMockItem(["public.utf8-plain-text": "hello".data(using: .utf8)!])
        let captured = manager.snapshot()
        #expect(captured.items.count == 1)
        #expect(captured.items[0].representations["public.utf8-plain-text"] == "hello".data(using: .utf8)!)

        manager.setMockItem(["public.utf8-plain-text": "replacement".data(using: .utf8)!])
        #expect(manager.snapshot().items[0].representations["public.utf8-plain-text"] == "replacement".data(using: .utf8)!)

        let restored = manager.restore(captured)
        #expect(restored == true)
        #expect(manager.snapshot().items[0].representations["public.utf8-plain-text"] == "hello".data(using: .utf8)!)
    }

    @Test
    func mockClipboardRestoresEmptyState() {
        let manager = MockClipboardManager()
        let emptySnapshot = manager.snapshot()

        manager.setMockItem(["public.utf8-plain-text": "temp".data(using: .utf8)!])
        #expect(!manager.snapshot().items.isEmpty)

        let restored = manager.restore(emptySnapshot)
        #expect(restored == true)
        #expect(manager.snapshot().items.isEmpty)
    }

    @Test
    func snapshotPreservesMultipleTypesPerItem() {
        let manager = MockClipboardManager()
        let types: [String: Data] = [
            "public.utf8-plain-text": "styled".data(using: .utf8)!,
            "public.html": "<b>styled</b>".data(using: .utf8)!,
            "com.apple.flat-rtfd": Data([0x01, 0x02, 0x03])
        ]
        manager.setMockItem(types)
        let snap = manager.snapshot()

        #expect(snap.items[0].representations.count == 3)
        #expect(snap.items[0].representations["public.html"] == "<b>styled</b>".data(using: .utf8)!)
    }
}
