# Multi-Select Batch Actions — Design

**Date:** 2026-06-02
**Status:** Proposed (pre-implementation)

## Problem

The project list (B3) added a "Start All / Stop All" bar that acts on the **entire current view** — the whole Projects list, or, when a group is selected in the sidebar, that whole group. There is no way to act on a **subset**. The user wants to shift-click a range or cmd-click individual projects, then start/stop exactly those — in the Projects list *and* inside a group.

The list is single-selection today: `selectedProjectID: DDEVProject.ID?` drives the right-column inspector. There is no multi-selection capability at all.

## Goals

- **Native multi-selection** in the project list: shift-click selects a range, cmd-click toggles individual rows, plain click selects one. Works in the Projects list and inside any group (both render through `ProjectListView`).
- The existing bottom bar becomes **selection-aware**: with 2+ selected it acts on the selection and relabels to "Start Selected (N) / Stop Selected (N)"; with 0–1 selected it stays "Start All / Stop All" over the whole view (today's behavior).
- When 2+ projects are selected, the **detail pane shows a "N selected" summary** (standard macOS Finder/Mail pattern) instead of loading per-project detail for a moving selection.
- Batch actions only ever touch projects you can **currently see** — selection ∩ visible (filtered) — so a stale search filter can't make you act on a hidden project.

## Non-Goals

- **Multi-project drag-to-group.** Dragging a row onto a sidebar group still moves that one project, even if several are selected.
- **Menu-bar surface (B1).** No multi-select there; this change is the main-window list only.
- **Checkbox / explicit "edit mode".** Selection is the native shift/cmd-click idiom only.
- **Auto-pruning the stored selection on search.** The stored selection survives a transient filter; only the *batch scope* intersects with the visible set.
- **New confirmation dialogs.** Batch stop/start stay un-confirmed, consistent with the existing per-project and B3 behavior (these operations are non-destructive).
- **Inline collapsible group sections in the main list.** Groups remain sidebar selections (unchanged from the Project Groups design).

## Decisions (locked during brainstorming)

1. **Approach:** Native `List(selection:)` bound to a `Set`, with the existing bottom bar re-scoped to the selection. (Rejected: a separate contextual toolbar/menu; a checkbox edit mode.)
2. **Detail pane on multi-select:** A "N selected" summary pane. (Rejected: keep showing the last-clicked project's detail.)
3. **Re-scope threshold:** The bar scopes to the selection only at **2+** selected. A single selection (the normal way to open a project in the inspector) does **not** hijack the bar — it stays "Start All / Stop All" over the whole view.
4. **Scope vs. search:** Batch actions and count labels operate on **selection ∩ currently-visible** projects. The stored selection is not mutated by typing in the search field.

## Architecture

### 1. Selection state (view model)

`ProjectDashboardViewModel` gains a `Set` as the new source of truth, and `selectedProjectID` becomes a computed facade over it:

```swift
/// Source of truth for list selection. Bound directly to `List(selection:)`.
public var selectedProjectIDs: Set<DDEVProject.ID> = [] {
    didSet {
        // Recency (B5) is recorded only when the selection settles on a single project.
        if selectedProjectIDs.count == 1, let id = selectedProjectIDs.first, !oldValue.contains(id) {
            recordRecentProject(id)
        }
    }
}

/// Facade kept for the inspector, quick switcher, and `selectedProject`. One selected → that id; else nil.
public var selectedProjectID: DDEVProject.ID? {
    get { selectedProjectIDs.count == 1 ? selectedProjectIDs.first : nil }
    set { selectedProjectIDs = newValue.map { [$0] } ?? [] }
}
```

- The existing `selectedProjectID` stored property (with its recency `didSet`) is **replaced** by this computed facade; recency moves into `selectedProjectIDs.didSet`.
- All existing callers keep working unchanged: `revealAndSelectProject` (B6 quick switcher) sets `selectedProjectID = id`; `selectedProject`'s getter/setter, `startSelectedProject`, `moveSelectedProjectFolderToTrash`, etc. all go through the facade.
- `@Observable` tracks the computed facade correctly because its getter reads the tracked `selectedProjectIDs`.

**Refresh / removal reconciliation.** The post-refresh reconciliation that currently re-validates the single selection is extended to **prune `selectedProjectIDs` to live project ids** (mirroring how group `memberIDs` are pruned to `liveIDs` in the same pass). The existing single-selection fallback — auto-select the first visible project when nothing valid remains — is preserved by writing through the facade. `moveSelectedProjectFolderToTrash` likewise removes the trashed id from the set, not just the single selection.

Derived helpers:

```swift
/// 2+ selected — the bar and inspector switch into selection mode.
public var isMultiSelecting: Bool { selectedProjectIDs.count >= 2 }

/// Projects to act on: the selection (∩ visible) when multi-selecting, else the whole view.
/// Always intersected with `filteredProjects` so hidden projects are never touched, and ordered
/// to match the visible list.
public var batchScopeProjects: [DDEVProject] {
    guard isMultiSelecting else { return filteredProjects }
    return filteredProjects.filter { selectedProjectIDs.contains($0.id) }
}

public var batchStartableProjects: [DDEVProject] { batchScopeProjects.filter { $0.status != .running } }
public var batchStoppableProjects: [DDEVProject] { batchScopeProjects.filter { $0.status == .running } }

/// Whether the bar is acting on a chosen subset (drives "Selected" vs "All" labels).
public var isBatchScopedToSelection: Bool { isMultiSelecting }
```

The existing `startableProjectsInCurrentView` / `stoppableProjectsInCurrentView` and `startProjectsInCurrentView()` / `stopProjectsInCurrentView()` are generalised to run over `batchScopeProjects` (or kept as thin aliases). `runBatch` is unchanged — it already skips busy projects and fans out through the scheduler-gated per-project mutations.

### 2. List binding (ProjectListView)

`List(selection:)` binds to a `Binding<Set<DDEVProject.ID>>` over `selectedProjectIDs` instead of the current single `Binding<DDEVProject.ID?>`. macOS provides shift-click range, cmd-click toggle, plain-click single, and ⌘A select-all for free. The `.tag(project.id)` per row stays.

### 3. Re-scoped bottom bar (ProjectListView)

The `batchBar` reads the scoped properties:

- `isBatchScopedToSelection == true` → labels "Start Selected (\(batchStartableProjects.count))" / "Stop Selected (\(batchStoppableProjects.count))".
- else → labels "Start All (…)" / "Stop All (…)" (unchanged).

Buttons remain disabled when their scoped candidate list is empty. The bar's visibility condition (`filteredProjects.count > 1`) is unchanged.

### 4. Detail pane — "N selected" summary

In `ContentView`'s `detail:` closure (and/or a small new view in `ProjectInspectorView`), branch on selection count:

- `selectedProjectIDs.count == 1` → `ProjectInspectorView` as today.
- `selectedProjectIDs.count >= 2` → a `MultiSelectionSummaryView`: "\(N) projects selected", a one-line status breakdown (e.g. "2 running · 1 stopped"), scoped **Start Selected / Stop Selected** buttons, and a **Clear Selection** button (`selectedProjectIDs = []`).
- `selectedProjectIDs.isEmpty` → existing empty/placeholder state.

The summary reuses the same view-model batch entry points, so the bottom bar and the summary pane stay in lockstep.

### 5. Clearing selection

- "Clear Selection" in the summary pane sets `selectedProjectIDs = []`.
- Native List behavior covers Esc / click-in-empty-space where the platform supports it; no custom gesture is added beyond the explicit button.

## Testing

View-model unit tests (extending `ProjectDashboardViewModelTests`):

- **Facade:** setting `selectedProjectID` yields a single-element set; setting it to `nil` empties the set; a 2-element set reports `selectedProjectID == nil`.
- **Recency:** settling on a single new id records it in `recentProjectIDs`; a multi-selection records nothing.
- **Scope:** `batchScopeProjects` equals `filteredProjects` with 0–1 selected, and the selection (∩ visible, in visible order) with 2+ selected.
- **Visibility intersection:** a selected project hidden by the search filter is excluded from `batchScopeProjects` and the scoped counts.
- **Counts:** `batchStartableProjects` / `batchStoppableProjects` reflect only the in-scope projects by status.
- **Batch run:** `startProjectsInCurrentView()` / `stopProjectsInCurrentView()` over a multi-selection act on the selected subset and skip busy projects.
- **Reconciliation:** after a refresh that drops a project, its id is removed from `selectedProjectIDs`; an emptied selection falls back to the first visible project.

UI wiring (selection gestures, label text, pane switching) is verified manually per the project's app-verification flow.

## Risks / Notes

- **Facade desync:** making `selectedProjectID` computed removes its stored `didSet`. Recency must move to `selectedProjectIDs.didSet`, and every existing reader/writer of `selectedProjectID` must be re-checked to confirm it tolerates a computed property (no `$`-binding to the stored form). The List must bind to `selectedProjectIDs`, never the facade.
- **Inspector load churn:** branching the detail pane on count avoids firing `loadDetailsForSelectedProject` / Xdebug / DB reads while a multi-selection is in flux.
