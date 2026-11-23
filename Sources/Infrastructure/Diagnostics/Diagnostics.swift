import OSLog

enum DiagnosticsCategory: String, CaseIterable, Sendable {
    case hotkey, text, clipboard, config
    case loginItem = "login-item"
}

enum DiagnosticsLabel: String, Sendable {
    case snapshotCaptured, snapshotSkippedOversized, restoreSucceeded, restoreFailed
    case replacementSuperseded, pasteUnverified, replacementFailed
    case hotkeyRegistered, hotkeyRegistrationFailed, hotkeyUnregistered
    case configSaveSkipped, configSaveFailed, configBackupWritten, configLoadedDefaults
    case loginItemReconciled, loginItemUpdateFailed
    case accessibilityDenied, focusedElementUnavailable
}

enum DiagnosticsLengthBucket: String, Sendable {
    case empty, short, medium, long, huge
}

enum Diagnostics {
    static let subsystem = "io.github.413d.Henge"

    static func logger(_ category: DiagnosticsCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    static func lengthBucket(_ count: Int) -> DiagnosticsLengthBucket {
        switch count {
        case ...0:
            .empty
        case 1...64:
            .short
        case 65...1024:
            .medium
        case 1025...65_536:
            .long
        default:
            .huge
        }
    }

    /// Returns `nil` for anything that does not match `^[A-Za-z0-9._-]{1,255}$`.
    static func bundleIdentifier(_ raw: String) -> String? {
        guard !raw.isEmpty, raw.utf8.count <= 255 else {
            return nil
        }

        let isValid = raw.unicodeScalars.allSatisfy { scalar in
            isASCIIAlphanumeric(scalar)
                || scalar == "."
                || scalar == "_"
                || scalar == "-"
        }
        return isValid ? raw : nil
    }

    /// Returns `nil` if any type name does not match `^[A-Za-z0-9._+-]{1,128}$`.
    static func pasteboardTypeNames(_ raws: [String]) -> [String]? {
        let allValid = raws.allSatisfy { raw in
            guard !raw.isEmpty, raw.utf8.count <= 128 else {
                return false
            }

            return raw.unicodeScalars.allSatisfy { scalar in
                isASCIIAlphanumeric(scalar)
                    || scalar == "."
                    || scalar == "_"
                    || scalar == "+"
                    || scalar == "-"
            }
        }
        return allValid ? raws : nil
    }

    private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, // 0-9
             0x41...0x5A, // A-Z
             0x61...0x7A: // a-z
            true
        default:
            false
        }
    }
}
