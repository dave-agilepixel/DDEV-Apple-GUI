# Per-Project Command Concurrency — Design

**Date:** 2026-05-30
**Status:** Approved (pre-implementation)

## Problem

Starting, stopping, or running any command on a project blocks the **whole app**. Every action gates on a single global `isRunningCommand` boolean, so an operation on one project disables controls for all projects — even though they are independent codebases with independent DDEV/Docker state.

This is purely a UI/state-management constraint. The execution layer already supports concurrency: `ProcessCommandRunner.run` dispatches each command onto a global **concurrent** dispatch queue with its own subprocess (`Sources/DDEVUIApp/Services/CommandRunning.swift`). There is no actor, lock, or semaphore serializing commands. The per-project groundwork also already exists — `busyProjectIDs: Set<DDEVProject.ID>` and `isBusy(project)` — but it is shadowed by the global flag, which is flipped on every operation (including the trailing global `refresh()`).

## Goal

Full per-project concurrency: any number of projects (subject to a soft cap) can run commands independently. Each project tracks its own command state, result, error, and history. Background-project command completion surfaces via the project's row **and** a native macOS notification.

The single-project constraint is preserved: a project cannot run two commands at once (DDEV/Docker would conflict). This is the correct use of the per-project "busy" guard.

## Decisions (locked during brainstorming)

1. **Scope:** Full per-project concurrency — per-project result/error/output/history, not just lifecycle-button gating.
2. **Notification model:** Row status update **plus** a native macOS notification when a background-project command finishes.
3. **Notification scope:** All **mutations** on a non-focused project, both success and failure. Skip pure reads. Skip the currently-selected project.
4. **Concurrency cap:** Soft cap (default 3) with a FIFO queue. Overflow requests queue and run as slots free up, with a visible "queued" state.

## Architecture (Approach A)

Chosen over (B) inline-in-ViewModel and (C) per-project sub-view-models. Approach A mirrors the existing dependency-injection pattern (`DDEVServicing`, `CommandRunning`, `AppAvailabilityChecking` are all injected protocols), keeps the scheduler and notification logic unit-testable in isolation, and avoids a disruptive view-layer restructure. It does not bloat the already-large (~900-line) ViewModel with untestable concurrency-queue logic.

### 1. State model

A per-project state value, keyed by project ID:

```swift
struct ProjectCommandState: Sendable {
    enum Activity: Equatable { case idle, queued, running }  // MUTATION lifecycle
    var activity: Activity = .idle
    var isReadingData = false        // a read (logs/config/snapshots/addons) in flight
    var lastResult: CommandResult?
    var lastErrorMessage: String?
    var history: [CommandHistoryEntry] = []
    var outputExpansionRequest = 0
}
```

On `ProjectDashboardViewModel`:

- `@Published var commandStates: [DDEVProject.ID: ProjectCommandState] = [:]` — replaces the per-project parts of today's globals (`busyProjectIDs`, `lastCommandResult`, `lastErrorMessage`, `commandHistory`, `commandOutputExpansionRequest`).
- **Retain** a global pair for genuinely project-less operations: `isRunningGlobalCommand` (renamed from `isRunningCommand`) and `globalErrorMessage`. These cover: global list refresh, global diagnostics, and new-project creation (which has no project ID yet).

**Mutation vs read distinction** — the crux of making "skip pure reads" implementable:

- **Mutations** (start, stop, restart, set PHP version, config apply, addon install/remove, snapshot create/restore/cleanup, db import/export, file import, xhgui, mutagen mutating commands, WordPress updates): drive `activity`, count toward the concurrency cap, gate the lifecycle buttons, and trigger notifications.
- **Reads** (logs, config load, snapshot list, addon list/search, describe, diagnostics reads): set `isReadingData`, run **uncapped**, never notify, never block lifecycle buttons.

Derived accessors:

- `isBusy(project) -> Bool` ≡ `commandStates[id]?.activity ?? .idle != .idle`
- `isQueued(project) -> Bool` ≡ `activity == .queued`
- `state(for project) -> ProjectCommandState` (returns default `.init()` when absent)

### 2. Concurrency scheduler

A standalone actor — a FIFO async semaphore with zero DDEV knowledge:

```swift
actor CommandScheduler {
    init(maxConcurrent: Int)        // default 3
    func acquire() async            // suspends FIFO until a slot frees
    func release()
}
```

**Placement:** at the **ViewModel level, wrapping mutations only**. Flow:

1. Guard: if the project is already busy (`activity != .idle`), return early (same-project single-command guard).
2. Mark `commandStates[id].activity = .queued`.
3. `await scheduler.acquire()`.
4. Mark `.running` (the await resumes on the MainActor-isolated VM).
5. Run the `ddevService` mutation.
6. Record result/error into the project's state; `scheduler.release()`; mark `.idle`.

