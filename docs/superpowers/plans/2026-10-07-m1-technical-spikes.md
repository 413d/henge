# Milestone 1 — Technical Spikes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Milestone 1 native API spikes (HEN-010 through HEN-016) by implementing native keyboard layout mapping via `TIS`/`UCKeyTranslate`, full-fidelity clipboard preservation on `NSPasteboard`, integrating them into `AppRuntime`, creating an executable CLI probe harness for manual GUI validation, and documenting results in GBrain.

**Architecture:** 
- Domain defines `Layout` and `LayoutMapping` abstractions independent of macOS frameworks.
- Infrastructure provides `NativeKeyboardLayoutMapper` using Carbon `TIS`/`UCKeyTranslate` APIs to dynamically synthesize RU↔EN mappings from system keyboard layout data, with robust fallbacks.
- Infrastructure provides `AppKitClipboardManager` conforming to `ClipboardManaging` to capture and restore all `NSPasteboardItem` types.
- A CLI probe mode (`Henge --probe ...`) allows interactive verification of hotkey registration, AX focus/selection/secure-field detection, layout mapping, and clipboard preservation from a GUI session.

**Tech Stack:** Swift 6.0, macOS 13+, Carbon HIToolbox (`TIS*`, `UCKeyTranslate`), AppKit (`NSPasteboard`), ApplicationServices (Accessibility API), Swift Testing.

**Spec:** `~/brain/Projects/henge/dev-plan.md` (§4 M1 — Technical Spikes, §11 M1 Exit Criteria) and `~/brain/Projects/henge/architecture.md` (§10, §11, §21, §30).

---

## Global Constraints

- Domain logic must remain independent from AppKit/SwiftUI/Carbon/ApplicationServices (`architecture.md` §5).
- macOS 13+ Ventura compatibility (`DL-002`).
- No hardcoded dictionary as the sole source of keyboard layout mapping (`DL-010`, `dev-plan.md` HEN-011).
- Password and secure fields must be an absolute no-op: never read, copy, transform or replace (`DL-016`).
- Clipboard preservation must restore all representations across pasteboard types (`DL-015`, user decision).
- Verification must use `swift test` and `swift run` CLI only (no Xcode required).
- Documentation updates must be written to GBrain (`~/brain/Projects/henge`).

## Review Focus

1. **UCKeyTranslate dead keys and modifier states:** Ensure translation does not leave dead key state hanging and correctly maps shifted and unshifted keys.
2. **Headless TIS availability:** `TISCreateInputSourceList` must be queried with `includeAllInstalled: true` to find Russian layout data even if Russian is not active in the current system session.
3. **Clipboard empty/multi-item restoration:** Restoring when pasteboard was originally empty or had multiple items must not crash or leave pasteboard in an inconsistent state.
4. **Keypad vs ANSI key code ambiguity:** Keypad decimal vs ANSI period (`.`): ensure typing keys (ANSI 0..50) take precedence so `.` maps to `ю` and not keypad `.`.
5. **Fail-safe fallback:** If system layout data cannot be extracted (e.g. sandbox or restricted environment), `NativeKeyboardLayoutMapper` must fall back gracefully to a bundled default ANSI mapping rather than failing.

---

### Task 1: Domain Layout Model and Native Keyboard Layout Mapper (HEN-011)

**Files:**
- Create: `Sources/Domain/Layout/Layout.swift`
- Create: `Sources/Domain/Layout/LayoutMapping.swift`
- Create: `Sources/Infrastructure/Layout/NativeKeyboardLayoutMapper.swift`
- Create: `Tests/HengeTests/NativeKeyboardLayoutMapperTests.swift`

**Interfaces:**
- Consumes: Carbon `TIS*`, `UCKeyTranslate`, `UCKeyboardLayout`
- Produces:
  ```swift
  public enum Layout: String, CaseIterable, Codable, Sendable {
      case english
      case russian
  }

  public protocol LayoutMapping: Sendable {
      func map(_ character: Character, from source: Layout, to target: Layout) -> Character?
      func map(text: String, from source: Layout, to target: Layout) -> String
  }
  ```

