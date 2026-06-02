# Reactivity & Progress Fixes — Design

**Date:** 2026-06-02
**Status:** Proposed (pre-implementation)

## Problem

Three distinct, independent defects in the project lifecycle UX, batched because they all touch the start/refresh path. (A fourth request — project groups — is deliberately **out of scope** here and gets its own brainstorm.)

1. **New projects don't auto-start.** Registering a folder that needs configuring leaves it stopped — the user reasonably expects a brand-new project to come up.
2. **No determinate progress for start/restart.** The list row shows a plain indeterminate spinner; the user wants a filling donut.
3. **Stale state after a manual start.** After starting a project from the list, the status dot stays grey, the action buttons stay on "Start", and the inspector overview still reads "web stopped / db stopped" — until the user hits the global refresh button *and* re-selects the project. A local app should reflect the action the user just took without manual intervention.

## Goals

- A newly **configured** project starts automatically, matching the already-configured add path.
- Start/restart (and add-then-start) show a **real** progress donut, with an **honest** fallback when progress can't be determined.
- A manual start/stop/restart immediately and correctly updates the status dot, the action buttons, the inspector badge, and the inspector services table — no global refresh, no re-selection.

## Non-Goals

- **External-change detection (polling).** This batch makes *the user's own actions* reflect immediately. It does **not** detect a `ddev start`/`stop` run from the terminal, a container crash, or any change made outside the app. That requires background polling and was explicitly deferred.
- **Project groups.** Separate feature, separate brainstorm.
- Changing the buffered `CommandResult` contract or the existing concurrency/scheduler model.

## Decisions (locked during brainstorming)

1. **Sequencing:** Bugs first (this spec), then groups separately.
2. **Bug 3 depth:** Minimal correct fix — reflect the user's own action immediately. No polling.
3. **Bug 2:** Real stream-and-parse progress, accepting version-drift brittleness, **on the condition that it degrades to indeterminate rather than ever showing a wrong/fake percentage.**
4. **Bug 2 scope:** Donut applies to start / restart / add-then-start. Stop keeps the plain spinner (fast, stage-less).
5. **Bug 2 grounding:** Milestone strings captured from a real `ddev start` run during implementation (start + stop a stopped project, e.g. `agilebugs`, then return it to stopped).
6. **Bug 1 failure handling:** If `config` succeeds but `start` fails, do **not** roll back the registration. Surface the start error; leave the project stopped for retry.

---

## Bug 1 — Auto-start newly configured projects

### Root cause
`ContentView.addFolder()` has two paths (`Sources/DDEVUIApp/Views/ContentView.swift:131`):
- Folder already has `.ddev/config.yaml` → `viewModel.startProject(atFolder:)` → `ddev start`. **Already starts.**
- Folder needs config → `AddProjectSheet` → `viewModel.configureProject(...)` → `ddev config` only. **Never starts.**

### Change
`ProjectDashboardViewModel.configureProject(folder:name:type:docroot:)` (`:363`) runs `config`, then on success runs `start` in the same folder, then refreshes the list — all inside one `runGlobalMutation`-style pipeline so the global spinner and error surface are unified.

- `DDEVServicing` already exposes both `configureProject(in:...)` and `startProject(in:)`; no new service surface needed.
- On `config` failure: surface error, no start (unchanged behavior).
- On `start` failure after `config` success: surface the start error in `globalErrorMessage`; the project remains registered and stopped. Decision #6.

### Files
- `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` (`configureProject`)

### Tests
- Stub `DDEVServicing` records call order: `configureProject` then `startProject` on success.
- `config` fails → `startProject` **not** called; `globalErrorMessage` set.
- `config` ok, `start` fails → both called; `globalErrorMessage` set; no crash.

---

## Bug 3 — Immediate, correct state after a manual mutation

### Root causes
1. **Status is thrown away on re-describe.** `DDEVProject.applying(details:)` (`Sources/DDEVUIApp/Models/DDEVProject.swift:278`) copies the *old* `status`/`statusDescription` forward. `DDEVProjectDetails` doesn't model status at all — even though `ddev describe -j` returns top-level `status` and `status_desc` (verified against a live project). So `reDescribe` can never flip stopped→running. The status dot, the Start/Stop/Restart buttons, and the inspector badge all read `project.status`, so all stay stale.
2. **Inspector overview not refreshed.** The services table reads `selectedProjectDetails`, loaded once per selection by `ProjectInspectorView`'s `.task(id: project.id)` (`Sources/DDEVUIApp/Views/ProjectInspectorView.swift:47`). A start doesn't change the project id, so the task never re-fires; `applyRefresh(.project)` → `reDescribe` patches the `projects` array but never republishes `selectedProjectDetails`.

### Changes
1. **Carry status through describe.**
   - Add `status: DDEVProjectStatus` and `statusDescription: String` to `DDEVProjectDetails`, decoded from `status` / `status_desc` in `RawDDEVProjectDetails` (`Sources/DDEVUIApp/Models/DDEVProjectDetails.swift`). Unknown/missing → `.unknown`.
   - `applying(details:)` takes `status`/`statusDescription` from `details` instead of preserving the stale value. (Document why describe is now trusted for status, mirroring the existing note that `xdebug_enabled` is *not* trusted.)
2. **Republish selected detail on `.project` refresh.**
   - In the `.project` refresh path, when the mutated project is the currently-selected one, publish the freshly-fetched describe into `selectedProjectDetails` too — reusing the single describe `reDescribe` already performs (no extra subprocess). Guard on selection not having moved on, matching the existing `refreshDetails` pattern.

