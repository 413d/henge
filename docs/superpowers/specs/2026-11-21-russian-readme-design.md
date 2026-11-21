# Russian README (`README.ru.md`) Design Document

## Intent and the Why
Henge is a macOS utility specifically designed to correct text accidentally typed in the wrong keyboard layout between Russian and English (`ghbdtn` ↔ `привет`).
Providing a high-quality, comprehensive Russian translation of the project documentation (`README.ru.md`) makes the project directly accessible and convenient for native Russian-speaking users and contributors.

## Goals
- Provide a complete, idiomatic Russian translation of `README.md` in `README.ru.md`.
- Keep parity in structure, headings, links, shields/badges, shell commands, and tables with the English `README.md`.
- Add clear cross-links between `README.md` and `README.ru.md` at the top of each file.
- Accurately translate macOS terminology (e.g., Gatekeeper, Accessibility, System Settings, Menu Bar, Dock).

## Non-Goals & Anti-Goals
- Translating code identifiers, CLI flags, file paths, repository URLs, or license text.
- Translating internal documentation (e.g., `CONTRIBUTING.md`, `docs/architecture.md`) at this time.
- Altering the structure or technical content of the English `README.md` beyond adding the language switcher.

## Constraints
- Shell commands and paths must remain exact and executable without translation (`xattr -dr com.apple.quarantine ~/Applications/Henge.app`, `shasum -a 256 -c SHA256SUMS.txt`, `swift test`, etc.).
- Markdown formatting and layout should render identically on GitHub.

## Approaches Considered
1. **Dedicated file `README.ru.md` with header links (Chosen)**:
   - Industry standard on GitHub for multilingual documentation.
   - Preserves default GitHub presentation of English `README.md` while making Russian easily discoverable via header switcher.
   - Clean separation of concerns; easy to update independently when content changes.
2. **Single bilingual `README.md` (Rejected)**:
   - Doubling the length in a single file clutters the page and harms readability for both audiences.
3. **`README_RU.md` or subfolder `docs/ru/README.md` (Rejected)**:
   - `README.ru.md` is more standard and natively recognized by many tools and GitHub renderers.

## Decisions Made
- File path: `README.ru.md` at repository root.
- Cross-link in `README.md`: `English · [Русский](README.ru.md)` placed in the header navigation.
- Cross-link in `README.ru.md`: `[English](README.md) · Русский` placed in the header navigation.
