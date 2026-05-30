# Per-Project Command Concurrency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let commands run independently per project — starting/stopping one project never freezes the others — with a bounded concurrency queue, per-project result/error/history state, and a macOS notification when a background project's command finishes.

**Architecture:** A standalone `CommandScheduler` actor (FIFO async semaphore) bounds concurrent *mutations*. `ProjectDashboardViewModel` holds per-project `ProjectCommandState` keyed by project name, routes mutations through the scheduler, re-describes only the affected project after a state change, and posts a macOS notification (via an injected `NotificationScheduling` service) when a *non-selected* project's mutation finishes. Reads (logs/config/etc.) bypass the scheduler and never notify. A single global busy/error pair survives only for genuinely project-less operations (list refresh, global diagnostics, new-project creation).

**Tech Stack:** Swift 6.2, SwiftUI, Swift Concurrency (actors, async/await), XCTest, `UNUserNotificationCenter`. Spec: `docs/superpowers/specs/2026-05-30-per-project-concurrency-design.md`.

---

## Key facts the engineer needs

- `DDEVProject` is `Identifiable` with `var id: String { name }` (`Sources/DDEVUIApp/Models/DDEVProject.swift:3`). So `commandStates` is keyed by the project **name** string.
- `DDEVProject.applying(details:)` returns a copy with describe data merged in (`Sources/DDEVUIApp/Models/DDEVProject.swift:263`). Used to patch one project after re-describe.
- `ProcessCommandRunner` already runs every command on a concurrent queue — nothing serializes at the execution layer (`Sources/DDEVUIApp/Services/CommandRunning.swift:28`). The cap we add is purely a chosen policy, not a fix for a missing one.
- `CommandResult` has `executable, arguments, workingDirectory, exitCode, stdout, stderr, startedAt, finishedAt, wasCancelled` and `var succeeded: Bool`. `CommandRunnerError.nonZeroExit(CommandResult)` is thrown on non-zero exit.
- The VM is `@MainActor`. Because of that, **after `await scheduler.acquire()` the code resumes on the MainActor** — so reading/writing `@Published` state right after an `await` is safe and needs no extra hop.
- The VM is built once: `@StateObject private var viewModel = ProjectDashboardViewModel()` (`Sources/DDEVUIApp/Views/ContentView.swift:4`). `init` params all have defaults, so new injected dependencies must also default.
- Build/test: `swift build` and `swift test`. Run a single test with `swift test --filter <TestClass>/<testMethod>`.
- Commit trailer: this repo does **not** use a Claude co-author trailer. Plain commits.

## File Structure

**Create:**
- `Sources/DDEVUIApp/Services/CommandScheduler.swift` — FIFO async-semaphore actor bounding concurrent mutations.
- `Sources/DDEVUIApp/Services/NotificationScheduling.swift` — protocol + `UserNotificationScheduler` (real) + `NoopNotificationScheduler` (fallback/tests).
- `Sources/DDEVUIApp/Models/ProjectCommandState.swift` — per-project command state value + `CommandHistoryEntry` (moved here from the VM).
- `Tests/DDEVUIAppTests/CommandSchedulerTests.swift`
- `Tests/DDEVUIAppTests/ProjectConcurrencyTests.swift` — concurrency/cap/notification behaviour of the VM.

**Modify:**
- `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` — per-project state, mutation pipeline, read pipeline, re-describe, notification wiring, init injection.
- `Sources/DDEVUIApp/Views/ProjectListView.swift` — row gating + queued treatment + global-error empty state.
- `Sources/DDEVUIApp/Views/ProjectInspectorView.swift` — selected-project gating + display fields.
- `Sources/DDEVUIApp/Views/ProjectConfigEditorView.swift` — selected-project gating + display fields.
- `Sources/DDEVUIApp/Views/{LogsViewerView,SnapshotManagerView,DatabaseOperationsView,AddonManagerView,DiagnosticsView,FrameworkCommandLauncherView,ContentView}.swift` — gating swaps.
- `Sources/DDEVUIApp/DDEVUIApp.swift` — request notification authorization on launch.
- `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift` — migrate assertions to per-project accessors and the new refresh behaviour.

---

## Task 1: `CommandScheduler` actor

A FIFO async semaphore. No DDEV knowledge. Bounds concurrent mutations; releases waiters in arrival order; never leaks a permit.

**Files:**
- Create: `Sources/DDEVUIApp/Services/CommandScheduler.swift`
- Test: `Tests/DDEVUIAppTests/CommandSchedulerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/DDEVUIAppTests/CommandSchedulerTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

final class CommandSchedulerTests: XCTestCase {
    func testRunsAtMostMaxConcurrentAtOnce() async {
        let scheduler = CommandScheduler(maxConcurrent: 2)
        let tracker = ConcurrencyTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    await scheduler.acquire()
                    await tracker.enter()
                    // Yield a few times so overlapping work would be observed if the cap leaked.
                    for _ in 0..<5 { await Task.yield() }
                    await tracker.leave()
                    await scheduler.release()
                }
            }
        }

        let peak = await tracker.peak
        XCTAssertEqual(peak, 2, "Never more than maxConcurrent permits held at once")
    }

    func testReleaseHandsPermitToWaiterFIFO() async {
        let scheduler = CommandScheduler(maxConcurrent: 1)
        let order = OrderRecorder()

        await scheduler.acquire()              // take the only permit

        // Queue three waiters in a known order.
        let waiters = (0..<3).map { index in
            Task {
                await scheduler.acquire()
                await order.record(index)
                await scheduler.release()
            }
        }
        // Give the waiters time to enqueue, then release one at a time.
        for _ in 0..<10 { await Task.yield() }
        await scheduler.release()
        for waiter in waiters { _ = await waiter.value }

        let recorded = await order.values
        XCTAssertEqual(recorded, [0, 1, 2], "Waiters resume strictly FIFO")
    }

    func testRunReleasesPermitEvenWhenOperationThrows() async {
        let scheduler = CommandScheduler(maxConcurrent: 1)
        struct Boom: Error {}

        do {
            _ = try await scheduler.run { throw Boom() }
            XCTFail("Expected throw")
        } catch {
            // expected
        }

        // If the permit leaked, this acquire would hang forever; wrap in a timeout guard.
        let acquired = await withTimeout(seconds: 1) { await scheduler.acquire(); return true } ?? false
        XCTAssertTrue(acquired, "Permit was released despite the thrown operation")
    }
}

// MARK: - Test helpers

private actor ConcurrencyTracker {
    private var current = 0
    private(set) var peak = 0
    func enter() { current += 1; peak = max(peak, current) }
    func leave() { current -= 1 }
}

private actor OrderRecorder {
    private(set) var values: [Int] = []
    func record(_ value: Int) { values.append(value) }
}

/// Runs `operation`, returning nil if it does not finish within `seconds`.
private func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CommandSchedulerTests`
Expected: FAIL to compile — `cannot find 'CommandScheduler' in scope`.

- [ ] **Step 3: Implement `CommandScheduler`**

Create `Sources/DDEVUIApp/Services/CommandScheduler.swift`:

```swift
import Foundation

/// A FIFO async semaphore that bounds how many command operations run at once.
///
/// Has zero DDEV knowledge — it simply hands out a fixed number of permits and releases
/// blocked callers in arrival order. `ProjectDashboardViewModel` uses it to cap concurrent
/// project *mutations* (start/stop/restart/import/…) so a "start everything" burst does not
/// thrash Docker. Reads (logs/config/describe) bypass it entirely.
public actor CommandScheduler {
    private let maxConcurrent: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(maxConcurrent: Int = 3) {
        precondition(maxConcurrent >= 1, "maxConcurrent must be >= 1")
        self.maxConcurrent = maxConcurrent
        self.available = maxConcurrent
    }

    /// Suspends until a permit is free. Queued callers resume strictly FIFO.
    public func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Returns a permit. If a caller is waiting, the permit is handed directly to the oldest
    /// waiter (the total in-flight count is conserved); otherwise the free count grows.
    public func release() {
        if waiters.isEmpty {
            available = min(available + 1, maxConcurrent)
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Runs `operation` while holding a permit; releases it even if `operation` throws.
    public func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CommandSchedulerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Services/CommandScheduler.swift Tests/DDEVUIAppTests/CommandSchedulerTests.swift
git commit -m "feat(concurrency): add CommandScheduler FIFO async semaphore"
```

---

## Task 2: `NotificationScheduling` service

