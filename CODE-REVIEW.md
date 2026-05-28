# DDEVUI Code Review — 2026-05-28

Full code-base review of `Sources/DDEVUIApp/` (29 Swift files, 6021 LOC). Performed by 4 parallel focused reviewers (security, bugs/correctness, code quality, performance/concurrency). This document is the synthesis. The raw per-reviewer reports live in `/tmp/ddevui-review/`.

## Headline assessment

**Security posture: solid.** No command injection (all `Process` calls use array `arguments:`, no shell). No string-concatenated commands. UserDefaults stores only enum raw-values, no secrets. JSON deserialisation strongly typed. Editor / DB-tool bundle IDs come from a closed enum.

**One critical correctness bug, two high-impact UX bugs.** All three live in `Services/CommandRunning.swift` and surface every time the user runs a DDEV command.

**Code quality is good for a learning project**, with one large refactor opportunity (god-object ViewModel) that's structural, not urgent.

---

## Severity counts (combined, deduped)

| Severity | Count |
|----------|-------|
| CRITICAL | 1 |
| HIGH     | 6 |
| MEDIUM   | 14 |
| LOW      | 14 |
| INFO     | 8 |

The CRITICAL and three of the HIGHs are the same root cause: how `ProcessCommandRunner` runs subprocesses.

---

## CRITICAL — Pipe-deadlock + main-thread block in subprocess runner

**File:** `Sources/DDEVUIApp/Services/CommandRunning.swift:26-63`

`ProcessCommandRunner.run` is declared `async` but performs no `await`. It calls `process.run()`, `process.waitUntilExit()`, and only afterwards reads the stdout/stderr pipes to EOF. Two compounding bugs:

1. **Pipe deadlock on >~64 KiB output.** Darwin pipe kernel buffers are 16-64 KiB. Any `ddev` command that emits more (logs, `utility diagnose`, large `import-db`, `add-on get`) fills the pipe → child blocks on `write(2)` → `waitUntilExit` waits forever. Hard hang.
2. **Main-thread block on every command.** With no `await` and no detached task, the implementation runs inline on the caller's actor. All callers chain through `@MainActor ProjectDashboardViewModel`, so the whole UI freezes for the duration of every `ddev` command (commonly 10-60s for `start`).

**Fix applied.** Wrap the body in `withCheckedThrowingContinuation` dispatched to `DispatchQueue.global(qos: .userInitiated)`. Drain stdout and stderr pipes concurrently on separate dispatch queues using a DispatchGroup, *before* `waitUntilExit`.

---

## HIGH

### H1. Serial `ddev describe` during refresh
**File:** `ViewModels/ProjectDashboardViewModel.swift:793-806`. Refresh awaits N `ddev describe` calls in a `for-in` loop, multiplying the freeze from CRITICAL by project count. **Fix applied** — `TaskGroup` with order-preserving collection.

### H2. `removeAddOn` UI passes slashed repository; DDEV expects short name
**File:** `Views/AddonManagerView.swift:111` passes `addon.repository` ("ddev/ddev-redis"). Older `ddev add-on remove` rejects the slashed form. **Fix applied** — pass `addon.installName` (the last path component).

### H3. ProjectInspector mounts five heavy sub-views unconditionally
**File:** `Views/ProjectInspectorView.swift:16-32`. Every project switch fires three concurrent `ddev` subprocesses (addons + snapshots + logs). Combined with the runner being main-blocking, switching a project freezes the UI for seconds. **Not applied** — UX decision (tab vs. expand-on-tap). Recommended.

### H4. `ProjectDashboardViewModel` is a god object (814 LOC, 30 `@Published` properties)
**File:** `ViewModels/ProjectDashboardViewModel.swift`. Owns every domain on the screen. Any state change re-renders every observer. **Not applied** — structural refactor, requires architectural decisions. Recommended as the highest-leverage next refactor.

### H5. `DDEVServicing` is a 39-method protocol
Same root issue as H4 at the service layer. **Not applied** — pairs with H4.

### H6. `nilIfBlank` duplicated as `private extension String` in five files
Five identical copies. **Fix applied** — consolidated into `Sources/DDEVUIApp/Utilities/String+Blank.swift` and dropped from all callers.

---

## MEDIUM (highlights)

