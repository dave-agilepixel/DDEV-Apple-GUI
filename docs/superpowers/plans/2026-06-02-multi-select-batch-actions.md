# Multi-Select Batch Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user shift/cmd-click to multi-select projects in the list, then Start/Stop just the selected subset — in the Projects list and inside a group.

**Architecture:** Bind the existing `List` to a `Set<DDEVProject.ID>` (native macOS range/toggle selection). `selectedProjectID` becomes a computed facade over that set so the inspector and quick switcher are untouched. The existing B3 "Start All / Stop All" bar re-scopes to the selection when 2+ are picked (relabelling to "… Selected (N)"); the right-column inspector shows a "N selected" summary instead of per-project detail. Batch actions act on selection ∩ currently-visible projects.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftPM (`swift test`), `@Observable` view model, XCTest. Target platform macOS 26.

**Spec:** `docs/superpowers/specs/2026-06-02-multi-select-batch-actions-design.md`

---

## File Structure

- **Modify** `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
  - Add `selectedProjectIDs: Set<DDEVProject.ID>` (the new selection source of truth + recency `didSet`).
  - Convert `selectedProjectID` to a computed facade over the set.
  - Add `isMultiSelecting` and `batchScopeProjects`; redefine `startableProjectsInCurrentView` / `stoppableProjectsInCurrentView` over the scope.
  - Prune the selection set to live ids in `applyProjects(_:)`.
- **Modify** `Sources/DDEVUIApp/Views/ProjectListView.swift`
  - Bind `List(selection:)` to `$viewModel.selectedProjectIDs` (remove the single-ID `projectSelection` binding).
  - Re-scope the `batchBar` labels via `isMultiSelecting`.
- **Create** `Sources/DDEVUIApp/Views/MultiSelectionSummaryView.swift`
  - The "N selected" detail-pane summary with scoped Start/Stop + Clear Selection.
- **Modify** `Sources/DDEVUIApp/Views/ContentView.swift`
  - Branch the `detail:` column on `selectedProjectIDs.count >= 2`.
- **Modify** `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`
  - New unit tests for the facade, recency, scope, and refresh pruning.

Run all tests with: `swift test`
Run only the view-model suite with: `swift test --filter ProjectDashboardViewModelTests`

---

## Task 1: Selection set + `selectedProjectID` facade

**Files:**
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift:130-135` (the stored `selectedProjectID`)
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Add these two tests to `ProjectDashboardViewModelTests` (anywhere among the existing `func test…` methods, e.g. after `testRevealAndSelectProjectJumpsToProjectsSection`):

```swift
func testSelectedProjectIDFacadeMapsToTheSelectionSet() {
    let viewModel = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []))

    viewModel.selectedProjectID = "aqua-pura"
    XCTAssertEqual(viewModel.selectedProjectIDs, ["aqua-pura"])
    XCTAssertEqual(viewModel.selectedProjectID, "aqua-pura")
    XCTAssertFalse(viewModel.isMultiSelecting)

    // A 2+ selection has no single "focused" id (the inspector falls back to the summary).
    viewModel.selectedProjectIDs = ["aqua-pura", "agilebugs"]
    XCTAssertNil(viewModel.selectedProjectID)
    XCTAssertTrue(viewModel.isMultiSelecting)

    viewModel.selectedProjectID = nil
    XCTAssertTrue(viewModel.selectedProjectIDs.isEmpty)
    XCTAssertFalse(viewModel.isMultiSelecting)
}

func testSettlingOnASingleSelectionRecordsRecency() {
    let viewModel = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []))

    viewModel.selectedProjectIDs = ["aqua-pura"]
    XCTAssertEqual(viewModel.recentProjectIDs.first, "aqua-pura")

    // A 2+ selection records nothing new.
    viewModel.selectedProjectIDs = ["aqua-pura", "agilebugs"]
    XCTAssertEqual(viewModel.recentProjectIDs, ["aqua-pura"])
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: compile failure — `value of type 'ProjectDashboardViewModel' has no member 'selectedProjectIDs'` (and `isMultiSelecting`).

- [ ] **Step 3: Replace the stored `selectedProjectID` with a set + facade**

In `ProjectDashboardViewModel.swift`, replace the current stored property (lines ~130-135):

```swift
    public var selectedProjectID: DDEVProject.ID? {
        didSet {
            // Track recency for the "Recently Used" sort (B5). Session-scoped — resets on relaunch.
            if let id = selectedProjectID, oldValue != id { recordRecentProject(id) }
        }
    }
