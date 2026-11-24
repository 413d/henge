import AppKit
import SwiftUI

@MainActor
private final class OnboardingWindowState: ObservableObject {
    @Published var isVisible = false
}

private struct OnboardingPollKey: Equatable {
    let isVisible: Bool
    let accessibilityGranted: Bool
}

struct OnboardingView: View {
    @EnvironmentObject private var coordinator: HengeCoordinator
    @ObservedObject private var windowState: OnboardingWindowState

    init() {
        self.windowState = OnboardingWindowState()
    }

    fileprivate init(windowState: OnboardingWindowState) {
        self.windowState = windowState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection

            VStack(alignment: .leading, spacing: 12) {
                featureRow(
                    symbolName: "keyboard",
                    text: L10n.format(
                        "onboarding.feature.shortcut",
                        defaultValue: "Press %@ to convert the selection or word at the cursor (for example, ghbdtn → привет).",
                        coordinator.shortcutDescription
                    )
                )

                featureRow(
                    symbolName: "lock.shield",
                    text: L10n.string(
                        "onboarding.feature.privacy",
                        defaultValue: "Runs 100% offline. Henge never logs your text, passwords, or clipboard contents."
                    )
                )
            }

            accessibilitySection

            actionRow
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            coordinator.refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard windowState.isVisible else { return }
            coordinator.refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard windowState.isVisible else { return }
            coordinator.refreshPermissions()
        }
        .task(id: OnboardingPollKey(isVisible: windowState.isVisible, accessibilityGranted: coordinator.state.accessibilityGranted)) {
            guard windowState.isVisible, !coordinator.state.accessibilityGranted else {
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled else { break }
                coordinator.refreshPermissions()
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(
                    L10n.string(
                        "onboarding.title",
                        defaultValue: "Welcome to Henge"
                    )
                )
                .font(.title2.weight(.semibold))

                Text(
                    L10n.string(
                        "onboarding.subtitle",
                        defaultValue: "Fix text typed in the wrong RU ↔ EN keyboard layout with a single shortcut."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func featureRow(symbolName: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, alignment: .center)

            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                L10n.string(
                    "onboarding.permissions.title",
                    defaultValue: "Accessibility Access"
                )
            )
            .font(.headline)

            Text(
                L10n.string(
                    "onboarding.permissions.description",
                    defaultValue: "macOS requires Accessibility permission so Henge can read and replace mistyped text in other apps."
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(
                    systemName: coordinator.state.accessibilityGranted
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(coordinator.state.accessibilityGranted ? .green : .orange)

                Text(
                    coordinator.state.accessibilityGranted
                        ? L10n.string(
                            "onboarding.permissions.granted",
                            defaultValue: "Accessibility access is granted."
                        )
                        : L10n.string(
                            "onboarding.permissions.pending",
                            defaultValue: "Accessibility access is not granted yet."
                        )
                )
                .font(.callout.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(
                L10n.string(
                    "onboarding.action.grant_accessibility",
                    defaultValue: "Grant Accessibility Access"
                )
            ) {
                coordinator.requestAccessibilityPermission()
            }
            .disabled(coordinator.state.accessibilityGranted)
            .buttonStyle(.borderedProminent)

            Spacer()

            if coordinator.state.accessibilityGranted {
                Button(
                    L10n.string(
                        "onboarding.action.get_started",
                        defaultValue: "Get Started"
                    )
                ) {
                    coordinator.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(
                    L10n.string(
                        "onboarding.action.continue",
                        defaultValue: "Continue"
                    )
                ) {
                    coordinator.completeOnboarding()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

@MainActor
final class OnboardingWindowController {
    private let windowState = OnboardingWindowState()
    private let windowController: SingletonWindowController<OnboardingView>

    init(
        coordinator: HengeCoordinator? = nil,
        activateApplication: (@MainActor () -> Void)? = nil,
        presentWindow: (@MainActor (NSWindow) -> Void)? = nil
    ) {
        let windowState = windowState
        windowController = SingletonWindowController(
            coordinator: coordinator,
            title: L10n.string(
                "onboarding.window.title",
                defaultValue: "Welcome to Henge"
            ),
            styleMask: [.titled, .closable],
            activateApplication: activateApplication,
            presentWindow: presentWindow,
            onShow: {
                windowState.isVisible = true
            },
            onWillClose: { coordinator in
                windowState.isVisible = false
                coordinator?.completeOnboarding()
            },
            makeContent: {
                OnboardingView(windowState: windowState)
            }
        )
    }

    func bind(coordinator: HengeCoordinator) {
        windowController.bind(coordinator: coordinator)
    }

    @discardableResult
    func showWindow() -> NSWindow? {
        windowController.showWindow()
    }

    func closeWindow() {
        windowState.isVisible = false
        windowController.closeWindow()
    }
}
