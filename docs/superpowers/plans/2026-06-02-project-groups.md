# Project Groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users organise DDEV projects into colour-coded, reorderable sidebar **groups** (folders model) that filter the project list, while "Projects" still shows everything.

**Architecture:** A `ProjectGroup` value type persisted in `UserDefaults` via an injected `ProjectGroupStoring` (mirrors `AppPreferencesStoring`). `ProjectDashboardViewModel` owns `groups`, enforces single-membership, prunes stale member ids, and exposes a `SidebarSelection` (`.library(item)` | `.group(id)`) that `filteredProjects` honours. The sidebar gains a "Groups" section; assignment is via a "Move to Group…" context menu plus drag-a-row-onto-a-group; groups reorder via SwiftUI `.onMove`.

**Tech Stack:** Swift 6.3 / SwiftPM, SwiftUI (`@Observable`), `Transferable`/`dropDestination`/`draggable`/`onMove`, XCTest. Tests: `swift test --filter <ClassName>`.

---

## Conventions for every task
- Branch is `feat/project-groups` (already checked out). One commit per task. **No "Co-Authored-By: Claude" trailer** (project rule).
- Tests: `@MainActor final class … : XCTestCase`, `@testable import DDEVUIApp`.
- After each task: the named test(s) pass AND `swift build` is clean (only the pre-existing `Assets.xcassets` resource warning is acceptable).
- TDD for logic tasks (1–5). View tasks (6–8) are verified by `swift build` + a manual checklist (drag/drop can't be unit-tested).

## File structure
- **Create:** `Sources/DDEVUIApp/Models/ProjectGroup.swift` (model + `GroupColor`), `Sources/DDEVUIApp/Services/ProjectGroupStore.swift` (protocol + UserDefaults impl + in-memory double), `Sources/DDEVUIApp/Views/GroupSupport.swift` (`SidebarSelection` lives in VM; this file holds `GroupColor→Color`, `ProjectTransfer`, and the new-group editor + sidebar row views).
- **Modify:** `ProjectDashboardViewModel.swift` (groups state, selection, CRUD, membership, prune, filtered branch), `ContentView.swift` (Groups sidebar section + selection binding), `ProjectListView.swift` (row `.draggable` + Move-to-Group menu), `ProjectInspectorView.swift` (⋯ Move-to-Group).
- **Tests:** `ProjectGroupTests.swift`, `ProjectGroupStoreTests.swift`, additions to `ProjectDashboardViewModelTests.swift`.

---

### Task 1: `ProjectGroup` model + `GroupColor`

**Files:**
- Create: `Sources/DDEVUIApp/Models/ProjectGroup.swift`
- Test: `Tests/DDEVUIAppTests/ProjectGroupTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/DDEVUIAppTests/ProjectGroupTests.swift`:
```swift
import XCTest
@testable import DDEVUIApp

final class ProjectGroupTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let group = ProjectGroup(id: UUID(), name: "Client Work", colorID: .blue, memberIDs: ["a", "b"])
        let data = try JSONEncoder().encode([group])
        let decoded = try JSONDecoder().decode([ProjectGroup].self, from: data)
        XCTAssertEqual(decoded, [group])
    }

    func testGroupColorHasEightCases() {
        XCTAssertEqual(GroupColor.allCases.count, 8)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProjectGroupTests`
Expected: FAIL to compile — `ProjectGroup` / `GroupColor` don't exist.

- [ ] **Step 3: Implement the model**

Create `Sources/DDEVUIApp/Models/ProjectGroup.swift`:
```swift
import Foundation

public struct ProjectGroup: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var colorID: GroupColor
    /// Project ids (DDEVProject.id == project name). Identity only — display order of members
    /// comes from the main `projects` array, not this list.
    public var memberIDs: [String]

    public init(id: UUID = UUID(), name: String, colorID: GroupColor, memberIDs: [String] = []) {
        self.id = id
        self.name = name
        self.colorID = colorID
        self.memberIDs = memberIDs
    }
}

public enum GroupColor: String, Codable, CaseIterable, Sendable {
    case blue, teal, green, yellow, orange, red, purple, gray
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProjectGroupTests`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/DDEVUIApp/Models/ProjectGroup.swift Tests/DDEVUIAppTests/ProjectGroupTests.swift
git commit -m "feat(groups): add ProjectGroup model and GroupColor palette"
```

---

### Task 2: `ProjectGroupStoring` (UserDefaults + in-memory double)

**Files:**
- Create: `Sources/DDEVUIApp/Services/ProjectGroupStore.swift`
- Test: `Tests/DDEVUIAppTests/ProjectGroupStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/DDEVUIAppTests/ProjectGroupStoreTests.swift`:
```swift
import XCTest
@testable import DDEVUIApp

final class ProjectGroupStoreTests: XCTestCase {
    func testUserDefaultsRoundTrip() {
        let defaults = UserDefaults(suiteName: "ProjectGroupStoreTests.\(UUID().uuidString)")!
        let store = UserDefaultsProjectGroupStore(userDefaults: defaults)
        let groups = [
            ProjectGroup(name: "A", colorID: .blue, memberIDs: ["x"]),
            ProjectGroup(name: "B", colorID: .red, memberIDs: [])
        ]
        store.saveGroups(groups)
        XCTAssertEqual(store.loadGroups(), groups)
    }

    func testLoadDefaultsToEmptyWhenAbsent() {
        let defaults = UserDefaults(suiteName: "ProjectGroupStoreTests.\(UUID().uuidString)")!
        XCTAssertEqual(UserDefaultsProjectGroupStore(userDefaults: defaults).loadGroups(), [])
    }

    func testInMemoryDouble() {
        let store = InMemoryProjectGroupStore()
        XCTAssertEqual(store.loadGroups(), [])
        let groups = [ProjectGroup(name: "A", colorID: .teal)]
        store.saveGroups(groups)
        XCTAssertEqual(store.loadGroups(), groups)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProjectGroupStoreTests`
Expected: FAIL to compile — store types don't exist.

- [ ] **Step 3: Implement the store**

Create `Sources/DDEVUIApp/Services/ProjectGroupStore.swift`:
```swift
import Foundation

public protocol ProjectGroupStoring: Sendable {
    func loadGroups() -> [ProjectGroup]
    func saveGroups(_ groups: [ProjectGroup])
}

public final class UserDefaultsProjectGroupStore: ProjectGroupStoring, @unchecked Sendable {
    private static let key = "projectGroups"
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadGroups() -> [ProjectGroup] {
        guard let data = userDefaults.data(forKey: Self.key),
              let groups = try? JSONDecoder().decode([ProjectGroup].self, from: data) else {
            return []
        }
        return groups
    }

    public func saveGroups(_ groups: [ProjectGroup]) {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        userDefaults.set(data, forKey: Self.key)
    }
}

public final class InMemoryProjectGroupStore: ProjectGroupStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var groups: [ProjectGroup]

    public init(groups: [ProjectGroup] = []) { self.groups = groups }

    public func loadGroups() -> [ProjectGroup] { lock.withLock { groups } }
    public func saveGroups(_ groups: [ProjectGroup]) { lock.withLock { self.groups = groups } }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProjectGroupStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add Sources/DDEVUIApp/Services/ProjectGroupStore.swift Tests/DDEVUIAppTests/ProjectGroupStoreTests.swift
git commit -m "feat(groups): add ProjectGroupStoring with UserDefaults + in-memory impls"
```

---

### Task 3: View model — groups state, init load, CRUD + persistence

**Files:**
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `ProjectDashboardViewModelTests.swift`:
```swift
    func testCreateGroupPersistsAndAppends() {
        let store = InMemoryProjectGroupStore()
        let vm = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []), groupStore: store)
        let id = vm.createGroup(name: "Client Work", color: .blue)
        XCTAssertEqual(vm.groups.map(\.name), ["Client Work"])
        XCTAssertEqual(vm.groups.first?.id, id)
        XCTAssertEqual(store.loadGroups().map(\.name), ["Client Work"], "create persists")
    }

    func testRenameAndRecolorGroupPersist() {
        let store = InMemoryProjectGroupStore()
        let vm = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []), groupStore: store)
        let id = vm.createGroup(name: "A", color: .blue)
        vm.renameGroup(id, to: "Renamed")
        vm.setColor(.red, for: id)
        XCTAssertEqual(vm.groups.first?.name, "Renamed")
        XCTAssertEqual(vm.groups.first?.colorID, .red)
        XCTAssertEqual(store.loadGroups().first?.name, "Renamed", "mutations persist")
    }

    func testEmptyOrWhitespaceGroupNameIsRejected() {
        let vm = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []), groupStore: InMemoryProjectGroupStore())
        let id = vm.createGroup(name: "   ", color: .blue)
        XCTAssertNil(id)
        XCTAssertTrue(vm.groups.isEmpty)
    }

    func testDeleteGroupRemovesItOnly() {
        let store = InMemoryProjectGroupStore()
        let vm = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []), groupStore: store)
        let id = vm.createGroup(name: "A", color: .blue)!
        vm.deleteGroup(id)
        XCTAssertTrue(vm.groups.isEmpty)
        XCTAssertTrue(store.loadGroups().isEmpty, "delete persists")
    }

    func testGroupsLoadFromStoreOnInit() {
        let store = InMemoryProjectGroupStore(groups: [ProjectGroup(name: "Seeded", colorID: .green)])
        let vm = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []), groupStore: store)
        XCTAssertEqual(vm.groups.map(\.name), ["Seeded"])
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: FAIL to compile — `groupStore:` param, `groups`, and the CRUD methods don't exist.