```

with:

```swift
    /// The list selection (the source of truth, bound directly to `List(selection:)`). Supports
    /// shift-click range and cmd-click toggle natively on macOS. Single-selection callers use the
    /// `selectedProjectID` facade below.
    public var selectedProjectIDs: Set<DDEVProject.ID> = [] {
        didSet {
            // Track recency for "Recently Used" (B5) only when the selection settles on one project;
            // a multi-selection has no single focused project. `recordRecentProject` is idempotent
            // (moves the id to the front), so a repeat is harmless. Session-scoped — resets on relaunch.
            if selectedProjectIDs.count == 1, let id = selectedProjectIDs.first, oldValue != selectedProjectIDs {
                recordRecentProject(id)
            }
        }
    }

    /// Single-selection facade over `selectedProjectIDs`, kept for the inspector, the quick switcher
    /// (B6), `selectedProject`, and the per-project read/mutation guards. One selected → that id;
    /// zero or 2+ selected → nil.
    public var selectedProjectID: DDEVProject.ID? {
        get { selectedProjectIDs.count == 1 ? selectedProjectIDs.first : nil }
        set { selectedProjectIDs = newValue.map { [$0] } ?? [] }
    }

    /// True when 2+ projects are selected — the bottom bar and detail pane switch into selection mode.
    public var isMultiSelecting: Bool { selectedProjectIDs.count >= 2 }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: PASS. The pre-existing `testRevealAndSelectProjectJumpsToProjectsSection` (asserts `selectedProjectID == "aqua-pura"`) and all other selection-dependent tests must still pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "feat: add Set-based project selection with selectedProjectID facade"
```

---

## Task 2: Batch scope over selection ∩ visible

**Files:**
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift:517-525` (the B3 startable/stoppable computeds)
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Add these three tests to `ProjectDashboardViewModelTests` (e.g. just after the existing `testStopProjectsInCurrentViewStopsOnlyRunningOnes`):

```swift
func testBatchScopeIsWholeViewWhenNotMultiSelecting() async {
    let running = DDEVProject.sampleWordPress                    // aqua-pura, running
    let stopped = DDEVProject.sampleLaravel.withStatus(.stopped) // agilebugs, stopped
    let viewModel = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: [running, stopped]))
    await viewModel.refresh() // auto-selects the first project → single selection, not multi

    XCTAssertFalse(viewModel.isMultiSelecting)
    XCTAssertEqual(Set(viewModel.batchScopeProjects.map(\.id)), ["aqua-pura", "agilebugs"])
    XCTAssertEqual(viewModel.startableProjectsInCurrentView.map(\.id), ["agilebugs"])
    XCTAssertEqual(viewModel.stoppableProjectsInCurrentView.map(\.id), ["aqua-pura"])
}

func testBatchScopeIsTheSelectedSubsetWhenMultiSelecting() {
    let running = DDEVProject.sampleWordPress                    // aqua-pura, running
    let stopped = DDEVProject.sampleLaravel.withStatus(.stopped) // agilebugs, stopped
    let extra = DDEVProject.sampleDrupal                         // drupal-demo, running (excluded)
    let viewModel = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []))
    viewModel.projects = [running, stopped, extra]

    viewModel.selectedProjectIDs = ["aqua-pura", "agilebugs"] // exclude drupal-demo
    XCTAssertTrue(viewModel.isMultiSelecting)
    XCTAssertEqual(Set(viewModel.batchScopeProjects.map(\.id)), ["aqua-pura", "agilebugs"])
    XCTAssertEqual(viewModel.startableProjectsInCurrentView.map(\.id), ["agilebugs"])
    XCTAssertEqual(viewModel.stoppableProjectsInCurrentView.map(\.id), ["aqua-pura"])
}

func testBatchScopeExcludesSelectedProjectsHiddenBySearch() {
    let viewModel = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []))
    viewModel.projects = [.sampleWordPress, .sampleLaravel] // aqua-pura, agilebugs

    viewModel.selectedProjectIDs = ["aqua-pura", "agilebugs"]
    viewModel.searchText = "aqua" // hides agilebugs from the view

    XCTAssertTrue(viewModel.isMultiSelecting)
    XCTAssertEqual(viewModel.batchScopeProjects.map(\.id), ["aqua-pura"],
                   "A selected project hidden by search is never acted on")
}

func testBatchStartOverMultiSelectionStartsOnlySelectedStoppedProjects() async {
    let running = DDEVProject.sampleWordPress                             // aqua-pura, running (selected)
    let selectedStopped = DDEVProject.sampleLaravel.withStatus(.stopped)  // agilebugs, stopped (selected)
    let unselectedStopped = DDEVProject.sampleDrupal.withStatus(.stopped) // drupal-demo, stopped (NOT selected)
    let service = FakeDDEVService(projects: [running, selectedStopped, unselectedStopped])
    let viewModel = ProjectDashboardViewModel(ddevService: service)
    await viewModel.refresh()

    viewModel.selectedProjectIDs = ["aqua-pura", "agilebugs"] // exclude drupal-demo
    await viewModel.startProjectsInCurrentView()

    let commands = service.commands
    XCTAssertTrue(commands.contains("start:agilebugs"), "Selected stopped project is started")
    XCTAssertFalse(commands.contains("start:drupal-demo"), "Unselected project is left alone")
    XCTAssertFalse(commands.contains("start:aqua-pura"), "Already-running selected project is left alone")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: compile failure — no member `batchScopeProjects`.

- [ ] **Step 3: Add `batchScopeProjects` and re-scope the startable/stoppable computeds**

In `ProjectDashboardViewModel.swift`, replace the current B3 computeds (lines ~517-525):

```swift
    /// Projects in the current view that aren't running (candidates for a batch start).
    public var startableProjectsInCurrentView: [DDEVProject] {
        filteredProjects.filter { $0.status != .running }
    }

    /// Projects in the current view that are running (candidates for a batch stop).
    public var stoppableProjectsInCurrentView: [DDEVProject] {
        filteredProjects.filter { $0.status == .running }
    }