A protocol with a real `UNUserNotificationCenter` implementation and a no-op fallback (used by tests and by the unbundled `swift build` executable). The *decision* of when to notify lives in the VM (Task 5) and is tested there with a spy; this task keeps the impl thin and safe.

**Files:**
- Create: `Sources/DDEVUIApp/Services/NotificationScheduling.swift`

- [ ] **Step 1: Implement the protocol and both implementations**

Create `Sources/DDEVUIApp/Services/NotificationScheduling.swift`:

```swift
import Foundation
import UserNotifications

/// Surfaces background-project command completions as macOS user notifications.
public protocol NotificationScheduling: Sendable {
    /// Requests notification authorization once, if the app is able to (no-op otherwise).
    func requestAuthorizationIfNeeded() async
    /// Posts a completion notification for a project command.
    func notifyCommandFinished(projectName: String, summary: String, succeeded: Bool) async
}

/// No-op implementation. Used in tests and whenever the process is not a real app bundle
/// (e.g. the `swift build` executable), where `UNUserNotificationCenter` is unavailable.
public struct NoopNotificationScheduler: NotificationScheduling {
    public init() {}
    public func requestAuthorizationIfNeeded() async {}
    public func notifyCommandFinished(projectName: String, summary: String, succeeded: Bool) async {}
}

/// Real implementation backed by `UNUserNotificationCenter`.
///
/// Local notifications need only user authorization — no Push entitlement. They only work
/// inside a real app bundle, so every entry point guards on `Bundle.main.bundleIdentifier`
/// and silently no-ops otherwise, keeping the unbundled `swift build` executable crash-free.
public final class UserNotificationScheduler: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    public func activateForegroundPresentation() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    public func requestAuthorizationIfNeeded() async {
        guard isBundled else { return }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    public func notifyCommandFinished(projectName: String, summary: String, succeeded: Bool) async {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = projectName
        content.body = succeeded ? "\(summary) finished" : "\(summary) failed"
        content.sound = succeeded ? nil : .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // Present banners even when the app is foregrounded — the user may be viewing a
    // different project than the one whose command just finished.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds with no errors (no test yet — behaviour is exercised via the VM spy in Task 5).

- [ ] **Step 3: Commit**

```bash
git add Sources/DDEVUIApp/Services/NotificationScheduling.swift
git commit -m "feat(notifications): add NotificationScheduling service with bundle-safe UNUserNotificationCenter impl"
```

---

## Task 3: `ProjectCommandState` model

Extract per-project command state into its own value type, and move `CommandHistoryEntry` out of the VM into the same file (it is part of this state).

**Files:**
- Create: `Sources/DDEVUIApp/Models/ProjectCommandState.swift`
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` (remove the old `CommandHistoryEntry` declaration)

- [ ] **Step 1: Create the model file**

Create `Sources/DDEVUIApp/Models/ProjectCommandState.swift`:

```swift
import Foundation

public struct CommandHistoryEntry: Equatable, Sendable {
    public let result: CommandResult

    public init(result: CommandResult) {
        self.result = result
    }
}

/// All command state scoped to a single project. Stored per project id in the view model.
public struct ProjectCommandState: Equatable, Sendable {
    /// Lifecycle of an in-flight *mutation* (start/stop/restart/…). Drives the cap, the
    /// row spinner, the single-command-per-project guard, and notifications.
    public enum Activity: Equatable, Sendable {
        case idle
        case queued
        case running
    }

    public var activity: Activity = .idle
    /// A *read* (logs/config/snapshot-list/addon-list) is in flight. Does not block lifecycle.
    public var isReadingData = false
    public var lastResult: CommandResult?
    public var lastErrorMessage: String?
    public var history: [CommandHistoryEntry] = []
    public var outputExpansionRequest = 0

    public init() {}

    public var isBusy: Bool { activity != .idle }
}
```

- [ ] **Step 2: Remove the duplicate `CommandHistoryEntry` from the view model**

In `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`, delete this block (currently around lines 47–53):

```swift
public struct CommandHistoryEntry: Equatable, Sendable {
    public let result: CommandResult

    public init(result: CommandResult) {
        self.result = result
    }
}
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: builds (the VM still uses `CommandHistoryEntry`, now resolved from the new file).

- [ ] **Step 4: Commit**

```bash
git add Sources/DDEVUIApp/Models/ProjectCommandState.swift Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift
git commit -m "refactor(state): extract ProjectCommandState and CommandHistoryEntry into a model"
```

---

## Task 4: Per-project state, accessors, and dependency injection on the view model

Introduce the `commandStates` dictionary, the retained global pair, convenience accessors, and inject the scheduler + notifier. No behaviour change yet — this is the scaffolding the pipelines in Task 5/6 build on. The old global fields are kept temporarily so the project still compiles; they are removed in Task 5/6.

**Files:**
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift:95-145`

- [ ] **Step 1: Add new stored state and rename the global flag**

In `ProjectDashboardViewModel`, replace the published-property block. **Find** (currently lines ~97-119):

```swift
    @Published public var projects: [DDEVProject] = []
    @Published public var selectedProjectID: DDEVProject.ID?
    @Published public var selectedSidebarItem: ProjectSidebarItem = .projects
    @Published public var searchText = ""
    @Published public var isRunningCommand = false
    @Published public var busyProjectIDs: Set<DDEVProject.ID> = []
    @Published public var lastCommandResult: CommandResult?
    @Published public var lastErrorMessage: String?
    @Published public var commandOutputExpansionRequest = 0
    @Published public var commandHistory: [CommandHistoryEntry] = []
```

**Replace with:**

```swift
    @Published public var projects: [DDEVProject] = []
    @Published public var selectedProjectID: DDEVProject.ID?
    @Published public var selectedSidebarItem: ProjectSidebarItem = .projects
    @Published public var searchText = ""

    /// Per-project command state, keyed by project id (the project name). The single source
    /// of truth for busy/queued lifecycle, last result, error, history, and output expansion.
    @Published public var commandStates: [DDEVProject.ID: ProjectCommandState] = [:]

    /// Busy/error for genuinely project-less operations: global list refresh, global
    /// diagnostics, and new-project creation (which has no project id yet).
    @Published public var isRunningGlobalCommand = false
    @Published public var globalErrorMessage: String?
```

- [ ] **Step 2: Inject the scheduler and notifier**

**Find** the stored dependencies and `init` (currently lines ~126-145):

```swift
    private let ddevService: DDEVServicing
    private let projectCache: ProjectCacheStoring
    private let preferencesStore: AppPreferencesStoring
    private let appAvailability: AppAvailabilityChecking
    private var selectedProjectFallback: DDEVProject?

    public init(
        ddevService: DDEVServicing = DDEVCommandService(),
        projectCache: ProjectCacheStoring = FileProjectCacheStore(),
        preferencesStore: AppPreferencesStoring = UserDefaultsAppPreferencesStore(),
        appAvailability: AppAvailabilityChecking = WorkspaceAppAvailabilityService()
    ) {
        self.ddevService = ddevService
        self.projectCache = projectCache
        self.preferencesStore = preferencesStore
        self.appAvailability = appAvailability
        self.preferences = preferencesStore.loadPreferences()
        self.installedEditors = appAvailability.installedEditors()
        self.installedDatabaseTools = appAvailability.installedDatabaseTools()
    }
```

**Replace with:**

```swift
    private let ddevService: DDEVServicing
    private let projectCache: ProjectCacheStoring
    private let preferencesStore: AppPreferencesStoring
    private let appAvailability: AppAvailabilityChecking
    private let scheduler: CommandScheduler
    private let notifier: NotificationScheduling
    private var selectedProjectFallback: DDEVProject?

    public init(
        ddevService: DDEVServicing = DDEVCommandService(),
        projectCache: ProjectCacheStoring = FileProjectCacheStore(),
        preferencesStore: AppPreferencesStoring = UserDefaultsAppPreferencesStore(),
        appAvailability: AppAvailabilityChecking = WorkspaceAppAvailabilityService(),
        scheduler: CommandScheduler = CommandScheduler(maxConcurrent: 3),
        notifier: NotificationScheduling = NoopNotificationScheduler()
    ) {
        self.ddevService = ddevService
        self.projectCache = projectCache
        self.preferencesStore = preferencesStore
        self.appAvailability = appAvailability
        self.scheduler = scheduler
        self.notifier = notifier
        self.preferences = preferencesStore.loadPreferences()
        self.installedEditors = appAvailability.installedEditors()
        self.installedDatabaseTools = appAvailability.installedDatabaseTools()
    }
```