- [ ] **Step 3: Add the injected store + state + init load**

In `ProjectDashboardViewModel.swift`:

Add a stored property near the other injected dependencies (next to `private let projectCache`):
```swift
    private let groupStore: ProjectGroupStoring
```
Add an observable state property near `public var projects` (top of the class's stored vars):
```swift
    /// User-authored project groups (folders). Sidebar display order == array order.
    public var groups: [ProjectGroup] = []
    /// Selected group, when a group (not a Library item) is the active sidebar selection.
    public var selectedGroupID: ProjectGroup.ID?
```
Add the init parameter (after `notifier: NotificationScheduling = NoopNotificationScheduler()`) and assignment + load. The init's parameter list becomes:
```swift
    public init(
        ddevService: DDEVServicing = DDEVCommandService(),
        projectCache: ProjectCacheStoring = FileProjectCacheStore(),
        preferencesStore: AppPreferencesStoring = UserDefaultsAppPreferencesStore(),
        appAvailability: AppAvailabilityChecking = WorkspaceAppAvailabilityService(),
        scheduler: CommandScheduler = CommandScheduler(maxConcurrent: 3),
        notifier: NotificationScheduling = NoopNotificationScheduler(),
        groupStore: ProjectGroupStoring = UserDefaultsProjectGroupStore()
    ) {
```
And in the init body, after `self.preferencesModel = …`:
```swift
        self.groupStore = groupStore
        self.groups = groupStore.loadGroups()
```

- [ ] **Step 4: Add CRUD methods**

Add a `// MARK: - Groups` section with:
```swift
    @discardableResult
    public func createGroup(name: String, color: GroupColor) -> ProjectGroup.ID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let group = ProjectGroup(name: trimmed, colorID: color)
        groups.append(group)
        persistGroups()
        return group.id
    }

    public func renameGroup(_ id: ProjectGroup.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = trimmed
        persistGroups()
    }

    public func setColor(_ color: GroupColor, for id: ProjectGroup.ID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].colorID = color
        persistGroups()
    }

    public func deleteGroup(_ id: ProjectGroup.ID) {
        groups.removeAll { $0.id == id }
        if selectedGroupID == id { selectedGroupID = nil }
        persistGroups()
    }

    private func persistGroups() {
        groupStore.saveGroups(groups)
    }
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter ProjectDashboardViewModelTests` then `swift build`
Expected: PASS; build clean. (Existing VM tests still pass — the new init param is defaulted.)

- [ ] **Step 6: Commit**
```bash
git add Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "feat(groups): view model group state, init load, and CRUD with persistence"
```

---

### Task 4: View model — membership (assign/remove, single-membership, count, prune)

**Files:**
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` (group methods + `applyProjects`)
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**
```swift
    func testAssignEnforcesSingleMembership() {
        let store = InMemoryProjectGroupStore()
        let vm = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []), groupStore: store)
        let a = vm.createGroup(name: "A", color: .blue)!
        let b = vm.createGroup(name: "B", color: .red)!
        vm.assignProject("proj1", toGroup: a)
        vm.assignProject("proj1", toGroup: b) // moves, not duplicates
        XCTAssertEqual(vm.groups.first(where: { $0.id == a })?.memberIDs, [])
        XCTAssertEqual(vm.groups.first(where: { $0.id == b })?.memberIDs, ["proj1"])
        XCTAssertEqual(vm.group(for: "proj1")?.id, b)
        XCTAssertEqual(store.loadGroups().first(where: { $0.id == b })?.memberIDs, ["proj1"], "assignment persists")
    }

    func testRemoveProjectFromGroup() {
        let vm = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []), groupStore: InMemoryProjectGroupStore())
        let a = vm.createGroup(name: "A", color: .blue)!
        vm.assignProject("proj1", toGroup: a)
        vm.removeProjectFromGroup("proj1")
        XCTAssertNil(vm.group(for: "proj1"))
        XCTAssertEqual(vm.groups.first?.memberIDs, [])
    }

    func testMemberCountIgnoresNonexistentProjects() async {
        let store = InMemoryProjectGroupStore()
        let vm = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: [.sampleWordPress]), groupStore: store)
        await vm.refresh() // projects == [aqua-pura]
        let a = vm.createGroup(name: "A", color: .blue)!
        vm.assignProject("aqua-pura", toGroup: a)
        vm.assignProject("ghost", toGroup: a) // not a real project
        XCTAssertEqual(vm.memberCount(of: a), 1, "only existing projects count")
    }

    func testRefreshPrunesStaleMemberIDs() async {
        let store = InMemoryProjectGroupStore()
        let vm = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: [.sampleWordPress]), groupStore: store)
        await vm.refresh()
        let a = vm.createGroup(name: "A", color: .blue)!
        vm.assignProject("aqua-pura", toGroup: a)
        vm.assignProject("ghost", toGroup: a)
        await vm.refresh() // re-applies projects; "ghost" no longer exists
        XCTAssertEqual(vm.groups.first(where: { $0.id == a })?.memberIDs, ["aqua-pura"], "stale id pruned")
    }

    func testMoveGroupsReorders() {
        let store = InMemoryProjectGroupStore()
        let vm = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []), groupStore: store)
        _ = vm.createGroup(name: "A", color: .blue)
        _ = vm.createGroup(name: "B", color: .red)
        _ = vm.createGroup(name: "C", color: .green)
        vm.moveGroups(fromOffsets: IndexSet(integer: 0), toOffset: 3) // move A to end
        XCTAssertEqual(vm.groups.map(\.name), ["B", "C", "A"])
        XCTAssertEqual(store.loadGroups().map(\.name), ["B", "C", "A"], "reorder persists")
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: FAIL to compile — the membership methods don't exist.