```

with:

```swift
    /// The set of projects a batch action operates on. When 2+ are selected this is the selection,
    /// intersected with the currently-visible (filtered) projects and kept in visible order — so a
    /// stale search filter can't make a batch touch a project the user can't see. Otherwise it's the
    /// whole current view (the original B3 behaviour).
    public var batchScopeProjects: [DDEVProject] {
        guard isMultiSelecting else { return filteredProjects }
        return filteredProjects.filter { selectedProjectIDs.contains($0.id) }
    }

    /// Projects in the batch scope that aren't running (candidates for a batch start).
    public var startableProjectsInCurrentView: [DDEVProject] {
        batchScopeProjects.filter { $0.status != .running }
    }

    /// Projects in the batch scope that are running (candidates for a batch stop).
    public var stoppableProjectsInCurrentView: [DDEVProject] {
        batchScopeProjects.filter { $0.status == .running }
    }
```

(`startProjectsInCurrentView()` / `stopProjectsInCurrentView()` are unchanged — they already fan out over `startableProjectsInCurrentView` / `stoppableProjectsInCurrentView` through the scheduler-gated `runBatch`.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: PASS — including the pre-existing `testStartProjectsInCurrentViewStartsOnlyStoppedOnes` and `testStopProjectsInCurrentViewStopsOnlyRunningOnes` (those refresh to a single selection, so `batchScopeProjects == filteredProjects`).

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "feat: scope batch start/stop to multi-selection intersected with the visible list"
```

---

## Task 3: Prune the selection on refresh

**Files:**
- Modify: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift:1611` + `:1686-1692` (give `FakeDDEVService` a mutable project list)
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift:1640-1647` (the selection reconciliation tail of `applyProjects(_:)`)
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

- [ ] **Step 1: Give `FakeDDEVService` a mutable project list (test seam)**

The fake currently returns a fixed `private let loadedProjects` from `listProjects()`, so a project can't appear/disappear between refreshes. Make it mutable and lock-guarded (it's `@unchecked Sendable`).

Change the declaration (line ~1611) from:

```swift
    private let loadedProjects: [DDEVProject]
```

to:

```swift
    private var loadedProjects: [DDEVProject]
```

Change `listProjects()` (line ~1691) from:

```swift
        return loadedProjects
```