Reads bypass the scheduler entirely, so the initial parallel "describe all projects" refresh is not throttled to 3.

The exact acquire/release-vs-`run { }`-wrapper syntax is an implementation detail to settle under TDD; the contract is: **at most `maxConcurrent` mutations execute simultaneously; waiters are released FIFO; a thrown operation must not leak a permit.**

Cap is a constant (3) for v1 — trivially movable to `AppPreferences` later. YAGNI for now.

### 3. Notifications

Injectable, following the existing service-protocol pattern:

```swift
protocol NotificationScheduling: Sendable {
    func requestAuthorizationIfNeeded() async
    func notifyCommandFinished(projectName: String, summary: String, succeeded: Bool) async
}
```

Implementations:

- `UserNotificationScheduler` — real, backed by `UNUserNotificationCenter`.
- `NoopNotificationScheduler` — for tests and unbundled `swift build` runs.

Real-impl behavior:

- Guards on `Bundle.main.bundleIdentifier != nil` and no-ops otherwise, so the `swift build -c release` executable (no app bundle) does not crash. Notifications work when run as the Xcode-built `.app` (`com.apple.product-type.application`, bundle id `com.agilepixel.ddevui`).
- Implements `UNUserNotificationCenterDelegate.willPresent` returning a banner, so notifications show even when the app is foregrounded (the user may be viewing a different project).
- **No entitlement file required** — local notifications need only user authorization, not the Push Notifications entitlement. Authorization requested once on launch via `requestAuthorizationIfNeeded()`.

**Fire rule** (in the VM, after a *mutation* completes): if `project.id != selectedProjectID`, call `notifyCommandFinished(...)` — for both success and failure. The "is this the focused project / is this a mutation" decision lives in the VM (testable with a spy), not in the notification implementation.

### 4. View changes + refresh strategy

**Views** — reclassify every `.disabled(viewModel.isRunningCommand)`:

- Row buttons (`ProjectListView`) + inspector lifecycle actions → `.disabled(viewModel.isBusy(project))` (per-project). Add a distinct **queued** treatment on the row (e.g. a clock/"waiting" glyph) vs the running spinner.
- Logs / Snapshots / Config / Addons / Database sub-views (all operate on the *selected* project) → read from `state(for: selected)`: lifecycle gating via `isBusy(selected)`, read spinners via `isReadingData`, and output/error/history panels via that project's `lastResult` / `lastErrorMessage` / `history`.
- Toolbar refresh + global diagnostics → stay on `isRunningGlobalCommand`. The "projects unavailable" empty-state error → `globalErrorMessage`.

**Refresh strategy** (fixes the concurrent-global-refresh race): drop the unconditional global `refresh()` after every mutation.

- **State-changing** mutations (start, stop, restart, php, config, addon, snapshot, etc.) → **re-describe just that one project** and patch it into the `projects` array. No global re-list, no cross-project race. Patching a single element from the MainActor is inherently serialized.
- **Existence-changing** mutations (unlink, deleteDDEVData, configure-new, start-new-folder) → global list refresh under `isRunningGlobalCommand`, with a reentrancy guard so two refreshes cannot race.

## Testing

- `CommandSchedulerTests`: at most N concurrent; FIFO promotion; no permit leak when the wrapped operation throws.
- ViewModel tests via a controllable fake `DDEVServicing` (can hold a command open until released) + a spy `NotificationScheduling`:
  - Two projects run mutations concurrently — no global lock.
  - Same-project second mutation is rejected/ignored while busy.
  - Cap: N+1 mutations → N running + 1 queued; freeing one promotes the queued one.
  - Per-project isolation: project A's failure sets A's error only, not B's; switching selection shows the correct state.
  - Notification fires for a background-project mutation (success and failure); not for the selected project; not for reads.
  - Per-project re-describe patches only the affected project; unlink/delete triggers a full list refresh.
- Notification: keep `UserNotificationScheduler` thin; test the *decision* (when to notify) in the VM with a spy, not `UNUserNotificationCenter` itself.
- **Migration:** update the 29 references to the old global fields in `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift` to the new per-project accessors.

## Risks / call-outs

- **"Queued" state and the read/mutation split** are the two fiddliest areas and where the real correctness lives. Kept deliberately minimal (cap as a constant, reads uncapped) to avoid gold-plating.
- **Unbundled runs:** native notifications silently no-op under `swift build`; they are only live in the Xcode-built `.app`. The graceful-degradation guard is mandatory, not optional.
- **Authorization prompt** appears once on first launch of the bundled app; if denied, rows still update and the feature degrades to row-status-only.

## Out of scope (YAGNI for v1)

- Configurable concurrency cap in preferences.
- A global cross-project activity feed (each project's history is now its own).
- Push notifications / remote anything.
