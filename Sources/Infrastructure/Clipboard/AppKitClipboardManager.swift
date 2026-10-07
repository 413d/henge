import Foundation
import AppKit

/// Concrete implementation of `ClipboardManaging` backed by macOS `NSPasteboard`.
///
/// Implements full-fidelity snapshotting and restoration by preserving all
/// declared UTI types and their raw data payloads per item.
public final class AppKitClipboardManager: ClipboardManaging, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
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

        return ClipboardSnapshot(changeCount: changeCount, items: itemSnapshots)
    }

    public func restore(_ snapshot: ClipboardSnapshot) -> Bool {
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