- [ ] **Step 3: Replace the `isBusy` accessor and add convenience accessors**

**Find** (currently lines ~260-262):

```swift
    public func isBusy(_ project: DDEVProject) -> Bool {
        busyProjectIDs.contains(project.id)
    }
```

**Replace with:**

```swift
    public func state(for id: DDEVProject.ID) -> ProjectCommandState {
        commandStates[id] ?? ProjectCommandState()
    }

    public func isBusy(_ project: DDEVProject) -> Bool {
        state(for: project.id).isBusy
    }

    public func isQueued(_ project: DDEVProject) -> Bool {
        state(for: project.id).activity == .queued
    }

    /// State of the currently-selected project (empty default when nothing is selected).
    public var selectedProjectState: ProjectCommandState {
        guard let selectedProjectID else { return ProjectCommandState() }
        return state(for: selectedProjectID)
    }

    public var isSelectedProjectBusy: Bool {
        selectedProjectState.isBusy
    }
```

- [ ] **Step 4: Verify it builds (expect known errors to fix in Task 5/6)**

Run: `swift build`
Expected: FAILS — references to the removed `isRunningCommand`, `lastCommandResult`, `lastErrorMessage`, `commandHistory`, `commandOutputExpansionRequest`, `busyProjectIDs`, and `recordCommandResult` no longer resolve in the VM and views. This is expected; Tasks 5–7 fix every site. Do **not** commit a non-building tree — proceed straight to Task 5.

> Note: Tasks 4, 5, and 6 form one non-building stretch. Treat them as a single commit boundary: commit only at the end of Task 6 Step (final), when `swift build` and the migrated VM tests pass. If using subagent-driven execution, assign Tasks 4–6 to one subagent.

---

## Task 5: Mutation pipeline (scheduler + per-project state + re-describe + notify)

This is the behavioural core. Replace `runMutation`/`runMutation(markingBusy:)` with one `runProjectMutation` that: guards one-command-per-project, marks queued→running around `scheduler.acquire()`, records the result into per-project state, refreshes per the given scope, and notifies if the project is not selected.

**Files:**
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
- Test: `Tests/DDEVUIAppTests/ProjectConcurrencyTests.swift`

- [ ] **Step 1: Write the failing concurrency/notification tests**

Create `Tests/DDEVUIAppTests/ProjectConcurrencyTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

@MainActor
final class ProjectConcurrencyTests: XCTestCase {
    func testTwoProjectsRunMutationsConcurrently() async {
        let service = GatedDDEVService(projects: [.sampleWordPress, .sampleLaravel])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        await viewModel.refresh()

        async let first: Void = viewModel.start(.sampleWordPress)
        async let second: Void = viewModel.start(.sampleLaravel)

        // Wait until both are reported running, then release both.
        await service.waitForInFlight(count: 2)
        XCTAssertEqual(viewModel.state(for: "aqua-pura").activity, .running)
        XCTAssertEqual(viewModel.state(for: "agilebugs").activity, .running)

        await service.releaseAll()
        _ = await (first, second)

        XCTAssertFalse(viewModel.isBusy(.sampleWordPress))
        XCTAssertFalse(viewModel.isBusy(.sampleLaravel))
    }

    func testSameProjectSecondMutationIgnoredWhileBusy() async {
        let service = GatedDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        await viewModel.refresh()

        async let first: Void = viewModel.start(.sampleWordPress)
        await service.waitForInFlight(count: 1)

        await viewModel.start(.sampleWordPress) // should be ignored (already running)

        await service.releaseAll()
        _ = await first

        let starts = service.commands.filter { $0 == "start:aqua-pura" }
        XCTAssertEqual(starts.count, 1, "Second start while busy is ignored")
    }

    func testCapQueuesExcessMutations() async {
        let service = GatedDDEVService(projects: [.sampleWordPress, .sampleLaravel, .sampleDrupal])
        let viewModel = ProjectDashboardViewModel(
            ddevService: service,
            scheduler: CommandScheduler(maxConcurrent: 2)
        )
        await viewModel.refresh()

        async let a: Void = viewModel.start(.sampleWordPress)
        async let b: Void = viewModel.start(.sampleLaravel)
        async let c: Void = viewModel.start(.sampleDrupal)

        await service.waitForInFlight(count: 2)
        XCTAssertEqual(viewModel.state(for: "drupal-demo").activity, .queued,
                       "Third mutation waits behind the cap of 2")

        await service.releaseAll()
        _ = await (a, b, c)
        XCTAssertEqual(service.commands.filter { $0.hasPrefix("start:") }.count, 3)
    }

    func testBackgroundProjectMutationNotifies() async {
        let service = GatedDDEVService(projects: [.sampleWordPress, .sampleLaravel])
        let spy = SpyNotificationScheduler()
        let viewModel = ProjectDashboardViewModel(ddevService: service, notifier: spy)
        await viewModel.refresh()
        viewModel.selectedProject = .sampleWordPress // aqua-pura is focused

        let task = Task { await viewModel.stop(.sampleLaravel) } // background project
        await service.waitForInFlight(count: 1)
        await service.releaseAll()
        await task.value

        XCTAssertEqual(spy.calls.map(\.projectName), ["agilebugs"])
        XCTAssertEqual(spy.calls.first?.succeeded, true)
    }

    func testSelectedProjectMutationDoesNotNotify() async {
        let service = GatedDDEVService(projects: [.sampleWordPress])
        let spy = SpyNotificationScheduler()
        let viewModel = ProjectDashboardViewModel(ddevService: service, notifier: spy)
        await viewModel.refresh()
        viewModel.selectedProject = .sampleWordPress

        let task = Task { await viewModel.start(.sampleWordPress) }
        await service.waitForInFlight(count: 1)
        await service.releaseAll()
        await task.value

        XCTAssertTrue(spy.calls.isEmpty, "No notification for the focused project")
    }

    func testStateChangingMutationReDescribesOnlyThatProject() async {
        let service = GatedDDEVService(projects: [.sampleWordPress, .sampleLaravel])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        await viewModel.refresh()
        service.resetCommands()

        let task = Task { await viewModel.stop(.sampleLaravel) }
        await service.waitForInFlight(count: 1)
        await service.releaseAll()
        await task.value

        XCTAssertEqual(service.commands, ["stop:agilebugs", "describe:agilebugs"],
                       "No global 'list'; only the affected project is re-described")
    }
}
```

Add a `sampleDrupal` fixture and the gated service. Append to the bottom of `Tests/DDEVUIAppTests/ProjectConcurrencyTests.swift`:

