import Carbon
import Foundation

enum HotkeyRegistrationError: Error {
    case unsupportedShortcut(String)
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
}

extension HotkeyRegistrationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .unsupportedShortcut(key):
            return L10n.format(
                "hotkey.error.unsupported_shortcut",
                defaultValue: "The shortcut key %@ is not supported by the current global hotkey backend.",
                key
            )
        case let .eventHandlerInstallationFailed(status):
            return L10n.format(
                "hotkey.error.event_handler_failed",
                defaultValue: "Henge could not install the global hotkey event handler (OSStatus %d).",
                status
            )
        case let .registrationFailed(status):
            return L10n.format(
                "hotkey.error.registration_failed",
                defaultValue: "Henge could not register the global hotkey (OSStatus %d).",
                status
            )
        }
    }
}

final class HotkeyRegistrar {
    private let hotkeyID = EventHotKeyID(signature: 0x484E4745, id: 1)

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var currentShortcut: Shortcut?
    private var handler: (() -> Void)?

    deinit {
        unregister()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(shortcut: Shortcut, handler: @escaping () -> Void) throws {
        try installEventHandlerIfNeeded()

        let hotkey = try CarbonHotkey(shortcut: shortcut)

        if hotKey != nil, currentShortcut == shortcut {
            self.handler = handler
            return
        }

        var newHotKey: EventHotKeyRef?

        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKey
        )

        guard status == noErr else {
            throw HotkeyRegistrationError.registrationFailed(status)
        }

        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = newHotKey
        currentShortcut = shortcut
        self.handler = handler
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }

        currentShortcut = nil
        handler = nil
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                let center = Unmanaged<HotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
                return center.handleHotKeyEvent(event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            throw HotkeyRegistrationError.eventHandlerInstallationFailed(status)
        }
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var registeredHotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &registeredHotkeyID
        )

        guard status == noErr else {
            return status
        }

        guard registeredHotkeyID.signature == hotkeyID.signature, registeredHotkeyID.id == hotkeyID.id else {
            return noErr
        }

        handler?()

        return noErr
    }
}