- [ ] **Step 1: Write failing tests for Layout and NativeKeyboardLayoutMapper**

```swift
// Tests/HengeTests/NativeKeyboardLayoutMapperTests.swift
import Testing
@testable import Henge

struct NativeKeyboardLayoutMapperTests {
    @Test
    func mapsBasicEnglishToRussianAlphabet() {
        let mapper = NativeKeyboardLayoutMapper()
        #expect(mapper.map("q", from: .english, to: .russian) == "й")
        #expect(mapper.map("w", from: .english, to: .russian) == "ц")
        #expect(mapper.map("e", from: .english, to: .russian) == "у")
        #expect(mapper.map("r", from: .english, to: .russian) == "к")
    }

    @Test
    func mapsBasicRussianToEnglishAlphabet() {
        let mapper = NativeKeyboardLayoutMapper()
        #expect(mapper.map("й", from: .russian, to: .english) == "q")
        #expect(mapper.map("ц", from: .russian, to: .english) == "w")
        #expect(mapper.map("у", from: .russian, to: .english) == "e")
    }

    @Test
    func mapsUppercasePreservingCase() {
        let mapper = NativeKeyboardLayoutMapper()
        #expect(mapper.map("Q", from: .english, to: .russian) == "Й")
        #expect(mapper.map("W", from: .english, to: .russian) == "Ц")
        #expect(mapper.map("Й", from: .russian, to: .english) == "Q")
    }

    @Test
    func mapsPunctuationAndBrackets() {
        let mapper = NativeKeyboardLayoutMapper()
        #expect(mapper.map("[", from: .english, to: .russian) == "х")
        #expect(mapper.map("]", from: .english, to: .russian) == "ъ")
        #expect(mapper.map(";", from: .english, to: .russian) == "ж")
        #expect(mapper.map("'", from: .english, to: .russian) == "э")
        #expect(mapper.map(",", from: .english, to: .russian) == "б")
        #expect(mapper.map(".", from: .english, to: .russian) == "ю")
    }

    @Test
    func mapsFullStrings() {
        let mapper = NativeKeyboardLayoutMapper()
        #expect(mapper.map(text: "ghbdtn", from: .english, to: .russian) == "привет")
        #expect(mapper.map(text: "ghbdtn, vbh!", from: .english, to: .russian) == "привет, мир!")
        #expect(mapper.map(text: "ghbdtn_123", from: .english, to: .russian) == "привет_123")
        #expect(mapper.map(text: "привет", from: .russian, to: .english) == "ghbdtn")
    }

    @Test
    func preservesUnmappedCharacters() {
        let mapper = NativeKeyboardLayoutMapper()
        #expect(mapper.map("1", from: .english, to: .russian) == "1")
        #expect(mapper.map(" ", from: .english, to: .russian) == " ")
        #expect(mapper.map("🎉", from: .english, to: .russian) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NativeKeyboardLayoutMapperTests`
Expected: FAIL (types not defined)

- [ ] **Step 3: Implement `Layout`, `LayoutMapping`, and `NativeKeyboardLayoutMapper`**

Implement:
1. `Sources/Domain/Layout/Layout.swift`: `enum Layout: String, CaseIterable, Codable, Sendable`.
2. `Sources/Domain/Layout/LayoutMapping.swift`: `protocol LayoutMapping: Sendable` with `map(_:from:to:)` and `map(text:from:to:)`.
3. `Sources/Infrastructure/Layout/NativeKeyboardLayoutMapper.swift`:
   - Queries `TISCreateInputSourceList` for `com.apple.keylayout.US` and `com.apple.keylayout.Russian` (or `com.apple.keylayout.RussianWin`).
   - Uses `UCKeyTranslate` over ANSI keycodes (0..52) with unshifted (0) and shifted (`shiftKey >> 8`) modifier states to build bidirectional character tables.
   - Includes bundled ANSI standard fallback table if system layout tables cannot be accessed.
   - Implements `map(_:from:to:)` using the built tables.
   - Implements `map(text:from:to:)` replacing mapped characters and leaving others untouched.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NativeKeyboardLayoutMapperTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Domain/Layout Sources/Infrastructure/Layout Tests/HengeTests/NativeKeyboardLayoutMapperTests.swift
