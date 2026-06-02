# Project Groups — Design

**Date:** 2026-06-02
**Status:** Proposed (pre-implementation)

## Problem

The project list is one long flat column. With 15+ DDEV projects across multiple clients/contexts it's hard to scan and manage. The user wants to organise projects into **groups** to keep the list tidy — without forcing that structure on anyone who doesn't want it.

## Goals

- Opt-in **groups** that appear as entries in the left sidebar (under a new "Groups" section). Selecting a group filters the middle column to that group's projects.
- **"Projects" continues to show everything** — a user who never makes a group sees zero added clutter. Groups are purely additive.
- Each group has a **name, a colour, and a live member count** shown in its sidebar row.
- Assign a project to a group via **right-click "Move to Group…"** (and the inspector ⋯ menu) **and** by **dragging a project row onto a sidebar group**.
- **Reorder groups** in the sidebar by drag; order persists.
- Groups persist across launches.

## Non-Goals

- **Multiple groups per project / tags.** A project belongs to at most one group (folders model).
- **Reordering projects *within* a group.** Members follow the main project-list order.
- **Nested/sub-groups.** Flat groups only.
- **Arbitrary colours or per-group icons.** A fixed colour palette only.
- **Auto-grouping / smart groups.** Membership is manual.
- Changing how Projects / Running / WordPress behave.

## Decisions (locked during brainstorming)

1. **Layout:** Groups live in the **sidebar** and filter the list (not collapsible sections inside the list). Projects stays a flat list of everything.
2. **Membership:** **Folders** — one group per project, or none (none → appears only under Projects). Enforced in code.
3. **Assignment:** Right-click **"Move to Group…"** menu (row + inspector ⋯) **and** drag a row onto a sidebar group. The menu is the guaranteed path; drag is the tactile add-on.
4. **Appearance:** Sidebar group row = **colour dot + name + member-count badge**. Fixed 8-colour palette via a swatch picker (no colour wheel).
5. **Group reordering:** **Drag-to-reorder in v1**; order is persisted.
6. **Persistence:** **UserDefaults**-backed store, mirroring `AppPreferencesStoring` (protocol + in-memory test double).

## Architecture

### 1. Data model
New file `Sources/DDEVUIApp/Models/ProjectGroup.swift`:

```swift
public struct ProjectGroup: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var colorID: GroupColor
    public var memberIDs: [String]   // DDEVProject.id (project name); membership only
}

public enum GroupColor: String, Codable, CaseIterable, Sendable {
    case blue, teal, green, yellow, orange, red, purple, gray
    // maps to a SwiftUI Color in the view layer
}
```

- **Single-membership invariant** is enforced by the view model on assignment (a project id is removed from all other groups when assigned), never relied upon from storage.
- `memberIDs` stores identity only; display order of members comes from the main `projects` array, not this list.

### 2. Persistence
New file `Sources/DDEVUIApp/Services/ProjectGroupStore.swift`, mirroring `AppPreferencesStoring`:

```swift
public protocol ProjectGroupStoring: Sendable {
    func loadGroups() -> [ProjectGroup]
    func saveGroups(_ groups: [ProjectGroup])
}
public final class UserDefaultsProjectGroupStore: ProjectGroupStoring { /* JSON under one key */ }
public final class InMemoryProjectGroupStore: ProjectGroupStoring { /* test double */ }
```

The array order **is** the sidebar display order (so reordering = reordering the array + save).

### 3. Sidebar selection
`selectedSidebarItem: ProjectSidebarItem` can't represent a group (its `String`/`CaseIterable` enum has no associated values). Introduce one selection type used by `ContentView` and the view model:

```swift
public enum SidebarSelection: Hashable, Sendable {
    case library(ProjectSidebarItem)   // projects / running / wordpress / diagnostics / settings
    case group(ProjectGroup.ID)
}
```

The view model keeps `selectedSidebarItem` semantics for the library cases and adds `selectedGroupID`, surfaced through a `selection: SidebarSelection` computed property (or stores `SidebarSelection` directly — implementation detail for the plan). Detail/inspector panes that branch on `selectedSidebarItem == .settings/.diagnostics` keep working; a `.group` selection routes to the normal project list + inspector.