to:

```swift
        return lock.withLock { loadedProjects }
```

Add this method just below `listProjects()`:

```swift
    /// Test seam: change the list returned by the next `listProjects()` (simulates a project
    /// appearing or disappearing between refreshes).
    func setProjects(_ projects: [DDEVProject]) {
        lock.withLock { loadedProjects = projects }
    }
```

(`init` already assigns `self.loadedProjects = projects`, which is still valid for a `var`.)

- [ ] **Step 2: Write the failing tests**

Add these tests to `ProjectDashboardViewModelTests`:

```swift
func testRefreshPrunesSelectionToLiveProjects() async {
    // First refresh sees two projects; the user multi-selects both.
    let service = FakeDDEVService(projects: [.sampleWordPress, .sampleLaravel])
    let viewModel = ProjectDashboardViewModel(ddevService: service)
    await viewModel.refresh()
    viewModel.selectedProjectIDs = ["aqua-pura", "agilebugs"]

    // A later refresh no longer lists agilebugs — it must drop out of the selection.
    service.setProjects([.sampleWordPress])
    await viewModel.refresh()

    XCTAssertEqual(viewModel.selectedProjectIDs, ["aqua-pura"])
}

func testRefreshThatEmptiesSelectionFallsBackToFirstVisibleProject() async {
    let service = FakeDDEVService(projects: [.sampleWordPress, .sampleLaravel])
    let viewModel = ProjectDashboardViewModel(ddevService: service)
    await viewModel.refresh()
    viewModel.selectedProjectIDs = ["agilebugs"]

    // agilebugs disappears entirely — selection empties, so fall back to the first visible project.
    service.setProjects([.sampleWordPress])
    await viewModel.refresh()

    XCTAssertEqual(viewModel.selectedProjectID, "aqua-pura")
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: `testRefreshPrunesSelectionToLiveProjects` FAILS — the stale `agilebugs` id lingers in `selectedProjectIDs` (`["aqua-pura", "agilebugs"]` ≠ `["aqua-pura"]`).

- [ ] **Step 4: Prune the selection set in `applyProjects(_:)`**

In `ProjectDashboardViewModel.swift`, replace the selection-reconciliation tail of `applyProjects(_:)` (lines ~1640-1647):

```swift
        if let selectedProjectID,
           let selectedProject = projects.first(where: { $0.id == selectedProjectID }) {
            selectedProjectFallback = selectedProject
        } else {
            let fallbackProject = filteredProjects(in: projects).first ?? projects.first
            selectedProjectID = fallbackProject?.id
            selectedProjectFallback = fallbackProject
        }
```

with:

```swift
        // Prune the multi-selection to projects that still exist (mirrors the group-member pruning
        // above) so vanished projects don't linger as ghost selections.
        let liveSelection = selectedProjectIDs.intersection(liveIDs)
        if liveSelection != selectedProjectIDs { selectedProjectIDs = liveSelection }

        if selectedProjectIDs.isEmpty {
            // Nothing valid selected — fall back to the first visible project (original behaviour).
            let fallbackProject = filteredProjects(in: projects).first ?? projects.first
            selectedProjectID = fallbackProject?.id
            selectedProjectFallback = fallbackProject
        } else if let id = selectedProjectID, let selectedProject = projects.first(where: { $0.id == id }) {
            // Exactly one still selected — keep the inspector's fallback project fresh.
            selectedProjectFallback = selectedProject
        }
```

(`liveIDs` is already computed earlier in `applyProjects` as `Set(projects.map(\.id))`.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: PASS — including the pre-existing `testRefreshLoadsProjectsAndSelectsFirstProject`, `testRefreshPreservesSelectedProjectWhenCurrentSelectionIsFilteredOut`, and `testLoadCachedProjectsThenRefreshShowsFreshProjectsAndPersistsThem`.

- [ ] **Step 6: Commit**

```bash
git add Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "feat: prune stale ids from the project selection on refresh"
```

---

## Task 4: Bind the list to the selection set

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ProjectListView.swift:129-161` (the `List` and the `projectSelection` binding)

- [ ] **Step 1: Bind `List(selection:)` to the set**

In `ProjectListView.swift`, change the `List` initializer (line ~129) from:

```swift
                List(selection: projectSelection) {
```

to:

