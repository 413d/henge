import Foundation

/// Represents the captured binary contents of a single pasteboard item across all its UTI types.
public struct PasteboardItemSnapshot: Equatable, Sendable {
    public let representations: [String: Data]

    public init(representations: [String: Data]) {
        self.representations = representations
    }
}

/// Full-fidelity snapshot of the pasteboard at a point in time, including changeCount and all items.
public struct ClipboardSnapshot: Equatable, Sendable {
    public let changeCount: Int
    public let items: [PasteboardItemSnapshot]
    /// UTI names of representations that exceed `ClipboardSizePolicy.maximumRepresentationBytes`
    /// and therefore make this snapshot non-restorable.
    public let oversizedTypes: [String]

    public init(changeCount: Int, items: [PasteboardItemSnapshot], oversizedTypes: [String] = []) {
        self.changeCount = changeCount
        self.items = items
        self.oversizedTypes = oversizedTypes
    }

    public var isRestorable: Bool { oversizedTypes.isEmpty }

    public static let empty = ClipboardSnapshot(changeCount: 0, items: [])
}

public enum ClipboardSizePolicy {
    public static let maximumRepresentationBytes = 32 * 1024 * 1024
    public static let exemptTypes: Set<String> = [
        "public.utf8-plain-text",
        "public.utf16-plain-text",
        "public.utf16-external-plain-text",
        "public.plain-text",
        "NSStringPboardType",
        "public.rtf",
        "public.url",
        "public.file-url"
    ]

    public static func oversizedTypes(in items: [PasteboardItemSnapshot]) -> [String] {
        var detected: Set<String> = []
        for item in items {
            for (type, data) in item.representations {
                if data.count > maximumRepresentationBytes, !exemptTypes.contains(type) {
                    detected.insert(type)
                }
            }
        }
        return detected.sorted()
    }
}