- [ ] **Step 3: Add membership methods (in the `// MARK: - Groups` section)**
```swift
    public func assignProject(_ projectID: DDEVProject.ID, toGroup groupID: ProjectGroup.ID) {
        // Single-membership: remove from every group first, then add to the target.
        for index in groups.indices {
            groups[index].memberIDs.removeAll { $0 == projectID }
        }
        guard let target = groups.firstIndex(where: { $0.id == groupID }) else { persistGroups(); return }
        groups[target].memberIDs.append(projectID)
        persistGroups()
    }

    public func removeProjectFromGroup(_ projectID: DDEVProject.ID) {
        for index in groups.indices {
            groups[index].memberIDs.removeAll { $0 == projectID }
        }
        persistGroups()
    }

    public func group(for projectID: DDEVProject.ID) -> ProjectGroup? {
        groups.first { $0.memberIDs.contains(projectID) }
    }

    public func memberCount(of groupID: ProjectGroup.ID) -> Int {
        guard let group = groups.first(where: { $0.id == groupID }) else { return 0 }
        let liveIDs = Set(projects.map(\.id))
        return group.memberIDs.filter { liveIDs.contains($0) }.count
    }

    public func moveGroups(fromOffsets source: IndexSet, toOffset destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        persistGroups()
    }
```