```swift
                List(selection: $viewModel.selectedProjectIDs) {
```

- [ ] **Step 2: Remove the now-unused single-ID binding**

Delete the `projectSelection` computed binding (lines ~154-161):

```swift
    private var projectSelection: Binding<DDEVProject.ID?> {
        Binding {
            viewModel.selectedProjectID
        } set: { newSelection in
            guard viewModel.selectedProjectID != newSelection else { return }
            viewModel.selectedProjectID = newSelection
        }
    }
```

(`viewModel` is already declared `@Bindable var viewModel`, so `$viewModel.selectedProjectIDs` is available. The per-row `.tag(project.id)` is unchanged — `DDEVProject.ID` is `String`, which is `Hashable`, satisfying `Set` selection.)

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Run the full test suite**

Run: `swift test`
Expected: PASS (no behavioural regressions).

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Views/ProjectListView.swift
git commit -m "feat: enable shift/cmd-click multi-selection in the project list"
```

---

## Task 5: Re-scope the bottom bar labels

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ProjectListView.swift:24-48` (the `batchBar`)

- [ ] **Step 1: Make the bar labels selection-aware**

In `ProjectListView.swift`, replace the `batchBar` body (lines ~24-48):

```swift
    private var batchBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.startProjectsInCurrentView() }
            } label: {
                Label("Start All (\(viewModel.startableProjectsInCurrentView.count))", systemImage: "play.fill")
            }
            .disabled(viewModel.startableProjectsInCurrentView.isEmpty)

            Button {
                Task { await viewModel.stopProjectsInCurrentView() }
            } label: {
                Label("Stop All (\(viewModel.stoppableProjectsInCurrentView.count))", systemImage: "stop.fill")
            }
            .disabled(viewModel.stoppableProjectsInCurrentView.isEmpty)

            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .help("Start or stop every project in the current view")
    }
```

with:

```swift
    private var batchBar: some View {
        // The verb scopes to the selection when 2+ projects are picked, else the whole view (B3).
        let noun = viewModel.isMultiSelecting ? "Selected" : "All"
        return HStack(spacing: 8) {
            Button {
                Task { await viewModel.startProjectsInCurrentView() }
            } label: {
                Label("Start \(noun) (\(viewModel.startableProjectsInCurrentView.count))", systemImage: "play.fill")
            }
            .disabled(viewModel.startableProjectsInCurrentView.isEmpty)

            Button {
                Task { await viewModel.stopProjectsInCurrentView() }
            } label: {
                Label("Stop \(noun) (\(viewModel.stoppableProjectsInCurrentView.count))", systemImage: "stop.fill")
            }
            .disabled(viewModel.stoppableProjectsInCurrentView.isEmpty)

            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .help(viewModel.isMultiSelecting
              ? "Start or stop the selected projects"
              : "Start or stop every project in the current view")
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/DDEVUIApp/Views/ProjectListView.swift
git commit -m "feat: relabel the batch bar to act on the selection when multi-selecting"
```

---

## Task 6: "N selected" summary in the detail pane

**Files:**
- Create: `Sources/DDEVUIApp/Views/MultiSelectionSummaryView.swift`
- Modify: `Sources/DDEVUIApp/Views/ContentView.swift:93-105` (the `detail:` closure)

- [ ] **Step 1: Create the summary view**

Create `Sources/DDEVUIApp/Views/MultiSelectionSummaryView.swift`:

