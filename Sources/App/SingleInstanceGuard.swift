import AppKit
import Foundation

public enum SingleInstanceGuard {
    /// Pure core: (running PIDs, current PID) -> earliest running peer PID to activate.
    public static func otherInstance(
        processIdentifiers: [pid_t],
        currentProcessIdentifier: pid_t
    ) -> pid_t? {
        processIdentifiers
            .filter { $0 != currentProcessIdentifier }
            .min()
    }

    /// Shell: if another instance with the same bundle identifier is running, activate it and return true.
    @discardableResult
    public static func enforce(
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        runningApplications: [NSRunningApplication] = NSWorkspace.shared.runningApplications
    ) -> Bool {
        guard let bundleId = bundleIdentifier, !bundleId.isEmpty else {
            // When running under tests or CLI tools where Bundle.main has no bundleIdentifier, exempt
            return false
        }

        let matchingPeers = runningApplications.filter {
            $0.bundleIdentifier == bundleId && !$0.isTerminated && $0.processIdentifier > 0
        }
        guard let targetProcessIdentifier = otherInstance(
            processIdentifiers: matchingPeers.map(\.processIdentifier),
            currentProcessIdentifier: currentProcessIdentifier
        ),
        let peer = matchingPeers.first(where: { $0.processIdentifier == targetProcessIdentifier }) else {
            return false
        }

        peer.activate(options: [.activateIgnoringOtherApps])
        return true
    }
}
