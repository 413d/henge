import ApplicationServices

/// The focused accessibility element resolved once per fix operation.
/// The element handle stays opaque to Application callers; Infrastructure
/// re-validates identity before every write.
struct TextTarget {
    let application: ApplicationIdentity
    let snapshot: FocusedElementSnapshot
    private let resolvedElement: AXUIElement?

    init(application: ApplicationIdentity, snapshot: FocusedElementSnapshot, element: AXUIElement? = nil) {
        self.application = application
        self.snapshot = snapshot
        self.resolvedElement = element
    }

    var element: AXUIElement? { resolvedElement }
}

extension TextTarget: Equatable {
    // Compares application + snapshot only; the AX handle is identity, not value.
    static func == (lhs: TextTarget, rhs: TextTarget) -> Bool {
        lhs.application == rhs.application && lhs.snapshot == rhs.snapshot
    }
}

struct TextContext: Equatable {
    let target: TextTarget
    let selection: SelectionSnapshot
}