### 4. View model (`ProjectDashboardViewModel`)
- `public var groups: [ProjectGroup]` (loaded from the store on init; saved on every mutation).
- `filteredProjects` gains a branch: for a `.group(id)` selection, return projects whose id is in that group's `memberIDs`, in `projects` order, then apply the existing `searchText` filter. Library cases unchanged.
- Methods (each persists via the store):
  - `createGroup(name:color:) -> ProjectGroup.ID`
  - `renameGroup(_:to:)`, `setColor(_:for:)`, `deleteGroup(_:)` (delete removes the group only; members become ungrouped)
  - `assignProject(_:toGroup:)` (enforces single membership), `removeProjectFromGroup(_:)`
  - `moveGroups(fromOffsets:toOffset:)` (reorder + persist)
  - `group(for project:) -> ProjectGroup?` (for menu checkmarks / inspector display)
  - `memberCount(of:) -> Int` counting only members that exist in `projects`
- **Stale-id pruning:** `applyProjects(_:)` already drops vanished projects; extend it to prune ids no longer present from every group's `memberIDs` (keeps counts honest after a project is unlinked/deleted).

### 5. UI
- **`ContentView` sidebar:** add a second `Section("Groups")` below "Library". Each row: a `GroupSidebarRow` (colour dot + name + count badge) using the existing count-badge style. A "＋ New Group" affordance at the section foot opens an inline editor (name field + 8-swatch picker). Selection binding becomes `SidebarSelection`.
  - **Drag-reorder** groups via `.onMove` / draggable group rows.
  - **Drop-to-assign:** a group row is a drop destination for a dragged project. Distinguish "a project was dropped here" (assign) from "a group was dragged here" (reorder) by **two Transferable types** — `ProjectTransfer(id)` and `GroupTransfer(id)`.
  - Right-click a group row → **Rename**, **Change Colour**, **Delete Group**.
- **`ProjectListView` rows:** make each row `.draggable(ProjectTransfer(id:))` and add a context menu **Move to Group ▸** (each group, with a checkmark on the current one) / **New Group…** / **Remove from Group** (shown only when grouped).
- **Inspector (`ProjectInspectorView`) ⋯ menu:** add the same **Move to Group** submenu for the selected project.
- **Empty group:** `ContentUnavailableView` "No projects in this group yet."
- **Colour mapping:** `GroupColor → SwiftUI Color` lives in the view layer (a small extension), keeping the model UI-free.

## Edge cases
- Member project removed from ddev → pruned from `memberIDs` on the next refresh; count drops accordingly.
- Project renamed in ddev → treated as a new project; loses membership. Acceptable for v1.
- Deleting the currently-selected group → selection falls back to `.library(.projects)`.
- Empty group stays in the sidebar with count 0 and the empty placeholder.
- Group name: trimmed; empty names rejected; duplicate names allowed (ids are unique).

## Risks & mitigations
- **Cross-column drag (list row → sidebar group) is the fiddliest SwiftUI piece.** Mitigation: the right-click menu delivers 100% of assignment independently, so drag is strictly additive — if it proves flaky, assignment still fully works.
- **Two drop intents on one target (assign vs reorder).** Mitigation: distinct `Transferable` types; the drop handler branches on payload type.
- **Selection-type refactor touches `ContentView`/VM.** Mitigation: keep library-case behaviour identical; add the group case alongside, with tests on `filteredProjects` for both.

## Testing
- **Model/store:** encode-decode round-trip; `UserDefaultsProjectGroupStore` save/load; assignment enforces single membership; delete ungroups members; reorder persists order; stale-id prune.
- **View model:** `filteredProjects` returns a group's members in list order; `searchText` narrows within a group; `memberCount` ignores non-existent ids; create/rename/recolour/delete/move/assign/remove mutate state and persist; deleting the selected group resets selection.
- **Views:** build + manual pass (drag-to-assign and drag-to-reorder especially, since they can't be unit-tested).

## File structure
- **Create:** `Sources/DDEVUIApp/Models/ProjectGroup.swift`, `Sources/DDEVUIApp/Services/ProjectGroupStore.swift`, a `GroupColor+Color` view extension (small, can live in `ViewHelpers.swift` or its own file), and a `GroupSidebarRow`/new-group editor view (in `ContentView.swift` or a small dedicated view file).
- **Modify:** `ProjectDashboardViewModel.swift` (groups state, selection, filtered branch, mutations, prune), `ContentView.swift` (Groups section, selection binding, drag/drop), `ProjectListView.swift` (row draggable + Move-to-Group menu), `ProjectInspectorView.swift` (⋯ Move-to-Group), and the VM initializer to inject `ProjectGroupStoring`.
- **Tests:** new `ProjectGroupTests.swift`, `ProjectGroupStoreTests.swift`, and additions to `ProjectDashboardViewModelTests.swift`.
