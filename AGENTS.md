# Henge

Resident macOS menu-bar utility for fixing text typed in the wrong keyboard layout (`ghbdtn` → `привет`).

## Stack

- Swift
- SwiftUI + AppKit
- macOS 13+
- ApplicationServices / Accessibility API
- ServiceManagement
- No third-party dependencies unless justified

## Core behavior

- Default hotkey: `⌥X`
- Selection has priority; otherwise fix the word around the caret.
- RU ↔ EN only.
- Detect direction from text, not current keyboard layout.
- Preserve case, digits, punctuation and `_`.
- Accessibility is the primary text path; clipboard is fallback only.
- Clipboard must be restored after fallback.

## Safety invariants

- Password/secure fields: **never read, copy, transform or replace content**.
- Excluded applications: complete no-op.
- Disabled state: app remains resident, hotkeys do nothing.
- Never log user text, passwords or clipboard contents.
- Fail safely when Accessibility or target applications are unsupported.

## Architecture

Keep Domain independent of AppKit/SwiftUI/ApplicationServices.

Main layers:

```text
UI → Application → Domain → Infrastructure
```

Prefer protocols around macOS-specific infrastructure.

## Configuration

- Local JSON configuration.
- Persist under `~/Library/Application Support/Henge/`.
- Apply settings immediately.
- Corrupt config → backup + defaults.
- Preserve working configuration when a new hotkey fails to register.

## Development

- MVP first. Do not add speculative features.
- Write unit tests for domain logic.
- Test Accessibility behavior against real macOS applications.
- Do not weaken password safety to improve compatibility.
- Before introducing a dependency, justify why native APIs are insufficient.

## Documentation

Project documentation is maintained in the repository:

- `README.md` — Project overview, installation, and usage
- `docs/architecture.md` — System architecture and safety invariants
- `CONTRIBUTING.md` — Contribution guidelines and development workflow
