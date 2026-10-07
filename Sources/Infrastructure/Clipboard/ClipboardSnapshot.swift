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

    public init(changeCount: Int, items: [PasteboardItemSnapshot]) {
        self.changeCount = changeCount
        self.items = items
    }

    public static let empty = ClipboardSnapshot(changeCount: 0, items: [])
}
