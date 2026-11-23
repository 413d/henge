import AppKit
import Foundation
import Testing
@testable import Henge

@MainActor
struct MenuBarActionsTests {
    @Test
    func openSettingsRefreshesPermissionsAndInvokesSettingsPresenter() {
        let store = InMemoryConfigurationStore()
        let runtime = MenuBarTestRuntime(hasAccessibilityPermission: false)
        let loginItemManager = MenuBarTestLoginItemManager(currentStatus: .disabled)
        var presentSettingsCallCount = 0

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime,
                loginItemManager: loginItemManager
            ),
            presentSettings: {
                presentSettingsCallCount += 1
            }
        )

        #expect(coordinator.state.accessibilityGranted == false)
        #expect(coordinator.state.launchAtLoginEnabled == false)

        runtime.hasAccessibilityPermission = true
        loginItemManager.currentStatus = .enabled

        coordinator.openSettings()

        #expect(presentSettingsCallCount == 1)
        #expect(coordinator.state.accessibilityGranted == true)
        #expect(coordinator.state.launchAtLoginEnabled == true)
    }

    @Test
    func settingsWindowControllerCreatesAndReusesSettingsWindowAfterClose() {
        let store = InMemoryConfigurationStore()
        let runtime = MenuBarTestRuntime(hasAccessibilityPermission: true)
        var activationCount = 0
        var orderedWindows: [NSWindow] = []

        let controller = SettingsWindowController(
            activateApplication: {
                activationCount += 1
            },
            presentWindow: { window in
                orderedWindows.append(window)
            }
        )

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime,
                loginItemManager: MenuBarTestLoginItemManager(currentStatus: .disabled)
            ),
            presentSettings: {
                controller.showWindow()
            }
        )
        controller.bind(coordinator: coordinator)

        let firstWindow = controller.showWindow()
        defer { firstWindow?.orderOut(nil) }

        #expect(firstWindow != nil)
        #expect(firstWindow?.title == "Henge Settings")
        #expect(firstWindow?.isReleasedWhenClosed == false)
        #expect(activationCount == 1)
        #expect(orderedWindows.count == 1)

        firstWindow?.close()

        let secondWindow = controller.showWindow()
        #expect(secondWindow === firstWindow)
        #expect(activationCount == 2)
        #expect(orderedWindows.count == 2)
    }

    @Test
    func workspaceProviderReturnsLastExternalApplicationWhenHengeBecomesFrontmost() {
        let notes = WorkspaceApplicationSnapshot(
            processIdentifier: 4100,
            bundleIdentifier: "com.apple.Notes",
            localizedName: "Notes",
            isTerminated: false
        )
        let henge = WorkspaceApplicationSnapshot(
            processIdentifier: 97735,
            bundleIdentifier: "io.github.413d.Henge",
            localizedName: "Henge",
            isTerminated: false
        )
        let workspace = FakeWorkspaceApplicationSource(
            frontmost: notes,
            running: [notes, henge]
        )
        let provider = WorkspaceActiveApplicationProvider(
            workspace: workspace,
            selfBundleIdentifier: "io.github.413d.Henge"
        )

        #expect(provider.activeApplication()?.bundleIdentifier == "com.apple.Notes")

        workspace.setFrontmost(henge)

        let resolved = provider.activeApplication()
        #expect(resolved?.bundleIdentifier == "com.apple.Notes")
        #expect(resolved?.displayName == "Notes")
        if let resolved {
            #expect(provider.activeProcessIdentifier(for: resolved) == 4100)
            #expect(provider.isFrontmost(resolved) == false)
        }
    }

    @Test
    func workspaceProviderUpdatesTrackedExternalAppViaActivationNotifications() {
        let notes = WorkspaceApplicationSnapshot(
            processIdentifier: 4100,
            bundleIdentifier: "com.apple.Notes",
            localizedName: "Notes",
            isTerminated: false
        )
        let safari = WorkspaceApplicationSnapshot(
            processIdentifier: 5200,
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            isTerminated: false
        )
        let henge = WorkspaceApplicationSnapshot(
            processIdentifier: 97735,
            bundleIdentifier: "io.github.413d.Henge",
            localizedName: "Henge",
            isTerminated: false
        )
        let workspace = FakeWorkspaceApplicationSource(
            frontmost: henge,
            running: [notes, safari, henge]
        )
        let provider = WorkspaceActiveApplicationProvider(
            workspace: workspace,
            selfBundleIdentifier: "io.github.413d.Henge"
        )

        #expect(provider.activeApplication() == nil)

        workspace.simulateActivation(notes)
        workspace.simulateActivation(safari)
        workspace.simulateActivation(henge)

        let resolved = provider.activeApplication()
        #expect(resolved?.bundleIdentifier == "com.apple.Safari")
        if let resolved {
            #expect(provider.activeProcessIdentifier(for: resolved) == 5200)
        }
    }

    @Test
    func workspaceProviderReturnsNilWhenTrackedExternalApplicationTerminates() {
        let notes = WorkspaceApplicationSnapshot(
            processIdentifier: 4100,
            bundleIdentifier: "com.apple.Notes",
            localizedName: "Notes",
            isTerminated: false
        )
        let henge = WorkspaceApplicationSnapshot(
            processIdentifier: 97735,
            bundleIdentifier: "io.github.413d.Henge",
            localizedName: "Henge",
            isTerminated: false
        )
        let workspace = FakeWorkspaceApplicationSource(
            frontmost: notes,
            running: [notes, henge]
        )
        let provider = WorkspaceActiveApplicationProvider(
            workspace: workspace,
            selfBundleIdentifier: "io.github.413d.Henge"
        )

        workspace.setFrontmost(henge)
        workspace.terminate(processIdentifier: 4100)

        #expect(provider.activeApplication() == nil)
    }

    @Test
    func workspaceProviderActivatesTrackedExternalApplicationProcess() {
        let notes = WorkspaceApplicationSnapshot(
            processIdentifier: 4100,
            bundleIdentifier: "com.apple.Notes",
            localizedName: "Notes",
            isTerminated: false
        )
        let henge = WorkspaceApplicationSnapshot(
            processIdentifier: 97735,
            bundleIdentifier: "io.github.413d.Henge",
            localizedName: "Henge",
            isTerminated: false
        )
        let workspace = FakeWorkspaceApplicationSource(
            frontmost: notes,
            running: [notes, henge]
        )
        let provider = WorkspaceActiveApplicationProvider(
            workspace: workspace,
            selfBundleIdentifier: "io.github.413d.Henge"
        )

        workspace.setFrontmost(henge)

        guard let target = provider.activeApplication() else {
            Issue.record("Expected Notes to remain tracked as target application")
            return
        }

        let didActivate = provider.activateApplication(target)
        #expect(didActivate == true)
        #expect(workspace.activatedProcessIdentifiers == [4100])
        #expect(provider.isFrontmost(target) == true)
    }

    @Test
    func activeApplicationProviderReportsActivations() {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0

            func increment() {
                lock.lock()
                value += 1
                lock.unlock()
            }

            var count: Int {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }

        let notes = WorkspaceApplicationSnapshot(
            processIdentifier: 4100,
            bundleIdentifier: "com.apple.Notes",
            localizedName: "Notes",
            isTerminated: false
        )
        let henge = WorkspaceApplicationSnapshot(
            processIdentifier: 97735,
            bundleIdentifier: "io.github.413d.Henge",
            localizedName: "Henge",
            isTerminated: false
        )
        let workspace = FakeWorkspaceApplicationSource(
            frontmost: henge,
            running: [notes, henge]
        )
        let provider = WorkspaceActiveApplicationProvider(
            workspace: workspace,
            selfBundleIdentifier: "io.github.413d.Henge"
        )
        let counter = Counter()
        provider.setActivationHandler {
            counter.increment()
        }

        workspace.simulateActivation(henge)
        #expect(counter.count == 0)

        workspace.simulateActivation(notes)
        #expect(counter.count == 1)
    }

    @Test
    func triggerFixTextRestoresTargetFocusAfterMenuDismissalAndTransformsWordEndToEnd() async {
        let notes = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let runtime = MenuBarEditorRuntime(
            hasAccessibilityPermission: true,
            activeApplication: notes,
            initiallyFocused: false,
            text: "Hello ghbdtn",
            selectedRange: SelectionRangeSnapshot(location: 12, length: 0),
            isSecure: false
        )
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper,
                casePreserver: DefaultCasePreserver()
            )
        )
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime,
                loginItemManager: MenuBarTestLoginItemManager(currentStatus: .disabled)
            )
        )

        coordinator.triggerFixText()
        await runtime.waitForFixTextCompletion()

        #expect(runtime.preparedApplications == [notes])
        #expect(runtime.text == "Hello привет")
        #expect(coordinator.lastProbeStatusText == "Correction attempted.")
    }

    @Test
    func triggerFixTextIsCompleteNoOpForExcludedApplication() async {
        let excludedApp = ApplicationIdentity(bundleIdentifier: "com.1password.1password", displayName: "1Password")!
        let store = InMemoryConfigurationStore()
        store.save(
            AppConfiguration(
                isEnabled: true,
                excludedApplicationBundleIdentifiers: ["com.1password.1password"]
            )
        )
        let runtime = MenuBarEditorRuntime(
            hasAccessibilityPermission: true,
            activeApplication: excludedApp,
            initiallyFocused: false,
            text: "ghbdtn",
            selectedRange: SelectionRangeSnapshot(location: 0, length: 6),
            isSecure: false
        )
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper,
                casePreserver: DefaultCasePreserver()
            )
        )
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: useCase,
                runtime: runtime,
                loginItemManager: MenuBarTestLoginItemManager(currentStatus: .disabled)
            )
        )

        coordinator.triggerFixText()
        await Task.yield()

        #expect(runtime.preparedApplications.isEmpty)
        #expect(runtime.text == "ghbdtn")
        #expect(coordinator.lastProbeStatusText == nil)
    }

    @Test
    func triggerFixTextLeavesSecureFieldUntouchedAfterRestoringFocus() async {
        let safari = ApplicationIdentity(bundleIdentifier: "com.apple.Safari", displayName: "Safari")!
        let runtime = MenuBarEditorRuntime(
            hasAccessibilityPermission: true,
            activeApplication: safari,
            initiallyFocused: false,
            text: "ghbdtn",
            selectedRange: SelectionRangeSnapshot(location: 0, length: 6),
            isSecure: true
        )
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper,
                casePreserver: DefaultCasePreserver()
            )
        )
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime,
                loginItemManager: MenuBarTestLoginItemManager(currentStatus: .disabled)
            )
        )

        coordinator.triggerFixText()
        await runtime.waitForPreparation()
        await Task.yield()

        #expect(runtime.preparedApplications == [safari])
        #expect(runtime.text == "ghbdtn")
        #expect(runtime.replaceCallCount == 0)
        #expect(coordinator.lastProbeStatusText?.contains("secure text field") == true)
    }

    @Test
    func triggerFixTextRefreshesRevokedAccessibilityPermissionWithoutRunningUseCase() async {
        let notes = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let runtime = MenuBarEditorRuntime(
            hasAccessibilityPermission: true,
            activeApplication: notes,
            initiallyFocused: true,
            text: "ghbdtn",
            selectedRange: SelectionRangeSnapshot(location: 0, length: 6),
            isSecure: false
        )
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper,
                casePreserver: DefaultCasePreserver()
            )
        )
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime,
                loginItemManager: MenuBarTestLoginItemManager(currentStatus: .disabled)
            )
        )

        #expect(coordinator.state.accessibilityGranted == true)
        runtime.hasAccessibilityPermission = false

        coordinator.triggerFixText()
        await Task.yield()

        #expect(coordinator.state.accessibilityGranted == false)
        #expect(runtime.preparedApplications.isEmpty)
        #expect(runtime.text == "ghbdtn")
        #expect(coordinator.lastProbeStatusText == FocusedElementProbeFailure.missingPermission.description)
    }

    @Test
    func menuBarLifecycleObserverRefreshesPermissions() async {
        let runtime = MenuBarTestRuntime(hasAccessibilityPermission: false)
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime,
                loginItemManager: MenuBarTestLoginItemManager(currentStatus: .disabled)
            )
        )
        let menuCenter = NotificationCenter()
        let observer = MenuBarLifecycleObserver(menuNotificationCenter: menuCenter)
        observer.bind(coordinator: coordinator)

        #expect(coordinator.state.accessibilityGranted == false)
        #expect(coordinator.statusItemSymbolName == "exclamationmark.cloud")

        runtime.hasAccessibilityPermission = true
        runtime.activationHandler?()
        await Task.yield()

        #expect(coordinator.state.accessibilityGranted == true)
        #expect(coordinator.statusItemSymbolName == "cloud.fill")

        runtime.hasAccessibilityPermission = false
        menuCenter.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        await Task.yield()

        #expect(coordinator.state.accessibilityGranted == false)
        #expect(coordinator.statusItemSymbolName == "exclamationmark.cloud")
        withExtendedLifetime(observer) {}
    }
}