git commit -m "feat(m1): implement native keyboard layout mapping via TIS and UCKeyTranslate (HEN-011)"
```

---

### Task 2: Clipboard Preservation Model and Manager (HEN-016)

**Files:**
- Create: `Sources/Infrastructure/Clipboard/ClipboardSnapshot.swift`
- Create: `Sources/Infrastructure/Clipboard/ClipboardManaging.swift`
- Create: `Sources/Infrastructure/Clipboard/AppKitClipboardManager.swift`
- Create: `Tests/HengeTests/ClipboardManagerTests.swift`

**Interfaces:**
- Consumes: `AppKit.NSPasteboard`, `NSPasteboardItem`
- Produces:
  ```swift
  public struct PasteboardItemSnapshot: Equatable, Sendable {
      public let representations: [String: Data]
  }

  public struct ClipboardSnapshot: Equatable, Sendable {
      public let changeCount: Int
      public let items: [PasteboardItemSnapshot]
  }

  public protocol ClipboardManaging: AnyObject, Sendable {
      func snapshot() -> ClipboardSnapshot
      func restore(_ snapshot: ClipboardSnapshot) -> Bool
  }
  ```

- [ ] **Step 1: Write failing tests for ClipboardManaging and mock double**

```swift
// Tests/HengeTests/ClipboardManagerTests.swift
import Testing
import Foundation
@testable import Henge

struct ClipboardManagerTests {
    @Test
    func mockClipboardCapturesAndRestoresItems() {
        let manager = MockClipboardManager()
        
        // Initial snapshot is empty
        let initial = manager.snapshot()
        #expect(initial.items.isEmpty)
        
        // Add item
        manager.setMockItem(["public.utf8-plain-text": "hello".data(using: .utf8)!])
        let captured = manager.snapshot()
        #expect(captured.items.count == 1)
        #expect(captured.items[0].representations["public.utf8-plain-text"] == "hello".data(using: .utf8)!)
        
        // Clobber
        manager.setMockItem(["public.utf8-plain-text": "replacement".data(using: .utf8)!])
        #expect(manager.snapshot().items[0].representations["public.utf8-plain-text"] == "replacement".data(using: .utf8)!)
        
        // Restore
        let restored = manager.restore(captured)
        #expect(restored == true)
        #expect(manager.snapshot().items[0].representations["public.utf8-plain-text"] == "hello".data(using: .utf8)!)
    }

    @Test
    func mockClipboardRestoresEmptyState() {
        let manager = MockClipboardManager()
        let emptySnapshot = manager.snapshot()
        
        manager.setMockItem(["public.utf8-plain-text": "temp".data(using: .utf8)!])
        #expect(!manager.snapshot().items.isEmpty)
        
        let restored = manager.restore(emptySnapshot)
        #expect(restored == true)
        #expect(manager.snapshot().items.isEmpty)
    }