- [ ] **Step 4: Prune stale ids in `applyProjects`**

`applyProjects(_:)` already filters `commandStates` to live ids. Add group pruning right after it sets `self.projects = projects`. Insert after the `let liveIDs = Set(projects.map(\.id))` line (reuse it) — locate the existing block:
```swift
        let liveIDs = Set(projects.map(\.id))
        commandStates = commandStates.filter { liveIDs.contains($0.key) || $0.value.isBusy }
```
and add immediately after it:
```swift
        // Drop group memberships for projects that no longer exist so counts/filters stay honest.
        var didPruneGroups = false
        for index in groups.indices {
            let kept = groups[index].memberIDs.filter { liveIDs.contains($0) }
            if kept.count != groups[index].memberIDs.count {
                groups[index].memberIDs = kept
                didPruneGroups = true
            }
        }
        if didPruneGroups { persistGroups() }
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter ProjectDashboardViewModelTests` then `swift build`
Expected: PASS; clean build.

- [ ] **Step 6: Commit**
```bash
git add Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "feat(groups): membership assignment, single-membership, counts, reorder, stale-id prune"
```

---

### Task 5: View model — `SidebarSelection` + group filtering

**Files:**
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` (`SidebarSelection`, `selection`, `filteredProjects`)
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**
```swift
    func testFilteredProjectsForSelectedGroup() async {
        let store = InMemoryProjectGroupStore()
        let vm = ProjectDashboardViewModel(
            ddevService: FakeDDEVService(projects: [.sampleWordPress, .sampleLaravel]), groupStore: store)
        await vm.refresh() // aqua-pura, agilebugs
        let a = vm.createGroup(name: "A", color: .blue)!
        vm.assignProject("agilebugs", toGroup: a)
        vm.selection = .group(a)
        XCTAssertEqual(vm.filteredProjects.map(\.id), ["agilebugs"])
    }

    func testSearchNarrowsWithinSelectedGroup() async {
        let vm = ProjectDashboardViewModel(
            ddevService: FakeDDEVService(projects: [.sampleWordPress, .sampleLaravel]), groupStore: InMemoryProjectGroupStore())
        await vm.refresh()
        let a = vm.createGroup(name: "A", color: .blue)!
        vm.assignProject("aqua-pura", toGroup: a)
        vm.assignProject("agilebugs", toGroup: a)
        vm.selection = .group(a)
        vm.searchText = "aqua"
        XCTAssertEqual(vm.filteredProjects.map(\.id), ["aqua-pura"])
    }

    func testSelectingLibraryClearsGroupSelection() {
        let vm = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []), groupStore: InMemoryProjectGroupStore())
        let a = vm.createGroup(name: "A", color: .blue)!
        vm.selection = .group(a)
        XCTAssertEqual(vm.selectedGroupID, a)
        vm.selection = .library(.running)
        XCTAssertNil(vm.selectedGroupID)
        XCTAssertEqual(vm.selectedSidebarItem, .running)
    }

    func testDeletingSelectedGroupResetsSelectionToLibrary() {
        let vm = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []), groupStore: InMemoryProjectGroupStore())
        let a = vm.createGroup(name: "A", color: .blue)!
        vm.selection = .group(a)
        vm.deleteGroup(a)
        if case .library = vm.selection { /* ok */ } else { XCTFail("selection should fall back to library") }
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: FAIL to compile — `SidebarSelection` / `selection` don't exist; `filteredProjects` ignores groups.