```swift
// MARK: - Test doubles

private struct SpyCall: Equatable { let projectName: String; let succeeded: Bool }

@MainActor
private final class SpyNotificationScheduler: NotificationScheduling {
    nonisolated(unsafe) var calls: [SpyCall] = []
    nonisolated func requestAuthorizationIfNeeded() async {}
    nonisolated func notifyCommandFinished(projectName: String, summary: String, succeeded: Bool) async {
        await MainActor.run { self.calls.append(SpyCall(projectName: projectName, succeeded: succeeded)) }
    }
}

/// A DDEV service whose mutating calls block until the test releases them, so two commands
/// can be observed in flight simultaneously. Reads (list/describe) return immediately.
private actor GatedDDEVService: DDEVServicing {
    private let projects: [DDEVProject]
    private var recorded: [String] = []
    private var inFlight = 0
    private var gate: [CheckedContinuation<Void, Never>] = []

    init(projects: [DDEVProject]) { self.projects = projects }

    nonisolated var commands: [String] {
        // Snapshot via a blocking hop; acceptable in tests.
        let box = UnsafeCommandsBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task { box.value = await self.snapshotCommands(); semaphore.signal() }
        semaphore.wait()
        return box.value
    }
    private func snapshotCommands() -> [String] { recorded }
    func resetCommands() { recorded = [] }

    func waitForInFlight(count: Int) async {
        while inFlight < count { await Task.yield() }
    }
    func releaseAll() {
        let waiters = gate; gate = []
        waiters.forEach { $0.resume() }
    }

    private func runGated(_ label: String) async -> CommandResult {
        recorded.append(label)
        inFlight += 1
        await withCheckedContinuation { gate.append($0) }
        inFlight -= 1
        return CommandResult(executable: "ddev", arguments: label.split(separator: ":").map(String.init),
                             workingDirectory: nil, exitCode: 0, stdout: "", stderr: "",
                             startedAt: .distantPast, finishedAt: .distantPast, wasCancelled: false)
    }

    func listProjects() async throws -> [DDEVProject] { recorded.append("list"); return projects }
    func describe(projectName: String) async throws -> DDEVProjectDetails {
        recorded.append("describe:\(projectName)"); return DDEVProjectDetails(phpVersion: nil, xhguiStatus: nil)
    }
    func start(projectName: String) async throws -> CommandResult { await runGated("start:\(projectName)") }
    func stop(projectName: String) async throws -> CommandResult { await runGated("stop:\(projectName)") }
    func restart(projectName: String) async throws -> CommandResult { await runGated("restart:\(projectName)") }

    // Remaining DDEVServicing methods are unused by these tests; return immediately.
    func unlink(projectName: String) async throws -> CommandResult { await runGated("unlink:\(projectName)") }
    func deleteDDEVData(projectName: String) async throws -> CommandResult { await runGated("delete:\(projectName)") }
    func startProject(in appRoot: String) async throws -> CommandResult { await runGated("start-folder") }
    func configureProject(in appRoot: String, name: String, type: DDEVProjectType, docroot: String) async throws -> CommandResult { await runGated("config") }
    func setPHPVersion(_ version: String, in appRoot: String) async throws -> CommandResult { await runGated("php") }
    func launchDatabaseTool(_ tool: DDEVDatabaseTool, in appRoot: String) async throws -> CommandResult { await runGated("db") }
    func importDatabase(_ options: DDEVDatabaseImportOptions, in appRoot: String) async throws -> CommandResult { await runGated("import") }
    func exportDatabase(_ options: DDEVDatabaseExportOptions, in appRoot: String) async throws -> CommandResult { await runGated("export") }
    func importFiles(_ options: DDEVFileImportOptions, in appRoot: String) async throws -> CommandResult { await runGated("import-files") }
    func createSnapshot(name: String?, in appRoot: String) async throws -> CommandResult { await runGated("snapshot") }
    func listSnapshots(in appRoot: String) async throws -> CommandResult { recorded.append("snapshot-list"); return await runImmediate() }
    func restoreSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult { await runGated("snapshot-restore") }
    func restoreLatestSnapshot(in appRoot: String) async throws -> CommandResult { await runGated("snapshot-restore-latest") }
    func cleanupSnapshots(in appRoot: String) async throws -> CommandResult { await runGated("snapshot-cleanup") }
    func cleanupSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult { await runGated("snapshot-cleanup-one") }
    func logs(projectName: String, service: String, tail: Int, includeTimestamps: Bool, in appRoot: String) async throws -> CommandResult { recorded.append("logs"); return await runImmediate() }
    func listInstalledAddOns(projectName: String, in appRoot: String) async throws -> CommandResult { recorded.append("addon-list"); return await runImmediate() }
    func searchAddOns(query: String, in appRoot: String) async throws -> CommandResult { recorded.append("addon-search"); return await runImmediate() }
    func getAddOn(_ repository: String, projectName: String, in appRoot: String) async throws -> CommandResult { await runGated("addon-get") }
    func removeAddOn(named name: String, projectName: String, in appRoot: String) async throws -> CommandResult { await runGated("addon-remove") }
    func config(flags: [String], in appRoot: String) async throws -> CommandResult { await runGated("config-flags") }
    func applyConfigChange(_ change: DDEVConfigChange, in appRoot: String) async throws -> CommandResult { await runGated("config-change") }
    func runProjectCommand(arguments: [String], in appRoot: String) async throws -> CommandResult { await runGated("project-command") }
    func version() async throws -> CommandResult { recorded.append("version"); return await runImmediate() }
    func utilityDiagnose(in appRoot: String?) async throws -> CommandResult { recorded.append("diagnose"); return await runImmediate() }
    func utilityConfigYAML(omitKeys: [String], in appRoot: String) async throws -> CommandResult { recorded.append("configyaml"); return await runImmediate() }
    func utilityCheckCustomConfig(in appRoot: String) async throws -> CommandResult { recorded.append("check-custom-config"); return await runImmediate() }
    func utilityCheckDBMatch(in appRoot: String) async throws -> CommandResult { recorded.append("check-db-match"); return await runImmediate() }
    func mutagen(_ command: DDEVMutagenCommand, in appRoot: String) async throws -> CommandResult { recorded.append("mutagen"); return await runImmediate() }
    func xhgui(_ command: DDEVXHGuiCommand, in appRoot: String) async throws -> CommandResult { await runGated("xhgui") }
    func updateWordPressCore(in appRoot: String) async throws -> CommandResult { await runGated("wp-core") }
    func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult { await runGated("wp-plugins") }
    func updateWordPressThemes(in appRoot: String) async throws -> CommandResult { await runGated("wp-themes") }

    private func runImmediate() -> CommandResult {
        CommandResult(executable: "ddev", arguments: [], workingDirectory: nil, exitCode: 0,
                      stdout: "", stderr: "", startedAt: .distantPast, finishedAt: .distantPast, wasCancelled: false)
    }
}

private final class UnsafeCommandsBox: @unchecked Sendable { var value: [String] = [] }

extension DDEVProject {
    static let sampleDrupal = DDEVProject(
        name: "drupal-demo",
        appRoot: "/Users/dave/Development/agilepixel/drupal-demo",
        shortRoot: "~/Development/agilepixel/drupal-demo",
        status: .running, statusDescription: "running",
        projectType: .drupal, docroot: "web",
        primaryURL: URL(string: "https://drupal-demo.ddev.site"),
        httpURL: nil, httpsURL: nil, mailpitURL: nil, mailpitHTTPSURL: nil,
        xhguiURL: nil, xhguiHTTPSURL: nil, xhguiStatus: nil,
        mutagenEnabled: true, mutagenStatus: "ok", phpVersion: nil
    )
}
```

