import Foundation

/// Abstraction for capturing and restoring clipboard state.
public protocol ClipboardManaging: AnyObject, Sendable {
    /// Takes a full-fidelity snapshot of the current clipboard contents.
    func snapshot() -> ClipboardSnapshot

    /// Restores the clipboard contents from a previous snapshot.
    ///
    /// - Parameter snapshot: The snapshot to restore.
    /// - Returns: `true` if restoration succeeded, `false` otherwise.
    func restore(_ snapshot: ClipboardSnapshot) -> Bool
}