- [ ] **Step 3: Add `SidebarSelection` and the `selection` accessor**

Add the type near `ProjectSidebarItem` (top of `ProjectDashboardViewModel.swift`, after the enum):
```swift
public enum SidebarSelection: Hashable, Sendable {
    case library(ProjectSidebarItem)
    case group(ProjectGroup.ID)
}
```
Add a computed `selection` to the view model (near `selectedProject`):
```swift
    /// Unified sidebar selection. `.group` wins when a still-existing group is selected, else the
    /// Library item. Setting `.library` clears the group selection.
    public var selection: SidebarSelection {
        get {
            if let selectedGroupID, groups.contains(where: { $0.id == selectedGroupID }) {
                return .group(selectedGroupID)
            }
            return .library(selectedSidebarItem)
        }
        set {
            switch newValue {
            case .library(let item):
                selectedSidebarItem = item
                selectedGroupID = nil
            case .group(let id):
                selectedGroupID = id
            }
        }
    }
```

- [ ] **Step 4: Branch `filteredProjects(in:)` on the group selection**

Replace the body of the private `filteredProjects(in:)` with:
```swift
    private func filteredProjects(in sourceProjects: [DDEVProject]) -> [DDEVProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sectionProjects: [DDEVProject]
        if let selectedGroupID, let group = groups.first(where: { $0.id == selectedGroupID }) {
            let memberSet = Set(group.memberIDs)
            sectionProjects = sourceProjects.filter { memberSet.contains($0.id) }
        } else {
            sectionProjects = sourceProjects.filter { project in
                switch selectedSidebarItem {
                case .projects: true
                case .running: project.status == .running
                case .wordpress: project.isWordPress
                case .diagnostics: false
                case .settings: false
                }
            }
        }

        guard !query.isEmpty else { return sectionProjects }

        return sectionProjects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || project.shortRoot.localizedCaseInsensitiveContains(query)
                || project.projectType.rawValue.localizedCaseInsensitiveContains(query)
                || (project.phpVersion?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter ProjectDashboardViewModelTests` then `swift build`
