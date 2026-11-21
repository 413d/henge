# Russian README (`README.ru.md`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a comprehensive, accurate Russian translation of `README.md` as `README.ru.md` and link both documents together.

**Architecture:** Maintain documentation parity with two root markdown files (`README.md` and `README.ru.md`). Both files reference each other in their top navigation header. Commands, paths, technical terms, and badge assets remain synchronized.

**Tech Stack:** Markdown (GitHub Flavored Markdown).

**Spec:** `docs/superpowers/specs/2026-11-21-russian-readme-design.md`

## Global Constraints

- Shell commands, paths, flags, and source code must remain untranslated and directly copy-pasteable.
- Relative links within the repository (e.g. `LICENSE`, `docs/architecture.md`, `README.md`) must resolve correctly.
- Section anchors in internal links (such as `#установка`, `#как-пользоваться` etc.) must correctly match the Russian headings.
- Language switcher link must be prominent in the header navigation of both files.

## Review Focus

1. Anchor links in `README.ru.md` table of contents and in-text links pointing to section headings must match GitHub's anchor slugification of Russian headers.
2. CLI commands, keyboard shortcuts (`⌥X`, `Option + X`), and environment variables (`HENGE_SIGNING_IDENTITY`) must match `README.md` exactly.
3. macOS UI terminology in Russian must follow Apple macOS conventions (e.g., «Системные настройки» → «Конфиденциальность и безопасность» → «Универсальный доступ»).
4. Gatekeeper quarantine instructions and explanations must remain technically exact.
5. Bidirectional language switcher links between `README.md` and `README.ru.md` must resolve cleanly.

---

### Task 1: Add language switcher link to English `README.md`

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: `README.ru.md` (relative link target)
- Produces: Language selector line in `README.md`

- [ ] **Step 1: Check existing header in `README.md`**

Verify the center block ending with `[Website](https://413d.github.io/henge/) ...`.

- [ ] **Step 2: Add language switcher to `README.md`**

In `README.md`, add the language switcher line right above the navigation links:
```markdown
**English** · [Русский](README.ru.md)
```

- [ ] **Step 3: Verify markdown formatting**

Run: `git diff README.md`
Verify the diff is clean and preserves existing formatting.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add Russian README language switcher to README.md"
```

---

### Task 2: Create `README.ru.md` with complete Russian translation

**Files:**
- Create: `README.ru.md`

**Interfaces:**
- Consumes: Content and structure of `README.md`
- Produces: Complete Russian documentation file `README.ru.md`

- [ ] **Step 1: Draft `README.ru.md` with complete translation**

Translate all sections maintaining exact structural parity:
- Header: logo, badges, download link, language switcher (`[English](README.md) · **Русский**`), navigation links with anchors.
- «Зачем нужен Henge» (Why Henge)
- «Возможности» (What It Does - table)
- «Установка» (Installation - macOS 13+, universal zip, gatekeeper quarantine, accessibility permissions)
- «Почему требуется xattr -dr com.apple.quarantine» (Explanation of ad-hoc signature on macOS Sequoia)
- «Проверка скачанного файла» (Verifying download with SHA256SUMS.txt)
- «Как пользоваться» (How to Use - shortcuts, menu bar items)
- «Приватность и безопасность» (Privacy & Safety - offline, secure fields, AX first, clipboard restore)
- «Честные ограничения» (Honest Limitations - RU ↔ EN only, no background daemons, ad-hoc AX reset on update)
- «Обновление и удаление» (Updating & Uninstalling)
- «Сборка из исходников» (Build from Source - commands and flags)
- «Лицензия» (License - link to LICENSE)

- [ ] **Step 2: Check anchors and cross-references in `README.ru.md`**

Verify table of contents and internal anchor links match:
- `#установка` for `## Установка`
- `#как-пользоваться` for `## Как пользоваться`
- `#приватность-и-безопасность` for `## Приватность и безопасность`
- `#честные-ограничения` for `## Честные ограничения`
- `#проверка-скачанного-файла` for `### Проверка скачанного файла`
- `#сборка-из-исходников` for `## Сборка из исходников`

- [ ] **Step 3: Verify file creation and contents**

Verify that `README.ru.md` exists and contains no missing sections.

- [ ] **Step 4: Commit**

```bash
git add README.ru.md
git commit -m "docs: add Russian translation in README.ru.md"
```

---

### Task 3: Verification of cross-links, formatting, and repository status

**Files:**
- Read: `README.md`, `README.ru.md`

**Interfaces:**
- Consumes: Both files created/modified in Tasks 1 & 2
- Produces: Verified documentation files

- [ ] **Step 1: Check link resolution and syntax**

Verify that `README.md` links to `README.ru.md` and `README.ru.md` links to `README.md`.
Verify relative links to `LICENSE` work from both files.

- [ ] **Step 2: Run test suite to ensure no collateral impact**

Run: `swift test`
Expected: PASS (all tests pass)

- [ ] **Step 3: Check git status**

Run: `git status`
Expected: Clean working tree on branch main (or pending clean commits)