> Verified: `DDEVProjectType.drupal` exists (`Sources/DDEVUIApp/Models/DDEVProject.swift:94`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ProjectConcurrencyTests`
Expected: FAIL to compile/run — the new pipeline methods do not exist yet and the VM does not build (Task 4 left it intentionally broken).

- [ ] **Step 3: Implement the mutation pipeline**

In `ProjectDashboardViewModel`, **replace** the two private `runMutation` methods, `runAndCapture`, and `recordCommandResult` (currently lines ~702-789) with the following. Keep `runDiagnostics`, `diagnosticEntry`, the `bounded`/`bound` helpers, and `commandHistoryLimit`/`commandHistoryOutputLimit` as they are.

```swift
    enum RefreshScope {
        case project   // re-describe just the affected project (state changed)
        case fullList  // re-list everything (project added/removed/renamed)
        case none      // no refresh (e.g. export writes a file, changes nothing)
    }

    /// Runs a state-changing command for one project: cap-gated, per-project state, scoped
    /// refresh, and a notification when the project is not the focused one.
    private func runProjectMutation(
        _ project: DDEVProject,
        refresh: RefreshScope = .project,
        _ operation: @escaping () async throws -> CommandResult
    ) async {
        let id = project.id
        guard !isBusy(project) else { return } // one command per project at a time

        setActivity(.queued, for: id)
        await scheduler.acquire()              // resumes on MainActor
        setActivity(.running, for: id)

        let outcome = await execute(operation)
        scheduler.release()                    // free the slot before the read-y describe
        setActivity(.idle, for: id)

        switch outcome {
        case .success(let result):
            recordResult(result, for: id)
            await applyRefresh(refresh, for: project)
            await notifyIfBackground(project: project, succeeded: true, summary: summary(result))
        case .failure(.nonZeroExit(let result)):
            recordResult(result, for: id)
            commandStates[id, default: .init()].lastErrorMessage =
                "Command failed with exit code \(result.exitCode)."
            await notifyIfBackground(project: project, succeeded: false, summary: summary(result))
        case .failure(.other(let error)):
            commandStates[id, default: .init()].lastErrorMessage = String(describing: error)
            await notifyIfBackground(project: project, succeeded: false, summary: "command failed")
        }
    }

    private enum MutationError: Error { case nonZeroExit(CommandResult), other(Error) }

    private func execute(_ operation: () async throws -> CommandResult) async -> Result<CommandResult, MutationError> {
        do { return .success(try await operation()) }
        catch CommandRunnerError.nonZeroExit(let result) { return .failure(.nonZeroExit(result)) }
        catch { return .failure(.other(error)) }
    }

    private func setActivity(_ activity: ProjectCommandState.Activity, for id: DDEVProject.ID) {
        commandStates[id, default: .init()].activity = activity
    }

    private func applyRefresh(_ scope: RefreshScope, for project: DDEVProject) async {
        switch scope {
        case .none: return
        case .fullList: await refreshProjectsFromDDEVInBackground()
        case .project: await reDescribe(project)
        }
    }

    /// Re-describe a single project and patch it into `projects` in place.
    private func reDescribe(_ project: DDEVProject) async {
        guard let refreshed = try? await ddevService.describe(projectName: project.name) else { return }
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = projects[index].applying(details: refreshed)
        if selectedProjectFallback?.id == project.id {
            selectedProjectFallback = projects[index]
        }
        try? projectCache.saveProjects(projects)
    }

    private func summary(_ result: CommandResult) -> String {
        let joined = result.arguments.joined(separator: " ")
        return joined.isEmpty ? result.executable : "\(result.executable) \(joined)"
    }

    private func notifyIfBackground(project: DDEVProject, succeeded: Bool, summary: String) async {
        guard project.id != selectedProjectID else { return }
        await notifier.notifyCommandFinished(projectName: project.name, summary: summary, succeeded: succeeded)
    }

    /// Records a per-project result + bounded history. `expandsOutput` mirrors the old
    /// `requestsOutputExpansion` default of `true` for mutations.
    private func recordResult(_ result: CommandResult, for id: DDEVProject.ID, expandsOutput: Bool = true) {
        var state = commandStates[id] ?? .init()
        state.lastResult = result
        state.history.append(CommandHistoryEntry(result: Self.bounded(result)))
        if state.history.count > Self.commandHistoryLimit {
            state.history.removeFirst(state.history.count - Self.commandHistoryLimit)
        }
        if expandsOutput { state.outputExpansionRequest += 1 }
        commandStates[id] = state
    }
```

- [ ] **Step 4: Point the lifecycle mutations at the new pipeline**

**Find** the `start`/`stop`/`restart` methods (currently lines ~264-280):

```swift
    public func start(_ project: DDEVProject) async {
        await runMutation(markingBusy: project) {
            try await self.ddevService.start(projectName: project.name)
        }
    }

    public func stop(_ project: DDEVProject) async {
        await runMutation(markingBusy: project) {
            try await self.ddevService.stop(projectName: project.name)
        }
    }

    public func restart(_ project: DDEVProject) async {
        await runMutation(markingBusy: project) {
            try await self.ddevService.restart(projectName: project.name)
        }
    }
```

**Replace with:**

```swift
    public func start(_ project: DDEVProject) async {
        await runProjectMutation(project) {
            try await self.ddevService.start(projectName: project.name)
        }
    }

    public func stop(_ project: DDEVProject) async {
        await runProjectMutation(project) {
            try await self.ddevService.stop(projectName: project.name)
        }
    }

    public func restart(_ project: DDEVProject) async {
        await runProjectMutation(project) {
            try await self.ddevService.restart(projectName: project.name)
        }
    }
```

- [ ] **Step 5: Convert the remaining selected-project mutations**

Each of these currently uses `runMutation { ... }` (no project) or a bespoke `runAndCapture`. Convert each to `runProjectMutation(selectedProject, refresh:)`. Apply these edits in `ProjectDashboardViewModel`:

**`unlinkSelectedProject` / `deleteSelectedDDEVData`** (currently ~297-309) — existence-changing, so `.fullList`:

```swift
    public func unlinkSelectedProject() async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .fullList) {
            try await self.ddevService.unlink(projectName: selectedProject.name)
        }
    }

    public func deleteSelectedDDEVData() async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .fullList) {
            try await self.ddevService.deleteDDEVData(projectName: selectedProject.name)
        }
    }
```

**`launchDatabaseTool`** (currently ~323-328) — launching a GUI changes no project state, so `.none`:

```swift
    public func launchDatabaseTool(_ tool: DDEVDatabaseTool) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .none) {
            try await self.ddevService.launchDatabaseTool(tool, in: selectedProject.appRoot)
        }
    }
```

**`importDatabase`** (currently ~335-340) — `.project`:

```swift
    public func importDatabase(_ options: DDEVDatabaseImportOptions) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.importDatabase(options, in: selectedProject.appRoot)
        }
    }
```

**`exportDatabase`** (currently ~342-349) — writes a file, changes nothing, `.none`:

```swift
    public func exportDatabase(_ options: DDEVDatabaseExportOptions) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .none) {
            try await self.ddevService.exportDatabase(options, in: selectedProject.appRoot)
        }
    }
```

**`restoreSnapshotForSelectedProject` / `restoreLatestSnapshotForSelectedProject`** (currently ~370-382) — `.project`:

```swift
    public func restoreSnapshotForSelectedProject(named snapshotName: String) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.restoreSnapshot(named: snapshotName, in: selectedProject.appRoot)
        }
    }

    public func restoreLatestSnapshotForSelectedProject() async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.restoreLatestSnapshot(in: selectedProject.appRoot)
        }
    }
```

**`enableXHGuiForSelectedProject`** (currently ~677-683) — `.project`:

```swift
    public func enableXHGuiForSelectedProject() async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.xhgui(.on, in: selectedProject.appRoot)
        }
    }
```

**`updateWordPressCore` / `updateWordPressPlugins` / `updateWordPressThemes`** (currently ~584-603) — `.project`:

```swift
    public func updateWordPressCore() async {
        guard let selectedProject, selectedProject.isWordPress else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.updateWordPressCore(in: selectedProject.appRoot)
        }
    }

    public func updateWordPressPlugins() async {
        guard let selectedProject, selectedProject.isWordPress else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.updateWordPressPlugins(in: selectedProject.appRoot)
        }
    }

    public func updateWordPressThemes() async {
        guard let selectedProject, selectedProject.isWordPress else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.updateWordPressThemes(in: selectedProject.appRoot)
        }
    }
```

**`runFrameworkCommandForSelectedProject`** (currently ~613-621) — `.project`:

```swift
    public func runFrameworkCommandForSelectedProject(_ command: DDEVFrameworkCommand) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.runProjectCommand(arguments: command.arguments, in: selectedProject.appRoot)
        }
    }
```

> The remaining special methods (`setPHPVersionForSelectedProject`, `applyConfigChangeForSelectedProject`, snapshot create/cleanup, the add-on install/remove, `configureProject`, `startProject(atFolder:)`) have extra follow-up logic (restart-after-php, snapshot-list refresh, restart-recommended flags). They are converted in Step 6.

- [ ] **Step 6: Convert the compound mutations that carry extra follow-up**

**`setPHPVersionForSelectedProject`** (currently ~244-258). It records two commands (config + optional restart) and refreshes. Rewrite to drive per-project state directly through the pipeline by composing inside one mutation operation, then re-describe once:

```swift
    public func setPHPVersionForSelectedProject(_ version: String) async {
        guard let selectedProject else { return }
        let id = selectedProject.id
        guard !isBusy(selectedProject) else { return }

        setActivity(.queued, for: id)
        await scheduler.acquire()
        setActivity(.running, for: id)

        let outcome = await execute {
            let configResult = try await self.ddevService.setPHPVersion(version, in: selectedProject.appRoot)
            self.recordResult(configResult, for: id)
            if selectedProject.status == .running {
                let restartResult = try await self.ddevService.restart(projectName: selectedProject.name)
                self.recordResult(restartResult, for: id)
                return restartResult
            }
            return configResult
        }
        scheduler.release()
        setActivity(.idle, for: id)

        switch outcome {
        case .success(let result):
            await reDescribe(selectedProject)
            await notifyIfBackground(project: selectedProject, succeeded: true, summary: summary(result))
        case .failure(.nonZeroExit(let result)):
            commandStates[id, default: .init()].lastErrorMessage = "Command failed with exit code \(result.exitCode)."
            await notifyIfBackground(project: selectedProject, succeeded: false, summary: summary(result))
        case .failure(.other(let error)):
            commandStates[id, default: .init()].lastErrorMessage = String(describing: error)
            await notifyIfBackground(project: selectedProject, succeeded: false, summary: "command failed")
        }
    }
```

**`applyConfigChangeForSelectedProject`** (currently ~470-479) — `.none` (no status change; a restart is only *recommended*), preserving the `projectConfigRestartRecommended` flag:

```swift
    public func applyConfigChangeForSelectedProject(_ change: DDEVConfigChange) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.applyConfigChange(change, in: selectedProject.appRoot)
            self.projectConfigRestartRecommended = selectedProject.status == .running
            return result
        }
    }
