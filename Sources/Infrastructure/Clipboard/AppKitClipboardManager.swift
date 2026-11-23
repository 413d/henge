import Foundation
import AppKit

public protocol PasteboardBacking: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
    @discardableResult
    func clearContents() -> Int
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
    func writePlainTextFallback(_ string: String) -> Bool
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

    public func writePlainTextFallback(_ string: String) -> Bool {
        pasteboard.setString(string, forType: .string)
    }
}

/// Concrete implementation of `ClipboardManaging` backed by macOS `NSPasteboard`.
///
/// Implements full-fidelity snapshotting and restoration by preserving all
/// declared UTI types and their raw data payloads per item.
public final class AppKitClipboardManager: ClipboardManaging, @unchecked Sendable {
    private let pasteboard: PasteboardBacking
    private let logger = Diagnostics.logger(.clipboard)

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
            logger.warning("\(DiagnosticsLabel.restoreFailed.rawValue, privacy: .public) reason=oversized")
            return false
        }

        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else {
            logger.info("\(DiagnosticsLabel.restoreSucceeded.rawValue, privacy: .public) items=0 fallback=false")
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

        if pasteboard.writeObjects(newItems) {
            logger.info("\(DiagnosticsLabel.restoreSucceeded.rawValue, privacy: .public) items=\(snapshot.items.count, privacy: .public) fallback=false")
            return true
        }

        guard let fallbackText = Self.plainTextFallback(in: snapshot.items) else {
            logger.error("\(DiagnosticsLabel.restoreFailed.rawValue, privacy: .public) items=\(snapshot.items.count, privacy: .public) hasFallback=false")
            return false
        }

        pasteboard.clearContents()
        if pasteboard.writePlainTextFallback(fallbackText) {
            logger.notice("\(DiagnosticsLabel.restoreSucceeded.rawValue, privacy: .public) items=\(snapshot.items.count, privacy: .public) fallback=true")
            return true
        }

        logger.error("\(DiagnosticsLabel.restoreFailed.rawValue, privacy: .public) items=\(snapshot.items.count, privacy: .public) hasFallback=true")
        return false
    }

    public static func plainTextFallback(in items: [PasteboardItemSnapshot]) -> String? {
        for item in items {
            if let data = item.representations["public.utf8-plain-text"],
               let text = String(data: data, encoding: .utf8),
               !text.isEmpty {
                return text
            }
        }
        for item in items {
            if let data = item.representations["public.utf16-plain-text"],
               let text = decodeUTF16(data),
               !text.isEmpty {
                return text
            }
        }
        for item in items {
            if let data = item.representations["public.plain-text"],
               let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .macOSRoman),
               !text.isEmpty {
                return text
            }
        }
        for item in items {
            if let data = item.representations["public.rtf"],
               let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string,
               !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private static func decodeUTF16(_ data: Data) -> String? {
        if data.starts(with: [0xFE, 0xFF]) || data.starts(with: [0xFF, 0xFE]) {
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .utf16LittleEndian)
    }
}