    @Test
    func snapshotPreservesMultipleTypesPerItem() {
        let manager = MockClipboardManager()
        let types: [String: Data] = [
            "public.utf8-plain-text": "styled".data(using: .utf8)!,
            "public.html": "<b>styled</b>".data(using: .utf8)!,
            "com.apple.flat-rtfd": Data([0x01, 0x02, 0x03])
        ]
        manager.setMockItem(types)
        let snap = manager.snapshot()
        
        #expect(snap.items[0].representations.count == 3)
        #expect(snap.items[0].representations["public.html"] == "<b>styled</b>".data(using: .utf8)!)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipboardManagerTests`
Expected: FAIL (types not defined)

- [ ] **Step 3: Implement ClipboardSnapshot, ClipboardManaging, AppKitClipboardManager, and MockClipboardManager**

Implement:
1. `Sources/Infrastructure/Clipboard/ClipboardSnapshot.swift`: `PasteboardItemSnapshot` and `ClipboardSnapshot`.
2. `Sources/Infrastructure/Clipboard/ClipboardManaging.swift`: `protocol ClipboardManaging`.
3. `Sources/Infrastructure/Clipboard/AppKitClipboardManager.swift`:
   - Accepts `NSPasteboard` (defaults to `.general`).
   - `snapshot()` reads `pasteboardItems` and extracts all representations as `Data` per `PasteboardType`.
   - `restore(_:)` clears pasteboard contents and reconstructs `NSPasteboardItem` instances with original `setData(_:forType:)`.
4. In `Tests/HengeTests/ClipboardManagerTests.swift`: add `MockClipboardManager` conforming to `ClipboardManaging` for deterministic headless verification.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClipboardManagerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Infrastructure/Clipboard Tests/HengeTests/ClipboardManagerTests.swift
git commit -m "feat(m1): implement clipboard snapshot and preservation manager (HEN-016)"
```

---

### Task 3: Runtime Integration & Application Environment Update

**Files:**
- Modify: `Sources/Infrastructure/AppRuntime.swift`
- Modify: `Sources/App/AppEnvironment.swift`
- Modify: `Tests/HengeTests/HengeCoordinatorTests.swift`

**Interfaces:**
- Consumes: `LayoutMapping`, `ClipboardManaging`
- Produces:
  ```swift
  protocol AppRuntime {
      ...
      var layoutMapper: LayoutMapping { get }
      var clipboardManager: ClipboardManaging { get }
  }
  ```

- [ ] **Step 1: Write failing tests or updates in `HengeCoordinatorTests`**

Update `StubRuntime` in `Tests/HengeTests/HengeCoordinatorTests.swift` to satisfy the updated `AppRuntime` protocol requirements and verify runtime integration.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HengeCoordinatorTests`
Expected: FAIL (protocol requirements missing)

- [ ] **Step 3: Update `AppRuntime.swift` and `AppEnvironment.swift`**

- In `Sources/Infrastructure/AppRuntime.swift`:
  - Add `var layoutMapper: LayoutMapping { get }` and `var clipboardManager: ClipboardManaging { get }` to `AppRuntime`.
  - In `LiveAppRuntime`: provide `lazy var layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper()` and `lazy var clipboardManager: ClipboardManaging = AppKitClipboardManager()`.
- In `Tests/HengeTests/HengeCoordinatorTests.swift`:
  - Add stub implementations in `StubRuntime`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Infrastructure/AppRuntime.swift Sources/App/AppEnvironment.swift Tests/HengeTests/HengeCoordinatorTests.swift
git commit -m "feat(m1): integrate layout mapper and clipboard manager into AppRuntime"
```

---

### Task 4: CLI Probe Harness for Interactive Native Spikes Validation

**Files:**
- Create: `Sources/Infrastructure/Probes/HengeProbeRunner.swift`
- Modify: `Sources/App/HengeApp.swift`
- Create: `Tests/HengeTests/HengeProbeRunnerTests.swift`

**Interfaces:**
- CLI invocation:
  - `swift run Henge --probe layout`
  - `swift run Henge --probe clipboard`
  - `swift run Henge --probe ax`
  - `swift run Henge --probe hotkey`
  - `swift run Henge --probe all`
  - `swift run Henge --probe help`

- [ ] **Step 1: Write test for ProbeRunner argument parsing and dispatch**

```swift
// Tests/HengeTests/HengeProbeRunnerTests.swift
import Testing
@testable import Henge

struct HengeProbeRunnerTests {
    @Test
    func parsesProbeCommandsCorrectly() {
        #expect(HengeProbeRunner.ProbeCommand(argument: "layout") == .layout)
        #expect(HengeProbeRunner.ProbeCommand(argument: "clipboard") == .clipboard)
        #expect(HengeProbeRunner.ProbeCommand(argument: "ax") == .ax)
        #expect(HengeProbeRunner.ProbeCommand(argument: "hotkey") == .hotkey)
        #expect(HengeProbeRunner.ProbeCommand(argument: "all") == .all)
        #expect(HengeProbeRunner.ProbeCommand(argument: "unknown") == .help)
    }

    @Test
    func layoutProbeRunsSuccessfully() {
        let output = HengeProbeRunner.runLayoutProbe(mapper: NativeKeyboardLayoutMapper())
        #expect(output.contains("ghbdtn -> привет"))
        #expect(output.contains("привет -> ghbdtn"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HengeProbeRunnerTests`
Expected: FAIL (types not defined)

- [ ] **Step 3: Implement `HengeProbeRunner` and update `HengeApp.swift`**

1. Create `Sources/Infrastructure/Probes/HengeProbeRunner.swift`:
   - `enum ProbeCommand` parsing arguments.
   - `run(arguments: [String]) -> Int32`:
     - `layout`: tests `NativeKeyboardLayoutMapper` across sample strings, uppercase, punctuation, and prints detailed report.
     - `clipboard`: snapshots pasteboard, displays item types, writes marker text, verifies snapshot restore, reports change count.
     - `ax`: inspects `AXIsProcessTrusted()`, frontmost application, focused element role/subrole, selection range and length, and whether secure field was detected.
     - `hotkey`: registers `⌥X` via Carbon, prints instructions to press `⌥X` within 10 seconds, logs event on trigger, then cleanly unregisters and exits.
     - `all`: runs layout, clipboard, and ax probes sequentially.
2. In `Sources/App/HengeApp.swift`:
   - Replace `@main struct HengeApp: App` with:
     ```swift
     @main
     enum HengeMain {
         static func main() {
             if CommandLine.arguments.contains("--probe") {
                 let probeArgs = Array(CommandLine.arguments.drop(while: { $0 != "--probe" }).dropFirst())
                 exit(HengeProbeRunner.run(arguments: probeArgs))
             } else {
                 HengeApp.main()
             }
         }
     }

     struct HengeApp: App { ... }
     ```

- [ ] **Step 4: Verify with `swift test` and `swift run Henge --probe layout`**

Run:
```bash
swift test
swift run Henge --probe layout
swift run Henge --probe help
```
Expected: All tests pass, and `--probe layout` prints successful RU↔EN translations.

- [ ] **Step 5: Commit**

```bash
git add Sources/Infrastructure/Probes Sources/App/HengeApp.swift Tests/HengeTests/HengeProbeRunnerTests.swift
git commit -m "feat(m1): add CLI probe runner for interactive native spikes validation"
```

---

### Task 5: GBrain Documentation and Decision Log Updates

**Files:**
- Modify: `~/brain/Projects/henge/decision-log.md`
- Modify: `~/brain/Projects/henge/dev-plan.md`
- Modify: `~/brain/Projects/henge/engineering-backlog.md`
- Modify: `README.md`

- [ ] **Step 1: Document DL-032 and DL-033 in `decision-log.md`**

Add:
- `DL-032 — Native keyboard layout mapping via TIS and UCKeyTranslate`:
  - Rationale, alternatives (hardcoded tables), consequences, layout selection behavior.
- `DL-033 — Full-fidelity NSPasteboard snapshot and restoration`:
  - Rationale, multi-type preservation, consequences for clipboard fallback safety.

- [ ] **Step 2: Update `dev-plan.md` (§4 M1 Spikes and §11 Exit Criteria)**

- Update HEN-010 through HEN-016 with implementation status, findings, and live CLI probe instructions.
- Provide explicit instructions for running `swift run Henge --probe ...` in GUI sessions with Accessibility permissions.

- [ ] **Step 3: Update `engineering-backlog.md`**

- Update tickets HEN-010, HEN-011, HEN-012, HEN-013, HEN-014, HEN-015, HEN-016 status and deliverables.

- [ ] **Step 4: Update `README.md` in repository**

- Update Current Status section: mark M1 spikes complete in codebase with instructions for `--probe`.

- [ ] **Step 5: Commit repository changes**

```bash
git add README.md
git commit -m "docs(m1): update status and probe runner documentation for Milestone 1"
```

---

### Task 6: Final Verification & Branch Integration

**Files:**
- Repository root

- [ ] **Step 1: Run full test suite via Swift CLI**

Run: `swift test`
Expected: 100% tests passing, 0 warnings/failures.

- [ ] **Step 2: Run CLI probes**

Run: `swift run Henge --probe layout`
Expected: Clean exit code 0 and valid mapping output.

- [ ] **Step 3: Verify git status is clean on main**

Run: `git status`
Expected: Clean working tree on branch `main`.