### Boundary (explicit)
Only the project the user acted on is reconciled. Other projects, and changes made outside the app, are untouched until the next global refresh. This is the agreed minimal scope.

### Files
- `Sources/DDEVUIApp/Models/DDEVProjectDetails.swift` (model + decode)
- `Sources/DDEVUIApp/Models/DDEVProject.swift` (`applying(details:)`)
- `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` (`reDescribe` / `applyRefresh` republish to `selectedProjectDetails`)

### Tests
- `DDEVProjectDetails` decodes `status`/`status_desc` from a describe fixture (running + stopped).
- `applying(details:)` adopts the describe status (stopped project + running describe → running).
- After a stubbed `start`, `projects[i].status == .running` and (when selected) `selectedProjectDetails?.status == .running`, with **no** global list refresh invoked.

---

## Bug 2 — Real stream-and-parse progress donut

### Constraints (verified)
- `ProcessCommandRunner.run` is fully buffered — returns only after `waitUntilExit()` (`Sources/DDEVUIApp/Services/CommandRunning.swift:135`). No live signal today.
- `ddev start` emits no percentage — only discrete stage lines. Any fraction is a stage→fraction mapping, not a true measurement.

### Architecture

**1. Streaming at the runner.**
Add an optional line handler to the run path:

```swift
func run(_ spec: CommandSpec, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult
```

- Existing `run(_:)` becomes a convenience that forwards `onOutputLine: nil`. All current callers and the buffered `CommandResult` contract are unchanged.
- The existing `drain` loop already reads chunks; it accumulates into a line buffer and invokes `onOutputLine` per completed line (both stdout and stderr — `ddev` writes status to stderr). Capping/truncation behavior unchanged.

**2. Service + protocol surface.**
`DDEVServicing.start` / `restart` / `startProject` gain progress-aware variants that forward a line handler. To minimize protocol churn, add **new** progress-aware methods (e.g. `start(projectName:onOutputLine:)`) rather than changing existing signatures; the plain methods remain for callers that don't want progress.

**3. Progress state + parser.**
- Add `startProgress: Double?` to `ProjectCommandState` (`Sources/DDEVUIApp/Models/ProjectCommandState.swift`). `nil` = indeterminate.
- A small, pure `StartProgressParser`:
  - Ordered list of milestone substrings → cumulative fraction (e.g. recognized container/stage lines), **monotonic** (max of current and new; never decreases).
  - Capped strictly below `1.0` while running; set to `1.0` only on successful exit.
  - Returns `nil` contribution for unrecognized lines.
- The VM consumes lines **on the main actor** (lines arrive on a background queue; bridged via an `AsyncStream` the `@MainActor` VM iterates, so `commandStates[id].startProgress` is mutated only on the main actor and ordering is preserved).
- On completion (success or failure), `startProgress` is cleared back to `nil` as `activity` returns to `.idle`.

**4. Graceful degradation (the contract).**
If **no** milestone matches for the whole run, `startProgress` stays `nil` and the donut renders **indeterminate**. Never a fabricated percentage, never a stuck partial ring after completion. This is the condition under which real-progress was accepted.

**5. UI.**
`ProjectRow.actionControls` (`Sources/DDEVUIApp/Views/ProjectListView.swift:172`):
- `startProgress != nil` → determinate ring: `Circle().trim(from: 0, to: progress).stroke(...)`, animated, small control size.
- `startProgress == nil` but busy → indeterminate rotating ring (donut-shaped, replacing the default `ProgressView` for start/restart).
- Stop → unchanged plain spinner.

### Grounding step (implementation-time)
Capture real `ddev start` output by starting then stopping a stopped project (e.g. `agilebugs`), returning it to stopped afterward. Derive the milestone list and bake a fixture into the parser tests so the mapping is regression-checked, not guessed.

### Files
- `Sources/DDEVUIApp/Services/CommandRunning.swift` (line handler + per-line drain)
- `Sources/DDEVUIApp/Services/DDEVCommandService.swift` (progress-aware start/restart/startProject)
- `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` (`DDEVServicing` additions, line consumption, progress wiring)
- `Sources/DDEVUIApp/Models/ProjectCommandState.swift` (`startProgress`)
- new `Sources/DDEVUIApp/Models/StartProgressParser.swift` (pure parser)
- `Sources/DDEVUIApp/Views/ProjectListView.swift` (donut)

### Tests
- `StartProgressParser`: captured-output fixture → monotonic increasing fractions, `< 1.0` until success.
- Unrecognized output → all `nil` (indeterminate fallback).
- Line handler in `ProcessCommandRunner` receives line-split output (and the buffered result still matches).
- VM: stub service emits scripted lines → `startProgress` advances monotonically then clears to `nil` on completion.

---

## Risks & mitigations

- **`ddev` version drift breaks the parser (Bug 2).** Mitigated by the indeterminate fallback — worst case is the old behavior (a spinner, donut-shaped), never a wrong number.
- **Concurrency ordering of progress lines (Bug 2).** Mitigated by funneling lines through an `AsyncStream` consumed on the main actor; no cross-actor mutation of `commandStates`.
- **Trusting describe for status (Bug 3).** `status`/`status_desc` are stable top-level fields in `ddev describe -j` (verified). If absent, decode to `.unknown` rather than crashing; the global refresh still corrects it.
- **Partial success on add (Bug 1).** Explicitly handled by decision #6 — no rollback, surfaced error.

## Sequencing of implementation
Bug 1 → Bug 3 → Bug 2, as three independent commits. Bug 1 and Bug 3 are small and unlock the visible correctness wins; Bug 2 is the larger architectural change and is isolated last so the streaming work can't destabilize the simpler fixes.