private final class MenuBarTestLoginItemManager: LoginItemManaging, @unchecked Sendable {
    var currentStatus: LoginItemStatus

    init(currentStatus: LoginItemStatus) {
        self.currentStatus = currentStatus
    }

    var status: LoginItemStatus {
        currentStatus
    }

    func setEnabled(_ enabled: Bool) throws {
        currentStatus = enabled ? .enabled : .disabled
    }
}

private final class MenuBarTestRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool
    var activeApplication: ApplicationIdentity? = ApplicationIdentity(
        bundleIdentifier: "com.apple.Notes",
        displayName: "Notes"
    )
    let layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper()
    let clipboardManager: ClipboardManaging = MockClipboardManager()
    var activationHandler: (@Sendable () -> Void)?

    init(hasAccessibilityPermission: Bool) {
        self.hasAccessibilityPermission = hasAccessibilityPermission
    }

    func setActivationHandler(_ handler: (@Sendable () -> Void)?) {
        activationHandler = handler
    }

    func openAccessibilitySettings() {}
    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {}
    func unregisterFixTextHotkey() {}

    func inspectFocusedElement() -> FocusedElementProbe {
        .available(FocusedElementSnapshot(role: "AXTextArea", subrole: nil, isSecure: false))
    }

    func inspectSelection() -> SelectionProbe {
        .unavailable(.noSelection)
    }

    func replaceSelection(with text: String) -> SelectionWriteResult {
        .unavailable(.unsupported)
    }
}