Expected: PASS; clean build.

- [ ] **Step 6: Commit**
```bash
git add Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "feat(groups): SidebarSelection and group-aware project filtering"
```

---

### Task 6: Sidebar "Groups" section + colour mapping + new-group editor

**Files:**
- Create: `Sources/DDEVUIApp/Views/GroupSupport.swift`
- Modify: `Sources/DDEVUIApp/Views/ContentView.swift`

> View task — verified by `swift build` + manual checklist (no unit tests).

- [ ] **Step 1: Create `GroupSupport.swift` with colour mapping + sidebar row + editor**
```swift
import SwiftUI
import UniformTypeIdentifiers

extension GroupColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .purple: .purple
        case .gray: .gray
        }
    }
}

/// Drag payload for assigning a project (a list row) onto a sidebar group.
struct ProjectTransfer: Codable, Transferable {
    let projectID: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ddevuiProjectRow)
    }
}

extension UTType {
    static let ddevuiProjectRow = UTType(exportedAs: "io.agilepixel.ddevui.project-row")
}

/// A sidebar row for one group: colour dot + name + member-count badge.
struct GroupSidebarRow: View {
    let group: ProjectGroup
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(group.colorID.color)
                .frame(width: 9, height: 9)
            Text(group.name)
                .lineLimit(1)
            Spacer(minLength: 0)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary.opacity(0.6)))
            }
        }
    }
}

/// Inline "new group" editor: a name field + the 8-swatch colour picker.
struct NewGroupEditor: View {
    @Bindable var viewModel: ProjectDashboardViewModel
    @State private var name = ""
    @State private var color: GroupColor = .blue
    @FocusState private var nameFocused: Bool
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Group name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(create)
            HStack(spacing: 6) {
                ForEach(GroupColor.allCases, id: \.self) { swatch in
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: color == swatch ? 2 : 0))
                        .onTapGesture { color = swatch }
                        .accessibilityLabel(swatch.rawValue)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onDone)
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear { nameFocused = true }
    }

    private func create() {
        guard viewModel.createGroup(name: name, color: color) != nil else { return }
        onDone()
    }
}
```

- [ ] **Step 2: Add the Groups section + selection binding in `ContentView.swift`**

Replace the sidebar `List(selection:)` block and `sidebarSelection` binding so selection is `SidebarSelection` and a "Groups" section is shown. In the `NavigationSplitView { List(selection: …) … }` sidebar column, use:
```swift
            List(selection: sidebarSelection) {
                Section("Library") {
                    ForEach(ProjectSidebarItem.allCases) { item in
                        SidebarRow(item: item, count: count(for: item))
                            .tag(SidebarSelection.library(item))
                    }
                }
                if !viewModel.groups.isEmpty {
                    Section("Groups") {
                        ForEach(viewModel.groups) { group in
                            GroupSidebarRow(group: group, count: viewModel.memberCount(of: group.id))
                                .tag(SidebarSelection.group(group.id))
                                .contextMenu { groupContextMenu(group) }
                                .dropDestination(for: ProjectTransfer.self) { items, _ in
                                    for item in items { viewModel.assignProject(item.projectID, toGroup: group.id) }
                                    return !items.isEmpty
                                }
                        }
                        .onMove { viewModel.moveGroups(fromOffsets: $0, toOffset: $1) }
                    }
                }
                Section {
                    Button {
                        showNewGroupEditor = true
                    } label: {
                        Label("New Group", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showNewGroupEditor, arrowEdge: .trailing) {
                        NewGroupEditor(viewModel: viewModel) { showNewGroupEditor = false }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("DDEVUI")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
```
Add state to `ContentView`:
```swift
    @State private var showNewGroupEditor = false
    @State private var groupToRename: ProjectGroup?
```
Replace `sidebarSelection` binding (currently `Binding<ProjectSidebarItem>`) with:
```swift
    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding {
            viewModel.selection
        } set: { newSelection in
            guard let newSelection, viewModel.selection != newSelection else { return }
            viewModel.selection = newSelection
        }
    }
```
Update the `content` and `detail` column branches to switch on `viewModel.selection` instead of `viewModel.selectedSidebarItem`:
```swift
        } content: {
            switch viewModel.selection {
            case .library(.settings):
                SettingsView(viewModel: viewModel)
            case .library(.diagnostics):
                DiagnosticsView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 480, ideal: 680)
            default:
                ProjectListView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
            }
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
Add the group context-menu builder + rename sheet to `ContentView` (a method, plus a `.sheet` for rename). Add this method inside `ContentView`:
```swift
    @ViewBuilder
    private func groupContextMenu(_ group: ProjectGroup) -> some View {
        Button("Rename…") { groupToRename = group }
        Menu("Change Colour") {
            ForEach(GroupColor.allCases, id: \.self) { swatch in
                Button {
                    viewModel.setColor(swatch, for: group.id)
                } label: {
                    Label(swatch.rawValue.capitalized, systemImage: group.colorID == swatch ? "checkmark" : "circle.fill")
                }
            }
        }
        Divider()
        Button("Delete Group", role: .destructive) { viewModel.deleteGroup(group.id) }
    }