| # | File | Issue | Status |
|---|------|-------|--------|
| M1 | `Models/DDEVAddon.swift:90` | Fallback table parser drops any repo whose name contains substring `"add-on"` (e.g. `acme/awesome-add-on`). | **Fixed** — removed the redundant substring guard; the `contains("/")` check already excludes headers. |
| M2 | `ViewModels/ProjectDashboardViewModel.swift:705-709` | `runDiagnostics` hard-codes `.projectDiagnose` as the failing check, mis-labelling failures from global / mutagen runs. | **Fixed** — failure now captured per-check inside `diagnosticEntry`. |
| M3 | `ViewModels/ProjectDashboardViewModel.swift:437-445` | `loadConfigForSelectedProject` swallows `CommandRunnerError.nonZeroExit` payload, showing `String(describing:)` in the editor's error panel. | **Fixed** — explicit branch extracts stderr, mirroring `loadLogsForSelectedProject`. |
| M4 | `Models/DDEVConfig.swift:372-375` | `droppingYAMLComment` treats `#` inside quoted strings as a comment start. | **Fixed** — tracks quote state while scanning. |
| M5 | `Services/CommandRunning.swift` + service call sites | Argument injection — values like `--help` passed positionally to `ddev` become flags. | **Fixed** — service-layer validation rejects user-controlled positional args starting with `-`. (No `--` separator added; requires per-version `ddev` testing to confirm support.) |
| M6 | `ViewModels/ProjectDashboardViewModel.swift:105,727` | `commandHistory` grows unbounded with full stdout/stderr per entry. | **Fixed** — capped at 50 entries, per-entry stdout/stderr truncated beyond 32 KiB in the stored history copy. |
| M7 | `Services/ProjectCacheStore.swift:35-36` | Cache JSON written with `.prettyPrinted, .sortedKeys` for a machine-only file. | **Fixed** — formatting dropped. |
| M8 | `ViewModels/ProjectDashboardViewModel.swift:654-669` | `moveSelectedProjectFolderToTrash` doesn't refresh DDEV registry → stale entry on next refresh. | **Not applied** — needs a UX decision (also call `ddev stop --unlist`? prompt user?). Recommended. |
| M9 | `Services/DDEVCommandService.swift:201-207` | `config(flags:)` validator is purely `hasPrefix("--") && count > 2`. False sense of safety. | **Not applied** — dead code in practice; flags come from a closed enum. Recommended deletion of the public surface in a follow-up. |
| M10 | `Models/DDEVConfig.swift:286-356` | Hand-rolled YAML parser misses flow-style maps, anchors, multiline strings. | **Not applied** — adding Yams is a dependency decision. Documented. |
| M11 | `Views/ProjectInspectorView.swift:101-105` | Command output auto-expands on every command, can't stay collapsed across actions. | **Not applied** — UX decision. |
| M12 | `Models/DDEVProject.swift:248-268` | `applying(details:)` is 21-line member-by-member copy (all-`let` struct). | **Not applied** — public API change (`let` → `var`). Recommended. |
| M13 | `Services/CommandRunning.swift` | `/usr/bin/env <name>` indirection unnecessary when resolver returned an absolute path. | **Not applied** — works correctly today; defer-able hardening. |
| M14 | `Services/DDEVExecutableResolver.swift:15-37` | Resolver tries user-PATH entries before known-good locations → executable hijack if `PATH` is hostile. | **Not applied** — env fallback makes resolved-path bypass moot in practice; tighten in a follow-up. |

---

## LOW (highlights)

- **L1** `ContentView.swift:83-92`, `ProjectListView.swift:54-63` — `Task { @MainActor in }` inside Binding setters is unnecessary (Binding.set is already MainActor) and causes one-frame lag. **Fixed**.
- **L2** `ViewModels/ProjectDashboardViewModel.swift:243` — `requiredBool` defined on `DDEVConfigDocument`, never called. **Fixed** — deleted.
- **L3** `Models/DDEVProject.swift:235-241` — `URL(string: "")` returns nil but `URL(string: " ")` doesn't; empty primaryURL strings can produce zombie URLs. **Not applied** — passes existing tests; recommended.
- **L4** `Services/CommandRunning.swift:26-63` — no timeout or cancellation on subprocess. **Not applied** — pairs with the CRITICAL refactor; recommended next step.
- **L5** `Services/ProjectCacheStore.swift` — cache file written with default umask; `appRoot` becomes future CWD if tampered. **Not applied** — local attack only, the cache should also be re-validated by `ddev list` before use. Recommended hardening.
- **L6** `ViewModels/ProjectDashboardViewModel.swift:146-155` — `selectedProjectFallback` dual-source-of-truth invites stale phantom selection. **Not applied** — recommended after H4 split.

---

## INFO (notes only)