private final class FakeWorkspaceApplicationSource: WorkspaceApplicationSource, @unchecked Sendable {
    private var currentFrontmost: WorkspaceApplicationSnapshot?
    private var appsByPID: [pid_t: WorkspaceApplicationSnapshot]
    private var observers: [UUID: @Sendable (WorkspaceApplicationSnapshot) -> Void] = [:]
    private(set) var activatedProcessIdentifiers: [pid_t] = []

    init(frontmost: WorkspaceApplicationSnapshot?, running: [WorkspaceApplicationSnapshot]) {
        currentFrontmost = frontmost
        appsByPID = Dictionary(uniqueKeysWithValues: running.map { ($0.processIdentifier, $0) })
    }

    func setFrontmost(_ snapshot: WorkspaceApplicationSnapshot?) {
        currentFrontmost = snapshot
    }

    func simulateActivation(_ snapshot: WorkspaceApplicationSnapshot) {
        appsByPID[snapshot.processIdentifier] = snapshot
        currentFrontmost = snapshot
        for observer in observers.values {
            observer(snapshot)
        }
    }

    func terminate(processIdentifier: pid_t) {
        guard var app = appsByPID[processIdentifier] else { return }
        app = WorkspaceApplicationSnapshot(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName,
            isTerminated: true
        )
        appsByPID[processIdentifier] = app
        if currentFrontmost?.processIdentifier == processIdentifier {
            currentFrontmost = nil
        }
    }