```swift
import SwiftUI

/// Shown in the detail column when 2+ projects are multi-selected — the per-project inspector is
/// only meaningful for a single project. Surfaces the same scoped batch actions as the list's bottom
/// bar (so the two stay in lockstep), plus a way to clear the selection. Counts reflect the batch
/// scope (selection ∩ visible), matching exactly what the actions will touch.
struct MultiSelectionSummaryView: View {
    var viewModel: ProjectDashboardViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text("\(viewModel.selectedProjectIDs.count) Projects Selected")
                .font(.title2.weight(.semibold))

            Text(statusBreakdown)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.startProjectsInCurrentView() }
                } label: {
                    Label("Start (\(viewModel.startableProjectsInCurrentView.count))", systemImage: "play.fill")
                }
                .disabled(viewModel.startableProjectsInCurrentView.isEmpty)

                Button {
                    Task { await viewModel.stopProjectsInCurrentView() }
                } label: {
                    Label("Stop (\(viewModel.stoppableProjectsInCurrentView.count))", systemImage: "stop.fill")
                }
                .disabled(viewModel.stoppableProjectsInCurrentView.isEmpty)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .labelStyle(.titleAndIcon)

            Button("Clear Selection") { viewModel.selectedProjectIDs = [] }
                .buttonStyle(.link)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "2 running · 1 stopped" over the batch scope. "stopped" covers every non-running status
    /// (stopped/paused/unknown), matching what the Start button targets.
    private var statusBreakdown: String {
        let running = viewModel.stoppableProjectsInCurrentView.count
        let notRunning = viewModel.startableProjectsInCurrentView.count
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if notRunning > 0 { parts.append("\(notRunning) stopped") }
        return parts.isEmpty ? "None in the current view" : parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 2: Branch the detail column on selection count**

In `ContentView.swift`, replace the `detail:` closure (lines ~93-105):

```swift
        } detail: {
            if case .library(.diagnostics) = viewModel.selection {
                ContentUnavailableView(
                    "Diagnostics",
                    systemImage: "stethoscope",
                    description: Text("Run global checks or select a project before opening Diagnostics for project-specific checks.")
                )
                .navigationSplitViewColumnWidth(min: 360, ideal: 420)
            } else {
                ProjectInspectorView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 540, ideal: 720)
            }
        }
```

with:

```swift
        } detail: {
            if case .library(.diagnostics) = viewModel.selection {
                ContentUnavailableView(
                    "Diagnostics",
                    systemImage: "stethoscope",
                    description: Text("Run global checks or select a project before opening Diagnostics for project-specific checks.")
                )
                .navigationSplitViewColumnWidth(min: 360, ideal: 420)
            } else if viewModel.isMultiSelecting {
                MultiSelectionSummaryView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 540, ideal: 720)
            } else {
                ProjectInspectorView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 540, ideal: 720)
            }
        }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Run the full test suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Views/MultiSelectionSummaryView.swift Sources/DDEVUIApp/Views/ContentView.swift
git commit -m "feat: show an N-selected summary pane while multi-selecting"
```

---

## Task 7: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the complete test suite**

Run: `swift test`
Expected: all tests PASS, including the new facade/scope/pruning tests and every pre-existing test.

- [ ] **Step 2: Manual app verification**

Build and drive the app per the project's verification flow (memory: build a bundle via `xcodebuild`, drive with cua-driver; `swift run` crashes on `UNUserNotificationCenter`). Confirm:
  - Plain click selects one project → inspector shows that project; bottom bar reads "Start All / Stop All".
  - Shift-click extends a contiguous range; cmd-click toggles individual rows.
  - With 2+ selected: bottom bar reads "Start Selected (N) / Stop Selected (N)"; the detail pane shows the "N Projects Selected" summary with a matching status breakdown.
  - "Start Selected" / "Stop Selected" act on only the selected, currently-visible projects; running ones are skipped by Start and stopped ones by Stop.
  - Selecting a group in the sidebar, then multi-selecting within it, scopes the batch to the chosen members.
  - Typing a search that hides a selected project removes it from the scoped counts and actions.
  - "Clear Selection" empties the selection and returns the inspector to the single-project view.

- [ ] **Step 3: Final commit (if any manual-fix tweaks were needed)**

```bash
git add -A
git commit -m "fix: multi-select batch action polish from manual verification"
```

(Skip if nothing changed.)

---

## Notes for the implementer

- **Why a facade instead of two stored properties:** `selectedProjectIDs` is the single source of truth; `selectedProjectID` is derived. Two independent stored properties would drift. Every existing reader/writer of `selectedProjectID` (verified: `revealAndSelectProject`, `selectedProject` get/set, `selectedProjectState`, the per-project read/mutation guards, `applyProjects`) goes through the facade and keeps working.
- **The `List` must bind to `selectedProjectIDs`, never the facade** — a `Binding<Set>` is what enables native range/toggle selection.
- **No new confirmation dialogs** — batch start/stop stay un-confirmed, consistent with existing per-project and B3 behaviour (non-destructive operations).
- **Out of scope (do not add):** multi-project drag-to-group, menu-bar multi-select, checkbox edit mode, auto-pruning the stored selection while typing in search.