- I1. `ddev utility diagnose` output can include DB passwords / env vars; the one-click copy of diagnostics blob leaks them. Recommended: redact `PASSWORD|SECRET|TOKEN|KEY|DB_|AWS_` lines before the Copy button.
- I2. `moveSelectedProjectFolderToTrash` trusts `appRoot` — combined with M14, a tampered cache could direct trashing of unintended directories. Recommended: assert path under `NSHomeDirectory()` before trashing.
- I3. No SwiftLint/SwiftFormat config — fine for a personal project, future bus-factor concern.
- I4. Most APIs marked `public` in a single-target SPM package — `internal` would suffice. No active harm.
- I5. `@unchecked Sendable` used on five services. Each is currently safe (stateless or NSLock-guarded); flag for re-audit if state is ever added.
- I6. `commandResultsToDisplay` ignores `result:` parameter when `history` is non-empty — dead parameter.
- I7. `recommendedOfficial` add-on list hardcoded in the model. Recommended: move to a resource file or fetch from `ddev add-on list`.
- I8. No `///` doc comments anywhere. For a learning project, adding them on `DDEVServicing` and parser functions would teach the idiom.

---

## Strengths observed

- Consistent use of `Sendable` value types (`struct`) and `protocol`-driven services with constructor injection.
- `@StateObject` once at the root and `@ObservedObject` for children — correct SwiftUI ownership.
- `final class` on every reference type; `private(set)` for published state.
- Tests use hand-rolled **fakes** that record calls (e.g. `FakeDDEVService`), not mocking frameworks.
- Pure parsing layers (`parseYAML`, `parseListOutput`) are statics on the type — discoverable.
- Confirmation dialogs gate every destructive action.
- Real test coverage of parser edge cases, not just the happy path.

---

## Fixes applied in this pass

See `git diff` for the full change. Verified by `swift build` (clean) and `swift test` (113 tests pass, plus new validation tests).

1. **`CommandRunning.swift`** — `ProcessCommandRunner.run` now executes off-main via `withCheckedThrowingContinuation` + `DispatchQueue.global`, with both pipes drained concurrently before `waitUntilExit`. Fixes deadlock and main-thread freeze.
2. **`DDEVAddon.swift`** — table parser substring guard removed; `acme/awesome-add-on`-style names are no longer dropped.
3. **`ProjectDashboardViewModel.swift`** — `runDiagnostics` failure now carries the correct check identity; `loadConfigForSelectedProject` extracts stderr on nonZeroExit; `enrichProjectsWithDetails` runs in parallel via `TaskGroup`; `commandHistory` capped at 50, stored stdout/stderr truncated past 32 KiB.
4. **`DDEVConfig.swift`** — `droppingYAMLComment` tracks quote state. Dead `requiredBool` deleted.
5. **`ProjectCacheStore.swift`** — pretty-print + sorted-keys dropped for the cache file.
6. **`ContentView.swift`, `ProjectListView.swift`** — redundant `Task { @MainActor in }` removed from Binding setters.
7. **`AddonManagerView.swift`** — pass `addon.installName` to remove instead of `addon.repository`.
8. **`DDEVCommandService.swift`** — service-layer validation rejects user-controlled positional args starting with `-` (snapshot restore, add-on get/remove/search). New `DDEVCommandValidationError.dashPrefixedArgument` case.
9. **`Utilities/String+Blank.swift`** — single `internal` `nilIfBlank` extension; private copies removed from 5 files.

## Recommended follow-ups (NOT applied)

In rough priority order:

1. **Split `ProjectDashboardViewModel` into per-domain observable models.** Single highest-leverage refactor. Tests come along.
2. **Decompose `DDEVServicing` into focused protocols** (`DDEVProjectLifecycle`, `DDEVSnapshotService`, ...). Pairs with #1.
3. **Add cancellation + timeout to `ProcessCommandRunner`.** Task cancellation should `process.terminate()` (then SIGKILL after grace). Per-command timeout cap.
4. **Lazy-load Inspector sub-sections** (Tabs or expand-on-tap) so project switch doesn't fire 3-4 concurrent `ddev` calls.
5. **Redact secrets from diagnostics copy blob** before the Copy button is offered.
6. **Lock down cache file** (`posixPermissions: 0o600`) and/or re-resolve `appRoot` from `ddev list` before invoking commands with it.
7. **Replace hand-rolled YAML parser with Yams** (or document the parser as read-only + add inline-map / anchors test).
8. **Convert `DDEVProject` to `var` properties** so `applying(details:)` collapses to two lines.
9. **Move `DDEVMutagenCommand`, `DDEVXHGuiCommand`, `DDEVDatabaseTool`, `DDEVFileImportOptions`, `DDEVCommandValidationError` out of `DDEVCommandService.swift` into `Models/`.**
10. **Add `Pasteboard` service** to lift `NSPasteboard.general` out of view files.

## Raw reviewer reports

- Security: `/tmp/ddevui-review/security.md`
- Bugs & correctness: `/tmp/ddevui-review/bugs.md`
- Code quality & Swift idioms: `/tmp/ddevui-review/quality.md`
- Performance & concurrency: `/tmp/ddevui-review/perfconc.md`