    func frontmostApplication() -> WorkspaceApplicationSnapshot? {
        currentFrontmost
    }

    func runningApplication(processIdentifier: pid_t) -> WorkspaceApplicationSnapshot? {
        appsByPID[processIdentifier]
    }

    func runningApplications(bundleIdentifier: String) -> [WorkspaceApplicationSnapshot] {
        appsByPID.values.filter { $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated }
    }

    func installedApplicationDisplayName(bundleIdentifier: String) -> String? {
        appsByPID.values.first(where: { $0.bundleIdentifier == bundleIdentifier })?.localizedName
    }

    func activateApplication(processIdentifier: pid_t) -> Bool {
        guard let app = appsByPID[processIdentifier], !app.isTerminated else {
            return false
        }
        activatedProcessIdentifiers.append(processIdentifier)
        currentFrontmost = app
        return true
    }

    func observeActivations(_ handler: @escaping @Sendable (WorkspaceApplicationSnapshot) -> Void) -> AnyObject {
        let token = UUID()
        observers[token] = handler
        return token as NSUUID
    }

    func stopObserving(_ token: AnyObject) {
        if let uuid = token as? NSUUID {
            observers.removeValue(forKey: uuid as UUID)
        }
    }
}

private final class MenuBarEditorRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool
    var activeApplication: ApplicationIdentity?
    let layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper()
    let clipboardManager: ClipboardManaging = MockClipboardManager()

    private var isTargetFocused: Bool
    private(set) var text: String
    private var selectedRange: SelectionRangeSnapshot
    private let isSecure: Bool
    private(set) var preparedApplications: [ApplicationIdentity] = []
    private(set) var replaceCallCount = 0

    init(
        hasAccessibilityPermission: Bool,
        activeApplication: ApplicationIdentity?,
        initiallyFocused: Bool,
        text: String,
        selectedRange: SelectionRangeSnapshot,
        isSecure: Bool
    ) {
        self.hasAccessibilityPermission = hasAccessibilityPermission
        self.activeApplication = activeApplication
        self.isTargetFocused = initiallyFocused
        self.text = text
        self.selectedRange = selectedRange
        self.isSecure = isSecure
    }

    func openAccessibilitySettings() {}
    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {}
    func unregisterFixTextHotkey() {}

    @MainActor
    func prepareTargetApplicationForFixText(_ application: ApplicationIdentity) async -> Bool {
        preparedApplications.append(application)
        isTargetFocused = true
        return true
    }

    func inspectFocusedElement() -> FocusedElementProbe {
        guard hasAccessibilityPermission else {
            return .unavailable(.missingPermission)
        }
        guard isTargetFocused else {
            return .unavailable(.noFocusedElement)
        }
        return .available(
            FocusedElementSnapshot(
                role: isSecure ? "AXSecureTextField" : "AXTextArea",
                subrole: isSecure ? "AXSecureTextField" : nil,
                isSecure: isSecure
            )
        )
    }

    func inspectSelection() -> SelectionProbe {
        guard hasAccessibilityPermission else {
            return .unavailable(.missingPermission)
        }
        guard isTargetFocused else {
            return .unavailable(.noFocusedElement)
        }
        guard !isSecure else {
            return .unavailable(.secureField)
        }
        guard selectedRange.length > 0 else {
            return .unavailable(.noSelection)
        }
        let nsText = text as NSString
        let substring = nsText.substring(with: NSRange(location: selectedRange.location, length: selectedRange.length))
        return .available(SelectionSnapshot(text: substring, range: selectedRange))
    }

    func inspectTextContext() -> TextContextProbe {
        guard hasAccessibilityPermission else {
            return .unavailable(.missingPermission)
        }
        guard isTargetFocused else {
            return .unavailable(.noFocusedElement)
        }
        guard !isSecure else {
            return .unavailable(.secureField)
        }
        if selectedRange.length > 0 {
            let nsText = text as NSString
            let substring = nsText.substring(with: NSRange(location: selectedRange.location, length: selectedRange.length))
            return .available(SelectionSnapshot(text: substring, range: selectedRange))
        }
        return .available(SelectionSnapshot(text: text, range: selectedRange, isCaretContext: true))
    }

    func replaceSelection(with replacement: String) -> SelectionWriteResult {
        .unavailable(.unsupported)
    }

    func replaceText(
        in range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with replacement: String,
        in application: ApplicationIdentity
    ) -> SelectionWriteResult {
        replaceCallCount += 1
        guard hasAccessibilityPermission else {
            return .unavailable(.missingPermission)
        }
        guard isTargetFocused, activeApplication == application else {
            return .unavailable(.noFocusedElement)
        }
        guard !isSecure else {
            return .unavailable(.secureField)
        }
        let nsText = text as NSString
        let targetNSRange = NSRange(location: range.location, length: range.length)
        guard nsText.substring(with: targetNSRange) == expectedText else {
            return .unavailable(.unsupported)
        }
        text = nsText.replacingCharacters(in: targetNSRange, with: replacement)
        let newLength = (replacement as NSString).length
        selectedRange = SelectionRangeSnapshot(location: range.location + newLength, length: 0)
        return .success(SelectionRangeSnapshot(location: range.location, length: newLength))
    }

    @MainActor
    func waitForPreparation() async {
        for _ in 0..<20 where preparedApplications.isEmpty {
            await Task.yield()
        }
    }

    @MainActor
    func waitForFixTextCompletion() async {
        for _ in 0..<20 where replaceCallCount == 0 {
            await Task.yield()
        }
    }
}
