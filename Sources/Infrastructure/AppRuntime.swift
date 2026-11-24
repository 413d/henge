import Cocoa

protocol AppRuntime {
    var hasAccessibilityPermission: Bool { get }
    var activeApplication: ApplicationIdentity? { get }
    func applicationIdentity(for bundleIdentifier: String) -> ApplicationIdentity?
    var layoutMapper: LayoutMapping { get }
    var clipboardManager: ClipboardManaging { get }

    func openAccessibilitySettings()
    func requestAccessibilityPermission()
    func setActivationHandler(_ handler: (@Sendable () -> Void)?)
    @MainActor
    func prepareTargetApplicationForFixText(_ application: ApplicationIdentity) async -> Bool
    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws
    func unregisterFixTextHotkey()
    func inspectFocusedElement() -> FocusedElementProbe
    func inspectTextContext(in application: ApplicationIdentity) -> TextContextProbe
    func replaceText(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult
    func replaceTextUsingClipboard(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult
}

extension AppRuntime {
    func requestAccessibilityPermission() {
        openAccessibilitySettings()
    }

    func setActivationHandler(_ handler: (@Sendable () -> Void)?) {}

    @MainActor
    func prepareTargetApplicationForFixText(_ application: ApplicationIdentity) async -> Bool {
        true
    }

    func applicationIdentity(for bundleIdentifier: String) -> ApplicationIdentity? {
        ApplicationIdentity(bundleIdentifier: bundleIdentifier, displayName: bundleIdentifier)
    }

    func replaceTextUsingClipboard(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult {
        .unavailable(.unsupported)
    }
}

final class LiveAppRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool {
        permissionProbe.isTrusted()
    }

    let layoutMapper: LayoutMapping
    let clipboardManager: ClipboardManaging
    private let applicationProvider: ActiveApplicationProviding
    private let permissionProbe: AccessibilityPermissionProbe
    private let textService: AccessibilityTextService
    private let hotkeyRegistrar: HotkeyRegistrar
    private let applicationActivator: ApplicationActivator

    var activeApplication: ApplicationIdentity? {
        applicationProvider.activeApplication()
    }

    func applicationIdentity(for bundleIdentifier: String) -> ApplicationIdentity? {
        applicationProvider.application(bundleIdentifier: bundleIdentifier)
    }

    func setActivationHandler(_ handler: (@Sendable () -> Void)?) {
        guard let handler else {
            applicationProvider.setActivationHandler(nil)
            return
        }

        let permissionProbe = permissionProbe
        applicationProvider.setActivationHandler {
            permissionProbe.invalidate()
            handler()
        }
    }

    init(
        layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper(),
        clipboardManager: ClipboardManaging = AppKitClipboardManager(),
        clipboardReplacement: ClipboardReplacing? = nil,
        applicationProvider: ActiveApplicationProviding = WorkspaceActiveApplicationProvider(),
        permissionProbe: AccessibilityPermissionProbe = AccessibilityPermissionProbe(),
        focusedElementResolver: (() -> Result<ResolvedFocusedElement, FocusedElementProbeFailure>)? = nil,
        textService: AccessibilityTextService? = nil,
        hotkeyRegistrar: HotkeyRegistrar = HotkeyRegistrar(),
        applicationActivator: ApplicationActivator? = nil
    ) {
        self.layoutMapper = layoutMapper
        self.clipboardManager = clipboardManager
        self.applicationProvider = applicationProvider
        self.permissionProbe = permissionProbe
        self.hotkeyRegistrar = hotkeyRegistrar

        let resolvedClipboardReplacement = clipboardReplacement ?? AppKitClipboardReplacement(clipboardManager: clipboardManager)
        let resolvedTextService = textService ?? AccessibilityTextService(
            clipboardReplacement: resolvedClipboardReplacement,
            applicationProvider: applicationProvider,
            permissionProbe: permissionProbe,
            focusedElementResolver: focusedElementResolver
        )
        self.textService = resolvedTextService
        self.applicationActivator = applicationActivator ?? ApplicationActivator(
            applicationProvider: applicationProvider,
            hasFocusedElement: {
                if case .success = resolvedTextService.resolveFocusedElement() {
                    return true
                }
                return false
            }
        )
    }

    func openAccessibilitySettings() {
        permissionProbe.invalidate()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        let openURL: @Sendable () -> Void = {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(url, configuration: configuration)
        }

        if Thread.isMainThread, RunLoop.main.currentMode == .eventTracking {
            RunLoop.main.perform(inModes: [.default]) {
                openURL()
            }
        } else {
            openURL()
        }
    }

    func requestAccessibilityPermission() {
        permissionProbe.requestPermission()
        openAccessibilitySettings()
    }

    @MainActor
    func prepareTargetApplicationForFixText(_ application: ApplicationIdentity) async -> Bool {
        await applicationActivator.prepareTargetApplicationForFixText(application)
    }

    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {
        try hotkeyRegistrar.register(shortcut: shortcut, handler: handler)
    }

    func unregisterFixTextHotkey() {
        hotkeyRegistrar.unregister()
    }

    func inspectFocusedElement() -> FocusedElementProbe {
        textService.inspectFocusedElement()
    }

    func inspectTextContext(in application: ApplicationIdentity) -> TextContextProbe {
        textService.inspectTextContext(in: application)
    }

    func replaceText(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult {
        textService.replaceText(target, range: range, context: context, expectedText: expectedText, with: text)
    }

    func replaceTextUsingClipboard(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult {
        textService.replaceTextUsingClipboard(target, range: range, context: context, expectedText: expectedText, with: text)
    }
}