```

**`createSnapshotForSelectedProject` / `cleanupSnapshotsForSelectedProject` / `cleanupSnapshotForSelectedProject`** (currently ~360-402) — these are mutations whose follow-up is "refresh the snapshot list" (a read), not the project. Use `.none` and refresh snapshots inside the operation:

```swift
    public func createSnapshotForSelectedProject(name: String?) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.createSnapshot(name: name, in: selectedProject.appRoot)
            await self.refreshSnapshots(in: selectedProject.appRoot)
            return result
        }
    }

    public func cleanupSnapshotsForSelectedProject() async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.cleanupSnapshots(in: selectedProject.appRoot)
            await self.refreshSnapshots(in: selectedProject.appRoot)
            return result
        }
    }

    public func cleanupSnapshotForSelectedProject(named snapshotName: String) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.cleanupSnapshot(named: snapshotName, in: selectedProject.appRoot)
            await self.refreshSnapshots(in: selectedProject.appRoot)
            return result
        }
    }
```

**`installAddOnForSelectedProject` / `removeAddOnForSelectedProject`** (currently ~544-578) — `.none`, preserving the restart-recommended + addon-list refresh + `addonErrorMessage` mirroring:

```swift
    public func installAddOnForSelectedProject(_ repository: String) async {
        guard let selectedProject else { return }
        addonErrorMessage = nil
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.getAddOn(
                repository, projectName: selectedProject.name, in: selectedProject.appRoot)
            self.addOnRestartRecommended = true
            await self.refreshInstalledAddOns(in: selectedProject.appRoot, projectName: selectedProject.name)
            return result
        }
        addonErrorMessage = selectedProjectState.lastErrorMessage
    }

    public func removeAddOnForSelectedProject(named name: String) async {
        guard let selectedProject else { return }
        addonErrorMessage = nil
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.removeAddOn(
                named: name, projectName: selectedProject.name, in: selectedProject.appRoot)
            self.addOnRestartRecommended = true
            await self.refreshInstalledAddOns(in: selectedProject.appRoot, projectName: selectedProject.name)
            return result
        }
        addonErrorMessage = selectedProjectState.lastErrorMessage
    }
```

**`startProject(atFolder:)` / `configureProject(folder:…)`** (currently ~311-321) — these have **no project id yet** (a project is being created). They keep the global pipeline. Replace with global helpers (defined in Step 7):

```swift
    public func startProject(atFolder path: String) async {
        await runGlobalMutation {
            try await self.ddevService.startProject(in: path)
        }
    }

    public func configureProject(folder: String, name: String, type: DDEVProjectType, docroot: String) async {
        await runGlobalMutation {
            try await self.ddevService.configureProject(in: folder, name: name, type: type, docroot: docroot)
        }
    }
```

- [ ] **Step 7: Add the global pipeline for project-less operations**

The global list refresh and new-project creation use `isRunningGlobalCommand` + `globalErrorMessage`. Add these helpers to `ProjectDashboardViewModel` (place near `runProjectMutation`). Also update `refresh()` to use the global flag.

```swift
    /// Pipeline for operations with no single owning project (new-project creation).
    /// Always full-list refreshes afterward.
    private func runGlobalMutation(_ operation: @escaping () async throws -> CommandResult) async {
        isRunningGlobalCommand = true
        globalErrorMessage = nil
        defer { isRunningGlobalCommand = false }
        do {
            _ = try await operation()
            try await refreshProjectsFromDDEV()
        } catch CommandRunnerError.nonZeroExit(let result) {
            globalErrorMessage = "Command failed with exit code \(result.exitCode)."
            _ = result
        } catch {
            globalErrorMessage = String(describing: error)
        }
    }
```

Update `refresh()` (currently ~227-232) to use the global flag instead of the removed `runAndCapture`:

```swift
    public func refresh() async {
        isRunningGlobalCommand = true
        globalErrorMessage = nil
        defer { isRunningGlobalCommand = false }
        do {
            try await refreshProjectsFromDDEV()
        } catch {
            globalErrorMessage = String(describing: error)
        }
    }
```

> `refreshProjectsFromDDEVInBackground()` (used by `.fullList`) already swallows errors and does not touch the global flag — leave it as is.

- [ ] **Step 8: Convert reads to per-project state (logs/config/addons/snapshots-list)**

These currently set the global `isRunningCommand` and write `lastErrorMessage`/`recordCommandResult`. Convert them to a small read helper that marks `isReadingData` on the selected project and records into per-project state. Add the helper:

```swift
    /// Pipeline for a *read* on the selected project: sets `isReadingData`, records the
    /// result into per-project state, never blocks lifecycle, never notifies, never caps.
    private func runSelectedProjectRead(
        recordOutput: Bool = false,
        _ operation: @escaping () async throws -> CommandResult?
    ) async {
        guard let id = selectedProjectID else { return }
        commandStates[id, default: .init()].isReadingData = true
        commandStates[id, default: .init()].lastErrorMessage = nil
        defer { commandStates[id, default: .init()].isReadingData = false }
        do {
            if let result = try await operation(), recordOutput {
                recordResult(result, for: id, expandsOutput: false)
            }
        } catch CommandRunnerError.nonZeroExit(let result) {
            recordResult(result, for: id, expandsOutput: false)
            commandStates[id, default: .init()].lastErrorMessage = "Command failed with exit code \(result.exitCode)."
        } catch {
            commandStates[id, default: .init()].lastErrorMessage = String(describing: error)
        }
    }
```

Now rewrite the read methods. **`loadLogsForSelectedProject`** (currently ~404-433):

```swift
    public func loadLogsForSelectedProject(_ request: DDEVLogRequest) async {
        guard let selectedProject else { return }
        projectLogsErrorMessage = nil
        await runSelectedProjectRead(recordOutput: true) {
            do {
                let result = try await self.ddevService.logs(
                    projectName: selectedProject.name,
                    service: request.service.rawValue,
                    tail: request.tailCount,
                    includeTimestamps: request.includeTimestamps,
                    in: selectedProject.appRoot
                )
                self.projectLogsResult = result
                return result
            } catch CommandRunnerError.nonZeroExit(let result) {
                self.projectLogsResult = result
                self.projectLogsErrorMessage = "Command failed with exit code \(result.exitCode)."
                throw CommandRunnerError.nonZeroExit(result)
            }
        }
        if projectLogsErrorMessage == nil { projectLogsErrorMessage = selectedProjectState.lastErrorMessage }
    }
```

**`loadConfigForSelectedProject`** (currently ~446-468):

```swift
    public func loadConfigForSelectedProject() async {
        guard let selectedProject else { return }
        projectConfigErrorMessage = nil
        projectConfig = nil
        await runSelectedProjectRead {
            do {
                let result = try await self.ddevService.utilityConfigYAML(omitKeys: ["web_environment"], in: selectedProject.appRoot)
                self.projectConfig = try DDEVConfig.parseYAML(result.stdout)
                return nil
            } catch CommandRunnerError.nonZeroExit(let result) {
                self.projectConfigErrorMessage = result.stderr.nilIfBlank ?? "Command failed with exit code \(result.exitCode)."
                throw CommandRunnerError.nonZeroExit(result)
            }
        }
    }
```

**`loadInstalledAddOnsForSelectedProject`** (currently ~485-510) and **`searchAddOnsForSelectedProject`** (currently ~512-542): wrap their bodies in `runSelectedProjectRead`, replacing `isRunningCommand = true`/`defer { isRunningCommand = false }` with the helper and writing `addonErrorMessage` from the caught error. Pattern (apply to both, keeping each method's existing parse logic):

```swift
    public func loadInstalledAddOnsForSelectedProject() async {
        guard let selectedProject else { return }
        addonErrorMessage = nil
        await runSelectedProjectRead {
            do {
                let result = try await self.ddevService.listInstalledAddOns(
                    projectName: selectedProject.name, in: selectedProject.appRoot)
                self.installedAddOns = try DDEVAddon.parseListOutput(result.stdout)
                self.addonRawOutput = self.installedAddOns.isEmpty ? result.stdout.nilIfBlank : nil
                return nil
            } catch CommandRunnerError.nonZeroExit(let result) {
                self.addonErrorMessage = "Command failed with exit code \(result.exitCode)."
                throw CommandRunnerError.nonZeroExit(result)
            }
        }
    }