```
And attach a rename sheet to the `NavigationSplitView` (next to the existing `.sheet`/`.task` modifiers):
```swift
        .sheet(item: $groupToRename) { group in
            RenameGroupSheet(viewModel: viewModel, group: group)
        }
```
Add `RenameGroupSheet` to `GroupSupport.swift`:
```swift
struct RenameGroupSheet: View {
    @Bindable var viewModel: ProjectDashboardViewModel
    let group: ProjectGroup
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(viewModel: ProjectDashboardViewModel, group: ProjectGroup) {
        self.viewModel = viewModel
        self.group = group
        _name = State(initialValue: group.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Group").font(.headline)
            TextField("Group name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func commit() {
        viewModel.renameGroup(group.id, to: name)
        dismiss()
    }
}
```
> Note: `ProjectGroup` is already `Identifiable`, so `.sheet(item:)` works.

- [ ] **Step 3: Build and manually verify**
```bash
swift build
```
Expected: clean build. Then run the app (xcodebuild a bundle — see `docs/superpowers/` notes / prior verification) and check:
1. Create a group via "New Group" → it appears under a "Groups" sidebar section with its colour dot.
2. Selecting the group shows its (initially empty) member list with the empty placeholder.
3. Right-click the group → Rename / Change Colour / Delete work; delete returns you to Projects.
4. Library items (Projects/Running/WordPress/Diagnostics/Settings) still select and route correctly.

- [ ] **Step 4: Commit**
```bash
git add Sources/DDEVUIApp/Views/GroupSupport.swift Sources/DDEVUIApp/Views/ContentView.swift
git commit -m "feat(groups): sidebar Groups section, new-group editor, rename/recolour/delete"
```

---

### Task 7: Assignment — row drag + "Move to Group" context menu

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ProjectListView.swift`

> View task — `swift build` + manual checklist.

- [ ] **Step 1: Make rows draggable and add the Move-to-Group menu**

In `ProjectListView.swift`, the `ForEach(viewModel.filteredProjects) { project in ProjectRow(...) … }` — attach a context menu and draggable to each row. Update the row construction:
```swift
                        ForEach(viewModel.filteredProjects) { project in
                            ProjectRow(project: project, viewModel: viewModel)
                                .tag(project.id)
                                .listRowSeparator(.visible)
                                .draggable(ProjectTransfer(projectID: project.id))
                                .contextMenu { moveToGroupMenu(project) }
                        }
```
Add the menu builder to `ProjectListView` (the outer struct):
```swift
    @ViewBuilder
    private func moveToGroupMenu(_ project: DDEVProject) -> some View {
        Menu("Move to Group") {
            ForEach(viewModel.groups) { group in
                Button {
                    viewModel.assignProject(project.id, toGroup: group.id)
                } label: {
                    Label(group.name,
                          systemImage: viewModel.group(for: project.id)?.id == group.id ? "checkmark" : "folder")
                }
            }
            Divider()
            Button("New Group…") {
                if let id = viewModel.createGroup(name: "New Group", color: .blue) {
                    viewModel.assignProject(project.id, toGroup: id)
                }
            }
            if viewModel.group(for: project.id) != nil {
                Button("Remove from Group", role: .destructive) {
                    viewModel.removeProjectFromGroup(project.id)
                }
            }
        }
    }
```
> "New Group…" here creates a group named "New Group" and assigns immediately (rename via the sidebar context menu). This keeps the menu non-modal; a full inline-name flow from a context menu isn't worth the complexity for v1.

- [ ] **Step 2: Build and manually verify**
```bash
swift build
```
Then in the app:
1. Right-click a project → **Move to Group** → pick a group → it disappears from that group view's complement and the group's count increments; the current group shows a checkmark.
2. **Drag** a project row onto a sidebar group → it's assigned (count updates). Re-check it moved (single-membership) if it was in another group.
3. Right-click a grouped project → **Remove from Group** clears membership.
4. "New Group…" from the menu creates + assigns in one step.

- [ ] **Step 3: Commit**
```bash
git add Sources/DDEVUIApp/Views/ProjectListView.swift
git commit -m "feat(groups): assign via row drag and Move-to-Group context menu"
```

---

### Task 8: Inspector ⋯ "Move to Group" submenu

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`

> View task — `swift build` + manual checklist.

- [ ] **Step 1: Add the submenu to the inspector ⋯ menu**

In `ProjectInspectorView.swift`, the toolbar `Menu { … } label: { Label("More", systemImage: "ellipsis.circle") }` currently has launch links + Unlink/Delete/Move-to-Trash. Add a Move-to-Group submenu above the destructive section (after the launch links `Divider()`):
```swift
                            Menu("Move to Group") {
                                ForEach(viewModel.groups) { group in
                                    Button {
                                        viewModel.assignProject(project.id, toGroup: group.id)
                                    } label: {
                                        Label(group.name,
                                              systemImage: viewModel.group(for: project.id)?.id == group.id ? "checkmark" : "folder")
                                    }
                                }
                                Divider()
                                Button("New Group…") {
                                    if let id = viewModel.createGroup(name: "New Group", color: .blue) {
                                        viewModel.assignProject(project.id, toGroup: id)
                                    }
                                }
                                if viewModel.group(for: project.id) != nil {
                                    Button("Remove from Group", role: .destructive) {
                                        viewModel.removeProjectFromGroup(project.id)
                                    }
                                }
                            }

                            Divider()
```
(Place this just before the existing `Button(role: .destructive) { confirmUnlink = true }` block.)

- [ ] **Step 2: Build and manually verify**
```bash
swift build
```
Then in the app: select a project → toolbar **⋯** → **Move to Group** assigns/removes consistently with the row menu (checkmark on the current group).

- [ ] **Step 3: Commit**
```bash
git add Sources/DDEVUIApp/Views/ProjectInspectorView.swift
git commit -m "feat(groups): Move-to-Group submenu in the inspector menu"
```

---

## Final verification

- [ ] **Full suite green**

Run: `swift test`
Expected: all tests pass (new + existing).

- [ ] **Manual end-to-end**
1. Create two groups (different colours); reorder them by dragging in the sidebar → order sticks after relaunch.
2. Assign projects by both drag and the Move-to-Group menu; confirm single-membership (assigning to B removes from A).
3. Select a group → only its members show; type in search → narrows within the group; switch to Projects → everything shows.
4. Delete a group → members reappear ungrouped under Projects; selection returns to Projects.
5. Unlink/delete a grouped project via ddev → after refresh its group count drops (stale id pruned).

---

## Self-review (completed by plan author)
- **Spec coverage:** model+palette → Task 1; UserDefaults store → Task 2; VM state/CRUD/load → Task 3; membership/single-membership/count/reorder/prune → Task 4; SidebarSelection + group filtering + delete-resets-selection → Task 5; sidebar Groups section + colour + new-group/rename/recolour/delete → Task 6; assignment (drag + menu) → Task 7; inspector menu → Task 8. Non-goals (multi-membership, member reorder, nesting, custom colours, polling) not implemented.
- **Drag model refinement vs spec:** spec floated two `Transferable` types; plan uses `.onMove` for group reorder + one `ProjectTransfer` `dropDestination` for assignment — simpler, same behaviour.
- **Placeholder scan:** none. "New Group…" from context menus intentionally creates a default-named group (rename via sidebar) — documented, not a placeholder.
- **Type consistency:** `groups`, `selectedGroupID`, `selection: SidebarSelection`, `createGroup→ProjectGroup.ID?`, `assignProject(_:toGroup:)`, `removeProjectFromGroup(_:)`, `group(for:)`, `memberCount(of:)`, `moveGroups(fromOffsets:toOffset:)`, `GroupColor.color`, `ProjectTransfer.projectID`, `.ddevuiProjectRow` used identically across tasks. New VM init param `groupStore:` is defaulted so existing call sites/tests compile unchanged.
