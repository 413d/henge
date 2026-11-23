import Testing
import Foundation
import AppKit
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

    @Test
    func oversizedRepresentationsAreDetected() {
        let limit = ClipboardSizePolicy.maximumRepresentationBytes
        #expect(limit == 32 * 1024 * 1024)

        let exactLimitItem = PasteboardItemSnapshot(representations: [
            "public.png": Data(count: limit)
        ])
        #expect(ClipboardSizePolicy.oversizedTypes(in: [exactLimitItem]).isEmpty)

        let overLimitItem = PasteboardItemSnapshot(representations: [
            "public.png": Data(count: limit + 1)
        ])
        #expect(ClipboardSizePolicy.oversizedTypes(in: [overLimitItem]) == ["public.png"])

        let largeTextItem = PasteboardItemSnapshot(representations: [
            "public.utf8-plain-text": Data(count: limit + 1),
            "public.utf16-plain-text": Data(count: limit + 1),
            "public.utf16-external-plain-text": Data(count: limit + 1),
            "public.plain-text": Data(count: limit + 1),
            "NSStringPboardType": Data(count: limit + 1),
            "public.rtf": Data(count: limit + 1),
            "public.url": Data(count: limit + 1),
            "public.file-url": Data(count: limit + 1)
        ])
        #expect(ClipboardSizePolicy.oversizedTypes(in: [largeTextItem]).isEmpty)

        let unsortedDuplicates = [
            PasteboardItemSnapshot(representations: [
                "public.tiff": Data(count: limit + 1),
                "public.png": Data(count: limit + 1)
            ]),
            PasteboardItemSnapshot(representations: [
                "public.png": Data(count: limit + 10)
            ])
        ]
        #expect(ClipboardSizePolicy.oversizedTypes(in: unsortedDuplicates) == ["public.png", "public.tiff"])
    }

    @Test
    func snapshotMarksOversizedRepresentations() {
        let item = NSPasteboardItem()
        item.setData(Data(count: ClipboardSizePolicy.maximumRepresentationBytes + 1), forType: NSPasteboard.PasteboardType("public.png"))
        let backing = FakePasteboardBacking(changeCount: 7, pasteboardItems: [item])
        let manager = AppKitClipboardManager(pasteboard: backing)

        let snapshot = manager.snapshot()

        #expect(snapshot.changeCount == 7)
        #expect(snapshot.isRestorable == false)
        #expect(snapshot.oversizedTypes == ["public.png"])
        #expect(manager.restore(snapshot) == false)
        #expect(backing.changeCount == 7)
    }
}

private final class FakePasteboardBacking: PasteboardBacking {
    var changeCount: Int
    var pasteboardItems: [NSPasteboardItem]?

    init(changeCount: Int, pasteboardItems: [NSPasteboardItem]?) {
        self.changeCount = changeCount
        self.pasteboardItems = pasteboardItems
    }

    @discardableResult
    func clearContents() -> Int {
        changeCount += 1
        pasteboardItems = nil
        return changeCount
    }

    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool {
        changeCount += 1
        pasteboardItems = objects.compactMap { $0 as? NSPasteboardItem }
        return true
    }
}