```

```swift
    public func searchAddOnsForSelectedProject(query: String) async {
        guard let selectedProject else { return }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            addonSearchResults = DDEVAddon.recommendedOfficial
            addonErrorMessage = nil
            return
        }
        addonErrorMessage = nil
        await runSelectedProjectRead {
            do {
                let result = try await self.ddevService.searchAddOns(query: trimmedQuery, in: selectedProject.appRoot)
                let parsedResults = try DDEVAddon.parseListOutput(result.stdout)
                self.addonSearchResults = parsedResults.isEmpty ? DDEVAddon.recommendedOfficial : parsedResults
                self.addonRawOutput = parsedResults.isEmpty ? result.stdout.nilIfBlank : nil
                return nil
            } catch CommandRunnerError.nonZeroExit(let result) {
                self.addonErrorMessage = "Command failed with exit code \(result.exitCode)."
                throw CommandRunnerError.nonZeroExit(result)
            }
        }
    }
```

**`loadSnapshotsForSelectedProject`** (currently ~351-358):

```swift
    public func loadSnapshotsForSelectedProject() async {
        guard let selectedProject else { return }
        await runSelectedProjectRead {
            let result = try await self.ddevService.listSnapshots(in: selectedProject.appRoot)
            self.snapshots = DDEVSnapshot.parseListOutput(result.stdout)
            return nil
        }
    }
```

- [ ] **Step 9: Point diagnostics at the global flag**

`runDiagnostics` (currently ~732-761) sets `isRunningCommand`. Global diagnostics is project-less; project diagnostics is a selected-project read. Simplest faithful change: keep `runDiagnostics` but swap its flag to `isRunningGlobalCommand`, and record each entry's result into the relevant per-project history only when a project is selected. Minimal change — replace the two `isRunningCommand` lines and the `recordCommandResult` calls:

In `runDiagnostics`, replace `isRunningCommand = true` → `isRunningGlobalCommand = true`, `defer { isRunningCommand = false }` → `defer { isRunningGlobalCommand = false }`. Replace each `recordCommandResult($0.result, requestsOutputExpansion: false)` / `recordCommandResult(result, requestsOutputExpansion: false)` with a no-op for now (the diagnostics report itself shows the output; diagnostics output no longer needs to live in command history). Delete those `recordCommandResult(...)` calls.

- [ ] **Step 10: Run the concurrency tests**

Run: `swift test --filter ProjectConcurrencyTests`
Expected: PASS (6 tests). If `reDescribe` ordering causes `testStateChangingMutationReDescribesOnlyThatProject` to also see a cache write, note the assertion only checks `service.commands` (cache is a different collaborator) — it should read exactly `["stop:agilebugs", "describe:agilebugs"]`.

- [ ] **Step 11: Commit (Tasks 4–6 land together)**

```bash
swift build
git add Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Tests/DDEVUIAppTests/ProjectConcurrencyTests.swift
git commit -m "feat(concurrency): per-project mutation pipeline with cap, re-describe, and notifications"
```

> If `swift build` still fails here, the failures are in the **views** (Task 7) referencing removed fields. That is expected — the views are converted next and the full suite runs at the end of Task 8. Commit the VM + concurrency tests now regardless (the VM compiles on its own; view files are separate compilation inputs in the same module, so the module won't fully build until Task 7). If your toolchain blocks the commit because the module doesn't link, fold Task 7 into this commit.

---

## Task 7: View migration

Swap every `.disabled(viewModel.isRunningCommand)` and every per-project display read to the new accessors. Mechanical but exact. Each location below lists the **find** expression and the **replacement**.

**Files & edits:**

- [ ] **Step 1: `ProjectListView.swift`**

- Row action button gating — line ~167: `.disabled(viewModel.isRunningCommand)` → `.disabled(viewModel.isBusy(project))`.
- Queued treatment — in `actionControls` (lines ~131-152), replace the `if viewModel.isBusy(project)` branch with a queued/running distinction:

```swift
    @ViewBuilder
    private var actionControls: some View {
        if viewModel.isBusy(project) {
            ProgressView()
                .controlSize(.small)
                .help(viewModel.isQueued(project) ? "Queued" : "Running")
                .opacity(viewModel.isQueued(project) ? 0.5 : 1)
        } else {
            // (unchanged start/stop/restart buttons)
            ...
        }
    }
