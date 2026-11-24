import AppKit
import SwiftUI

@MainActor
final class SingletonWindowController<Content: View>: NSObject, NSWindowDelegate {
    private weak var coordinator: HengeCoordinator?
    private var window: NSWindow?
    private var isClosingWindow = false

    private let title: String
    private let styleMask: NSWindow.StyleMask
    private let contentSize: NSSize?
    private let activateApplication: @MainActor () -> Void
    private let presentWindow: @MainActor (NSWindow) -> Void
    private let onShow: (@MainActor () -> Void)?
    private let onWillClose: (@MainActor (HengeCoordinator?) -> Void)?
    private let makeContent: @MainActor () -> Content

    init(
        coordinator: HengeCoordinator? = nil,
        title: String,
        styleMask: NSWindow.StyleMask,
        contentSize: NSSize? = nil,
        activateApplication: (@MainActor () -> Void)? = nil,
        presentWindow: (@MainActor (NSWindow) -> Void)? = nil,
        onShow: (@MainActor () -> Void)? = nil,
        onWillClose: (@MainActor (HengeCoordinator?) -> Void)? = nil,
        makeContent: @escaping @MainActor () -> Content
    ) {
        self.coordinator = coordinator
        self.title = title
        self.styleMask = styleMask
        self.contentSize = contentSize
        self.activateApplication = activateApplication ?? {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        self.presentWindow = presentWindow ?? { window in
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        self.onShow = onShow
        self.onWillClose = onWillClose
        self.makeContent = makeContent
        super.init()
    }

    func bind(coordinator: HengeCoordinator) {
        self.coordinator = coordinator
    }

    @discardableResult
    func showWindow() -> NSWindow? {
        guard let coordinator else {
            return nil
        }

        let targetWindow: NSWindow
        if let existingWindow = window {
            targetWindow = existingWindow
        } else {
            let hostingController = NSHostingController(
                rootView: makeContent().environmentObject(coordinator)
            )
            let createdWindow = NSWindow(contentViewController: hostingController)
            createdWindow.title = title
            createdWindow.styleMask = styleMask
            createdWindow.isReleasedWhenClosed = false
            if let contentSize {
                createdWindow.setContentSize(contentSize)
            }
            if onWillClose != nil {
                createdWindow.delegate = self
            }
            createdWindow.center()
            window = createdWindow
            targetWindow = createdWindow
        }

        onShow?()
        bringCurrentWindowToFront()

        if RunLoop.main.currentMode == .eventTracking {
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.bringCurrentWindowToFront()
                }
            }
        }

        return targetWindow
    }

    func closeWindow() {
        guard !isClosingWindow, let window else {
            return
        }
        isClosingWindow = true
        defer { isClosingWindow = false }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosingWindow else {
            return
        }
        isClosingWindow = true
        defer { isClosingWindow = false }
        onWillClose?(coordinator)
    }

    private func bringCurrentWindowToFront() {
        guard let window else {
            return
        }

        activateApplication()
        presentWindow(window)
    }
}
