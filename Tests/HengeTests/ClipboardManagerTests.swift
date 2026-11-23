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

    @Test
    func restoreFallsBackToPlainTextWhenWriteFails() {
        let backing = FakePasteboardBacking(changeCount: 10, pasteboardItems: nil)
        backing.writeObjectsResult = false
        backing.writePlainTextFallbackResult = true
        let manager = AppKitClipboardManager(pasteboard: backing)

        let snapshot = ClipboardSnapshot(
            changeCount: 10,
            items: [
                PasteboardItemSnapshot(representations: [
                    "public.png": Data([0x89, 0x50, 0x4E, 0x47]),
                    "public.utf8-plain-text": Data("fallback text".utf8)
                ])
            ]
        )

        let restored = manager.restore(snapshot)

        #expect(restored == true)
        #expect(backing.writeObjectsCallCount == 1)
        #expect(backing.clearContentsCallCount == 2)
        #expect(backing.writtenPlainTextFallbacks == ["fallback text"])
        #expect(backing.pasteboardItems?.count == 1)
        #expect(backing.pasteboardItems?.first?.string(forType: .string) == "fallback text")
    }

    @Test
    func restoreReportsFailureWhenNoPlainTextRepresentation() {
        let backing = FakePasteboardBacking(changeCount: 10, pasteboardItems: nil)
        backing.writeObjectsResult = false
        let manager = AppKitClipboardManager(pasteboard: backing)

        let snapshot = ClipboardSnapshot(
            changeCount: 10,
            items: [
                PasteboardItemSnapshot(representations: [
                    "public.png": Data([0x89, 0x50, 0x4E, 0x47])
                ])
            ]
        )

        let restored = manager.restore(snapshot)

        #expect(restored == false)
        #expect(backing.writeObjectsCallCount == 1)
        #expect(backing.writtenPlainTextFallbacks.isEmpty)
    }

    @Test
    func restoreReportsFailureWhenPlainTextFallbackAlsoFails() {
        let backing = FakePasteboardBacking(changeCount: 10, pasteboardItems: nil)
        backing.writeObjectsResult = false
        backing.writePlainTextFallbackResult = false
        let manager = AppKitClipboardManager(pasteboard: backing)

        let snapshot = ClipboardSnapshot(
            changeCount: 10,
            items: [
                PasteboardItemSnapshot(representations: [
                    "public.utf8-plain-text": Data("hello".utf8)
                ])
            ]
        )

        let restored = manager.restore(snapshot)

        #expect(restored == false)
        #expect(backing.writtenPlainTextFallbacks == ["hello"])
    }

    @Test
    func restoreWritesAllRepresentationsOnSuccess() {
        let backing = FakePasteboardBacking(changeCount: 1, pasteboardItems: nil)
        let manager = AppKitClipboardManager(pasteboard: backing)

        let utf8Data = Data("styled".utf8)
        let htmlData = Data("<b>styled</b>".utf8)
        let snapshot = ClipboardSnapshot(
            changeCount: 1,
            items: [
                PasteboardItemSnapshot(representations: [
                    "public.utf8-plain-text": utf8Data,
                    "public.html": htmlData
                ])
            ]
        )

        let restored = manager.restore(snapshot)

        #expect(restored == true)
        #expect(backing.writtenPlainTextFallbacks.isEmpty)
        #expect(backing.pasteboardItems?.count == 1)
        let writtenItem = backing.pasteboardItems?.first
        #expect(writtenItem?.data(forType: NSPasteboard.PasteboardType("public.utf8-plain-text")) == utf8Data)
        #expect(writtenItem?.data(forType: NSPasteboard.PasteboardType("public.html")) == htmlData)
    }

    @Test
    func snapshotReadsChangeCountFromBacking() {
        let item = NSPasteboardItem()
        item.setString("text", forType: .string)
        let backing = FakePasteboardBacking(changeCount: 42, pasteboardItems: [item])
        let manager = AppKitClipboardManager(pasteboard: backing)

        let first = manager.snapshot()
        #expect(first.changeCount == 42)

        backing.changeCount = 99
        let second = manager.snapshot()
        #expect(second.changeCount == 99)
    }

    @Test
    func plainTextFallbackFollowsPriorityAndRtfFallback() {
        let rtfData = Data("{\\rtf1\\ansi RTF text}".utf8)
        let utf16Data = "utf16 text".data(using: .utf16)!
        let plainData = Data("plain text".utf8)
        let utf8Data = Data("utf8 text".utf8)

        let all = [PasteboardItemSnapshot(representations: [
            "public.utf8-plain-text": utf8Data,
            "public.utf16-plain-text": utf16Data,
            "public.plain-text": plainData,
            "public.rtf": rtfData
        ])]
        #expect(AppKitClipboardManager.plainTextFallback(in: all) == "utf8 text")

        let noUtf8 = [PasteboardItemSnapshot(representations: [
            "public.utf16-plain-text": utf16Data,
            "public.plain-text": plainData,
            "public.rtf": rtfData
        ])]
        #expect(AppKitClipboardManager.plainTextFallback(in: noUtf8) == "utf16 text")

        let plainAndRtf = [PasteboardItemSnapshot(representations: [
            "public.plain-text": plainData,
            "public.rtf": rtfData
        ])]
        #expect(AppKitClipboardManager.plainTextFallback(in: plainAndRtf) == "plain text")

        let rtfOnly = [PasteboardItemSnapshot(representations: [
            "public.rtf": rtfData
        ])]
        #expect(AppKitClipboardManager.plainTextFallback(in: rtfOnly) == "RTF text")

        let binaryOnly = [PasteboardItemSnapshot(representations: [
            "public.png": Data([0x01, 0x02])
        ])]
        #expect(AppKitClipboardManager.plainTextFallback(in: binaryOnly) == nil)
    }
}

private final class FakePasteboardBacking: PasteboardBacking {
    var changeCount: Int
    var pasteboardItems: [NSPasteboardItem]?
    var writeObjectsResult: Bool = true
    var writePlainTextFallbackResult: Bool = true
    private(set) var clearContentsCallCount: Int = 0
    private(set) var writeObjectsCallCount: Int = 0
    private(set) var writtenPlainTextFallbacks: [String] = []

    init(changeCount: Int, pasteboardItems: [NSPasteboardItem]?) {
        self.changeCount = changeCount
        self.pasteboardItems = pasteboardItems
    }

    @discardableResult
    func clearContents() -> Int {
        clearContentsCallCount += 1
        changeCount += 1
        pasteboardItems = nil
        return changeCount
    }

    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool {
        writeObjectsCallCount += 1
        guard writeObjectsResult else {
            return false
        }
        changeCount += 1
        pasteboardItems = objects.compactMap { $0 as? NSPasteboardItem }
        return true
    }

    func writePlainTextFallback(_ string: String) -> Bool {
        writtenPlainTextFallbacks.append(string)
        guard writePlainTextFallbackResult else {
            return false
        }
        changeCount += 1
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        pasteboardItems = [item]
        return true
    }
}