```

- Empty-state error — line ~51: `if let errorMessage = viewModel.lastErrorMessage, viewModel.projects.isEmpty {` → `if let errorMessage = viewModel.globalErrorMessage, viewModel.projects.isEmpty {`.

- [ ] **Step 2: `ProjectInspectorView.swift`**

- Lifecycle gating — lines ~77, ~281, ~456, ~488: `.disabled(viewModel.isRunningCommand)` → `.disabled(viewModel.isSelectedProjectBusy)`.
- `onChange` of expansion — line ~114: `.onChange(of: viewModel.commandOutputExpansionRequest) { _, requestCount in` → `.onChange(of: viewModel.selectedProjectState.outputExpansionRequest) { _, requestCount in`.
- `LogsTabContent.hasAnyActivity` — lines ~576-580:

```swift
        let hasAnyActivity =
            viewModel.selectedProjectState.lastResult != nil ||
            viewModel.selectedProjectState.lastErrorMessage != nil ||
            viewModel.isSelectedProjectBusy ||
            !viewModel.selectedProjectState.history.isEmpty
```

- `commandHistorySection` — lines ~598-617: replace each field:
  - `viewModel.commandHistory.count > 1` → `viewModel.selectedProjectState.history.count > 1`
  - the spinner condition `if viewModel.isRunningCommand {` → `if viewModel.isSelectedProjectBusy {`
  - `else if viewModel.lastErrorMessage != nil {` → `else if viewModel.selectedProjectState.lastErrorMessage != nil {`
  - `else if let result = viewModel.lastCommandResult {` → `else if let result = viewModel.selectedProjectState.lastResult {`
  - `result: viewModel.lastCommandResult,` → `result: viewModel.selectedProjectState.lastResult,`
  - `history: viewModel.commandHistory,` → `history: viewModel.selectedProjectState.history,`
  - `errorMessage: viewModel.lastErrorMessage` → `errorMessage: viewModel.selectedProjectState.lastErrorMessage`

- [ ] **Step 3: `ProjectConfigEditorView.swift`**

- Line ~84: `} else if loadedConfig == nil || viewModel.isRunningCommand && viewModel.projectConfig == nil {` → `} else if loadedConfig == nil || viewModel.isSelectedProjectBusy && viewModel.projectConfig == nil {`
- Line ~134: `.disabled(viewModel.isRunningCommand)` → `.disabled(viewModel.isSelectedProjectBusy)`
- Line ~262: `if let result = viewModel.lastCommandResult, result.arguments.first == "config" {` → `if let result = viewModel.selectedProjectState.lastResult, result.arguments.first == "config" {`
- Line ~315: `.disabled(!hasChanges || viewModel.isRunningCommand)` → `.disabled(!hasChanges || viewModel.isSelectedProjectBusy)`
- Line ~323: `if viewModel.lastErrorMessage == nil, let updatedConfig = draftConfig {` → `if viewModel.selectedProjectState.lastErrorMessage == nil, let updatedConfig = draftConfig {`

- [ ] **Step 4: Remaining selected-project sub-views — swap `.disabled(viewModel.isRunningCommand)` → `.disabled(viewModel.isSelectedProjectBusy)`**

Exact locations:
- `LogsViewerView.swift`: line ~60. Also line ~74 `if viewModel.isRunningCommand {` → `if viewModel.selectedProjectState.isReadingData {`; line ~103 `project.status == .running && !viewModel.isRunningCommand` → `project.status == .running && !viewModel.selectedProjectState.isReadingData`.
- `SnapshotManagerView.swift`: lines ~28, ~44, ~51, ~58, ~160.
- `DatabaseOperationsView.swift`: line ~40.
- `AddonManagerView.swift`: lines ~26, ~73, ~125, ~166, ~188 (`viewModel.isRunningCommand` inside the `actionDisabled:` expression).
- `FrameworkCommandLauncherView.swift`: line ~49.

- [ ] **Step 5: `DiagnosticsView.swift` and `ContentView.swift` — global flag**

Diagnostics and the toolbar refresh are project-less:
- `DiagnosticsView.swift`: lines ~91, ~125: `.disabled(viewModel.isRunningCommand)` → `.disabled(viewModel.isRunningGlobalCommand)`.
- `ContentView.swift`: line ~59 `if viewModel.isRunningCommand {` → `if viewModel.isRunningGlobalCommand {`; line ~66 `.disabled(viewModel.isRunningCommand)` → `.disabled(viewModel.isRunningGlobalCommand)`.

- [ ] **Step 6: Build**

Run: `swift build`
Expected: builds clean. If any `isRunningCommand` / `lastCommandResult` / `lastErrorMessage` / `commandHistory` / `commandOutputExpansionRequest` / `busyProjectIDs` reference remains, the compiler names the file and line — fix per the rules above. Confirm none remain:

Run: `grep -rn "isRunningCommand\|busyProjectIDs\|\.lastCommandResult\|\.commandHistory\|commandOutputExpansionRequest" Sources/`
Expected: no matches (every `lastErrorMessage` left should be `projectLogsErrorMessage`/`projectConfigErrorMessage`/`addonErrorMessage`/`diagnosticsErrorMessage`/`globalErrorMessage` — verify none are the bare removed `viewModel.lastErrorMessage`).

- [ ] **Step 7: Commit**

```bash
git add Sources/DDEVUIApp/Views/
git commit -m "refactor(views): gate controls on per-project state instead of the global flag"
```

---

## Task 8: Wire notifications into the app + migrate the existing test suite

- [ ] **Step 1: Inject the real notifier and request authorization on launch**

In `Sources/DDEVUIApp/Views/ContentView.swift` line ~4, build the VM with the real notifier and keep a handle to activate foreground presentation. Replace:

```swift
    @StateObject private var viewModel = ProjectDashboardViewModel()
```

with:

```swift
    @StateObject private var viewModel = ProjectDashboardViewModel(
        notifier: ContentView.makeNotifier()
    )

    private static func makeNotifier() -> NotificationScheduling {
        let scheduler = UserNotificationScheduler()
        scheduler.activateForegroundPresentation()
        return scheduler
    }
```

`ContentView.body` is a `NavigationSplitView` that already has a `.task` calling `loadCachedProjectsThenRefresh()`. Extend that existing task — **find**:

```swift
        .task {
            await viewModel.loadCachedProjectsThenRefresh()
        }
```

**Replace with:**

```swift
        .task {
            await viewModel.requestNotificationAuthorization()
            await viewModel.loadCachedProjectsThenRefresh()
        }
```

Add the forwarding method to `ProjectDashboardViewModel`:

```swift
    public func requestNotificationAuthorization() async {
        await notifier.requestAuthorizationIfNeeded()
    }
```

- [ ] **Step 2: Migrate `ProjectDashboardViewModelTests.swift`**

The existing assertions reference removed fields and the old global-refresh behaviour. Apply these rules across the file:

- `viewModel.isRunningCommand` → `viewModel.isRunningGlobalCommand` (used in `testBackgroundRefreshFailure…` line 96 and `testInitialRefreshFailure…` line 108 — both are about `refresh()`, which is global).
- `viewModel.lastErrorMessage` after `refresh()` failures (lines 95, 107) → `viewModel.globalErrorMessage`.
- `viewModel.lastCommandResult` after a **mutation** → `viewModel.selectedProjectState.lastResult` (when the mutation targets the selected project) or `viewModel.state(for: "<name>").lastResult`.
- `viewModel.commandHistory` → `viewModel.selectedProjectState.history`.
- `viewModel.commandOutputExpansionRequest` → `viewModel.selectedProjectState.outputExpansionRequest`.
- **Command-sequence expectations:** for every state-changing mutation on the selected project, drop the `"list"` element and keep only the trailing `"describe:<name>"`. Concretely:
  - line 137 `["start:aqua-pura", "list", "describe:aqua-pura"]` → `["start:aqua-pura", "describe:aqua-pura"]`
  - lines 161-165 / 190-194 (`launchDatabaseTool`/`launchDefaultDatabaseTool`, now `.none`) → just `["db:tableplus:/…/aqua-pura"]` (no `list`/`describe`).
  - lines 240-250 (`updateWordPress*`) → each block becomes `["wp-core:/…","describe:aqua-pura","wp-plugins:/…","describe:aqua-pura","wp-themes:/…","describe:aqua-pura"]`.
  - lines 319-324 (`setPHPVersion`, running project restarts) → `["php:8.3:/…", "restart:aqua-pura", "describe:aqua-pura"]`.
  - lines 348-352 (`setPHPVersion`, paused project, no restart) → `["php:8.2:/…", "describe:agilebugs"]`.
  - lines 368-372 (`importDatabase`) → `["import:…", "describe:aqua-pura"]`.
  - lines 391-392 (`exportDatabase`, `.none`) → unchanged (already just `["export:…"]`).
  - lines 494-498 (`restoreSnapshot`) → `["snapshot-restore:/…:before-upgrade", "describe:aqua-pura"]`.
  - lines 511-515 (`restoreLatestSnapshot`) → `["snapshot-restore-latest:/…", "describe:aqua-pura"]`.
  - lines 788-792 (`enableXHGui`) → `["xhgui:/…:on", "describe:aqua-pura"]`.
  - line 295 (`deleteDDEVData`, `.fullList`) → unchanged `["delete:aqua-pura", "list", "describe:aqua-pura"]`.
  - line 309 (`configureProject`, global) → unchanged `["config:/Users/dave/new-site:new-site:wordpress:web", "list"]`.
  - snapshot create/cleanup (lines 478-481, 526-530, 540-543) → unchanged: the snapshot create/cleanup is `.none` and still calls `snapshot-list` inside the operation, so the sequence is `["snapshot:…", "snapshot-list:…"]` etc. (no `describe`).
  - line 562 / 561 (`loadLogs`, a read) → `commandHistory` becomes `selectedProjectState.history`; expansion stays 0.
- `testStartSelectedProjectRefreshesAfterCommand` and similar names that say "RefreshesAfterCommand": the behaviour is now per-project re-describe; keep the test name or rename to `…ReDescribesAfterCommand` for clarity (optional).

> This is the bulk of the migration. Work method-by-method, running `swift test --filter ProjectDashboardViewModelTests/<methodName>` after each to converge.

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: PASS — all targets including `CommandSchedulerTests`, `ProjectConcurrencyTests`, and the migrated `ProjectDashboardViewModelTests`.

- [ ] **Step 4: Commit**

```bash
git add Sources/DDEVUIApp/Views/ContentView.swift Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "feat(notifications): wire UserNotificationScheduler into the app and migrate VM tests"
```

---

## Task 9: Manual verification

Native notifications only work in the bundled app, so this must be done in Xcode, not `swift run`.

- [ ] **Step 1:** Open `DDEVUI.xcodeproj` in Xcode and Run. Approve the notification permission prompt on first launch.
- [ ] **Step 2:** With at least two real DDEV projects: click **Start** on project A, then immediately **Start/Stop** on project B. Confirm B's button is active while A is running (no global freeze) and both rows show their own spinners.
- [ ] **Step 3:** Select project A. Trigger a command on project B (not selected). Confirm a macOS notification appears for B on completion, and none appears for commands on the selected A.
- [ ] **Step 4:** Lower the cap temporarily (`CommandScheduler(maxConcurrent: 1)` in `ContentView.makeNotifier`'s sibling — or pass `scheduler:` in the VM init) and start three projects; confirm the third shows the dimmed "Queued" spinner until a slot frees. Revert the cap to 3.
- [ ] **Step 5:** Confirm `swift build && swift test` is green (the unbundled executable path — notifications no-op, no crash).
- [ ] **Step 6 (optional):** `git push -u origin feat/per-project-concurrency` and open a PR if desired.

---

## Self-review notes (author)

- **Spec coverage:** state model → Task 3/4; scheduler (cap+FIFO queue) → Task 1 + Task 5 (`runProjectMutation` queued/running + cap test); reads uncapped/no-notify → Task 5 Step 8 (`runSelectedProjectRead`); notifications (all mutations, background only, success+failure, bundle-safe, foreground banner) → Task 2 + Task 5 + Task 8; per-project re-describe vs full-list refresh → Task 5 `RefreshScope`; view migration → Task 7; test migration → Task 8.
- **Known sharp edges flagged inline:** the Tasks 4–6 non-building stretch (commit boundary note) — this is the riskiest part of execution and may need folding into one commit.
- **Deviation from "29 references":** the real test migration is larger because the refresh-strategy change rewrites ~10 command-sequence expectations on top of the field renames. Enumerated explicitly in Task 8 Step 2 so there are no surprises.
