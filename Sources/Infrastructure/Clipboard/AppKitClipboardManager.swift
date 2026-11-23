import Foundation
import AppKit

public protocol PasteboardBacking: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
    @discardableResult
    func clearContents() -> Int
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

public final class SystemPasteboardBacking: PasteboardBacking, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }

    public var pasteboardItems: [NSPasteboardItem]? {
        pasteboard.pasteboardItems
    }

    @discardableResult
    public func clearContents() -> Int {
        pasteboard.clearContents()
    }

    public func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool {
        pasteboard.writeObjects(objects)
    }
}

/// Concrete implementation of `ClipboardManaging` backed by macOS `NSPasteboard`.
///
/// Implements full-fidelity snapshotting and restoration by preserving all
/// declared UTI types and their raw data payloads per item.
public final class AppKitClipboardManager: ClipboardManaging, @unchecked Sendable {
    private let pasteboard: PasteboardBacking

    public init(pasteboard: PasteboardBacking = SystemPasteboardBacking()) {
        self.pasteboard = pasteboard
    }

    public func snapshot() -> ClipboardSnapshot {
        let changeCount = pasteboard.changeCount
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            return ClipboardSnapshot(changeCount: changeCount, items: [])
        }

        let itemSnapshots = items.map { item -> PasteboardItemSnapshot in
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            return PasteboardItemSnapshot(representations: dict)
        }

        let oversizedTypes = ClipboardSizePolicy.oversizedTypes(in: itemSnapshots)
        return ClipboardSnapshot(
            changeCount: changeCount,
            items: itemSnapshots,
            oversizedTypes: oversizedTypes
        )
    }

    public func restore(_ snapshot: ClipboardSnapshot) -> Bool {
        guard snapshot.isRestorable else {
            return false
        }

        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else {
            return true
        }

        var newItems: [NSPasteboardItem] = []
        for itemSnapshot in snapshot.items {
            let item = NSPasteboardItem()
            for (typeRaw, data) in itemSnapshot.representations {
                item.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
            }
            newItems.append(item)
        }

        return pasteboard.writeObjects(newItems)
    }
}
