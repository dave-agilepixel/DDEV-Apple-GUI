# Project Inspector Pane Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganise the project inspector pane so it reflects how the user actually works — daily actions promoted, the database un-scattered, Overview as a card grid, and the 8-section Manage pile collapsed into 3 grouped cards — while splitting the 1348-line `ProjectInspectorView.swift` into focused files.

**Architecture:** Pure view-layer redesign. All behaviour runs through the existing `ProjectDashboardViewModel` API (no command/model changes). Work proceeds in two phases: (1) a **mechanical file split with zero behaviour change** to make the code tractable, then (2) the **redesign** of header, action bar, tab-strip URL launcher, Overview cards, and Manage cards. The one functional change is merging the per-tool rows + the exec box into a single runner via a new pure `RunTarget` enum.

**Tech Stack:** Swift, SwiftUI, AppKit (macOS app), Swift Package Manager. Tests via XCTest (`swift test`). App bundle for manual verification via `xcodebuild` (per the `verify-ddevui-app` memory — `swift run` crashes on `UNUserNotificationCenter`).

**Testing note (read first):** SwiftUI view layout is not unit-tested in this codebase. The automated anchors are: (a) the existing `InspectorTabTests` and `ProjectLaunchLinksTests` must stay green (so the `InspectorTab` enum and the `projectLaunchLinks(_:_:)` signature/behaviour must not change), and (b) one new unit test for the pure `RunTarget` model. Everything else is verified by `swift build` per task plus a consolidated manual pass in the final task. Do **not** weaken or rename `InspectorTab` or `projectLaunchLinks`.

**Commands used throughout:**
- Compile check: `swift build` → expect `Build complete!`
- Unit tests: `swift test` → expect all pass. Targeted: `swift test --filter InspectorTabTests`, `swift test --filter ProjectLaunchLinksTests`, `swift test --filter RunTargetTests`.

---

## Phase 1 — Mechanical split (no behaviour change)

### Task 1: Add `InspectorCard` and move shared low-level components into a new file

Move the reusable, leaf-level pieces out of `ProjectInspectorView.swift` into a new `InspectorComponents.swift`, and add the new `InspectorCard` container the redesign needs. **No behaviour change** — this is a cut/paste plus an access-level change (`private struct` → `struct`/internal so other inspector files can use them) plus one new component.

**Files:**
- Create: `Sources/DDEVUIApp/Views/Inspector/InspectorComponents.swift`
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift` (remove the moved declarations)

- [ ] **Step 1: Create `InspectorComponents.swift` and move these declarations into it**

Create `Sources/DDEVUIApp/Views/Inspector/InspectorComponents.swift` with `import AppKit` + `import SwiftUI`. **Move the following declarations verbatim** out of `ProjectInspectorView.swift` into this file, changing each `private struct`/`private func` to internal (drop the `private` keyword) so they're visible to the other inspector files created later:

- `InspectorSection` (currently `ProjectInspectorView.swift:429`)
- `ProjectStatusBadge` (already non-private — `:452`) — leave its access as-is, just move it
- `InspectorChipLabelStyle` (`:493`)
- `LaunchLink` struct + `projectLaunchLinks(_:_:)` free function (`:507`, `:517`) — **keep `projectLaunchLinks` internal and its signature/return value identical** (a test depends on it)
- `DBDriftBanner` (`:538`)
- `CopyableRow` (`:574`)
- `FlowHStack`, `WrappingHStack`, `FlowLayout` (`:1216`, `:1233`, `:1244`)
- `SourceFolderDeleteSheet` (`:1290`)

- [ ] **Step 2: Add the new `InspectorCard` component to `InspectorComponents.swift`**

Append this **new** component (this is the titled, bordered container every redesigned card uses):

```swift
/// A titled, bordered card used across the redesigned Overview and Manage tabs. Optional trailing
/// header action (e.g. "Open in TablePlus"). Replaces the old header-only `InspectorSection` for
/// grouped content.
struct InspectorCard<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var headerActionTitle: String? = nil
    var headerAction: (() -> Void)? = nil
    @ViewBuilder var content: Content

    init(
        _ title: String,
        systemImage: String? = nil,
        headerActionTitle: String? = nil,
        headerAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.headerActionTitle = headerActionTitle
        self.headerAction = headerAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .sectionHeaderStyle()
                Spacer(minLength: 8)
                if let headerActionTitle, let headerAction {
                    Button(headerActionTitle, action: headerAction)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.4), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }
}
```

- [ ] **Step 3: Compile**

Run: `swift build`
Expected: `Build complete!` (Fix any missed access-level errors — anything still referenced from `ProjectInspectorView.swift` must be internal, not private.)

- [ ] **Step 4: Run the existing tests**

Run: `swift test --filter InspectorTabTests` then `swift test --filter ProjectLaunchLinksTests`
Expected: both pass (proves the move didn't change `InspectorTab` or `projectLaunchLinks`).

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Views/Inspector/InspectorComponents.swift Sources/DDEVUIApp/Views/ProjectInspectorView.swift
git commit -m "refactor: extract inspector shared components + add InspectorCard"
```

---

### Task 2: Split the three tab contents + header into separate files (verbatim move)

Move the tab content views and the header/action-bar code into their own files. **Still no behaviour change** — verbatim move + access-level fixes. This isolates each tab so later redesign tasks touch one small file.

**Files:**
- Create: `Sources/DDEVUIApp/Views/Inspector/InspectorOverviewTab.swift`
- Create: `Sources/DDEVUIApp/Views/Inspector/InspectorManageTab.swift`
- Create: `Sources/DDEVUIApp/Views/Inspector/InspectorLogsTab.swift`
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`

- [ ] **Step 1: Move Overview into `InspectorOverviewTab.swift`**

`import AppKit` + `import SwiftUI`. Move verbatim (drop `private`): `OverviewTabContent` (`:619`), `ServiceRow` (`:836`), `ServiceHealthRow` (`:877`). Leave the `ScrollView { OverviewTabContent(...) }` call site in `ProjectInspectorView.tabContent` for now.

- [ ] **Step 2: Move Manage into `InspectorManageTab.swift`**

`import AppKit` + `import SwiftUI`. Move verbatim (drop `private`): `ToolRunnerView` (`:901`), `ToolRow` (`:928`), `ExecConsoleView` (`:967`), `CustomCommandsView` (`:1024`), `ShareView` (`:1052`), `ManageTabContent` (`:1132`). (These get replaced in Phase 2; moving them first keeps the diffs small.)

- [ ] **Step 3: Move Logs into `InspectorLogsTab.swift`**

`import SwiftUI`. Move verbatim (drop `private`): `LogsTabContent` (`:1158`).

- [ ] **Step 4: Compile and test**

Run: `swift build` → `Build complete!`
Run: `swift test --filter InspectorTabTests` → pass

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Views/Inspector/ Sources/DDEVUIApp/Views/ProjectInspectorView.swift
git commit -m "refactor: split inspector tabs into separate files"
```

---

## Phase 2 — Redesign

### Task 3: Header — move the thumbnail beside the title

Replace the stacked header (big thumbnail above the title block) with a horizontal layout: a smaller thumbnail beside the title/meta/path block.

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift` (the `header(_:)` function, currently `:231`)

- [ ] **Step 1: Replace the `header(_:)` body**

Replace the entire `header(_ project:)` function with:

```swift
private func header(_ project: DDEVProject) -> some View {
    HStack(alignment: .top, spacing: 16) {
        ProjectThumbnailView(
            thumbnail: viewModel.thumbnails[project.id],
            fallbackSymbol: project.projectType.symbol,
            cornerRadius: 9
        )
        .frame(width: 168, height: 96)
        .accessibilityLabel("Homepage preview for \(project.name)")

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(project.name)
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                ProjectStatusBadge(status: project.status)
            }

            HStack(spacing: 14) {
                Label(project.projectType.displayName, systemImage: project.projectType.symbol)
                if let php = project.phpVersion {
                    Label("PHP \(php)", systemImage: "swift")
                        .labelStyle(.titleAndIcon)
                }
                if project.mutagenEnabled {
                    Label("Mutagen", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .labelStyle(InspectorChipLabelStyle())

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.tertiary)
                Text(project.appRoot)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        Spacer(minLength: 0)
    }
}
```

- [ ] **Step 2: Compile**

Run: `swift build` → `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/DDEVUIApp/Views/ProjectInspectorView.swift
git commit -m "feat: inspector header — thumbnail beside title"
```

---

### Task 4: Action bar — fold Shell + Editor into a single "Open ▾" menu

The daily set keeps Open Site / lifecycle / Database. The two non-daily split buttons (Shell, Editor) collapse into one trailing `Open ▾` menu.

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift` (`primaryActionBar(_:)` `:279`; delete `shellSplitButton` `:345` and `editorSplitButton` `:374`)

- [ ] **Step 1: Replace the trailing buttons in `primaryActionBar`**

In `primaryActionBar(_:)`, replace the three trailing split-button calls:

```swift
                shellSplitButton(project, isRunning: isRunning)
                editorSplitButton(project)
                databaseSplitButton(isRunning: isRunning)
```

with:

```swift
                databaseSplitButton(isRunning: isRunning)
                openMenu(project, isRunning: isRunning)
```

- [ ] **Step 2: Add the `openMenu` function**

Add this method to `ProjectInspectorView` (replaces `shellSplitButton` + `editorSplitButton`, which you delete in Step 3):

```swift
/// Demoted launchers (shell + editor) — daily-but-not-primary, folded into one menu so they
/// don't eat the action bar.
private func openMenu(_ project: DDEVProject, isRunning: Bool) -> some View {
    Menu {
        Section("Shell") {
            ForEach(DDEVShellTarget.allCases) { target in
                Button {
                    workspaceOpener.openShell(in: project.appRoot, target: target)
                } label: {
                    Label(target.displayName, systemImage: target.systemImage)
                }
                .disabled(!isRunning)
            }
        }
        Section("Editor") {
            ForEach(viewModel.availableEditors) { editor in
                Button(editor.displayName) {
                    workspaceOpener.openFolder(project.appRoot, editor: editor)
                }
            }
        }
    } label: {
        Label("Open", systemImage: "arrow.up.forward.app")
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .controlSize(.large)
}
```

- [ ] **Step 3: Delete `shellSplitButton` and `editorSplitButton`**

Delete the `shellSplitButton(_:isRunning:)` and `editorSplitButton(_:)` functions entirely. Keep `databaseSplitButton(isRunning:)`.

- [ ] **Step 4: Compile**

Run: `swift build` → `Build complete!`
(If `EditorChoice` needs `Identifiable` for `ForEach` and isn't already, use `ForEach(viewModel.availableEditors, id: \.self)` instead — verify by building.)

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Views/ProjectInspectorView.swift
git commit -m "feat: fold shell + editor launchers into one Open menu"
```

---

### Task 5: URL quick-launch strip on the tab row

Add a persistent URL launcher to the right of the tab picker, fed by the shared `projectLaunchLinks` (minus `Primary`, which `Open Site` covers). Common links show as chip buttons; the rest fold into a `⋯` menu. Greyed out when the project is stopped.

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift` (the `tabPicker` computed property `:187`, used in `pinnedRegion` `:178`)

- [ ] **Step 1: Wrap the tab picker in a row with the URL strip**

In `pinnedRegion(_:)`, the line `tabPicker` stays, but change it to pass the project:

Replace `tabPicker` (in the `pinnedRegion` VStack) with `tabRow(project)`.

- [ ] **Step 2: Add `tabRow` and `urlStrip`**

Add these methods. `tabRow` keeps the existing segmented picker (and its unseen-log-activity dot, already inside `tabPicker`) on the left and adds the URL strip trailing:

```swift
private func tabRow(_ project: DDEVProject) -> some View {
    HStack(spacing: 10) {
        tabPicker
        Spacer(minLength: 8)
        urlStrip(project)
    }
}

/// Persistent quick-launch for the project's browser URLs, shown across every tab. `Primary` is
/// omitted (it's the Open Site button). Common links are chips; the remainder fold into a menu.
@ViewBuilder
private func urlStrip(_ project: DDEVProject) -> some View {
    let links = projectLaunchLinks(project, viewModel.selectedProjectDetails)
        .filter { $0.name != "Primary" }
    if !links.isEmpty {
        let inline = Array(links.prefix(3))
        let overflow = Array(links.dropFirst(3))
        HStack(spacing: 6) {
            Text("Open")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            ForEach(inline) { link in
                Button {
                    workspaceOpener.openURL(link.url)
                } label: {
                    Label(link.name, systemImage: link.systemImage)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if !overflow.isEmpty {
                Menu {
                    ForEach(overflow) { link in
                        Button {
                            workspaceOpener.openURL(link.url)
                        } label: {
                            Label(link.name, systemImage: link.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.small)
            }
        }
        .labelStyle(.titleAndIcon)
        .disabled(project.status != .running)
    }
}
```

- [ ] **Step 3: Compile**

Run: `swift build` → `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/DDEVUIApp/Views/ProjectInspectorView.swift
git commit -m "feat: pin URL quick-launch chips to the tab row"
```

---

### Task 6: Overview tab — card grid (Services / Database / Environment)

Rebuild `OverviewTabContent` as a 2-column card grid: Services + Database side by side, Environment full-width below. URLs are gone (now on the tab row). The Database card gains an "Open in TablePlus" header action; the "Enable XHGui" affordance moves into the Environment card.

**Files:**
- Modify: `Sources/DDEVUIApp/Views/Inspector/InspectorOverviewTab.swift` (replace `OverviewTabContent` body and its section helpers; keep `ServiceRow`/`ServiceHealthRow`)

- [ ] **Step 1: Replace `OverviewTabContent` with the card-grid version**

Replace the whole `OverviewTabContent` struct (keep `ServiceRow` and `ServiceHealthRow` below it unchanged) with:

```swift
struct OverviewTabContent: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel
    let workspaceOpener: MacWorkspaceOpener
    @Binding var showConfigEditor: Bool

    private var details: DDEVProjectDetails? { viewModel.selectedProjectDetails }

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                servicesCard
                databaseCard
            }
            GridRow {
                environmentCard
                    .gridCellColumns(2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Services

    @ViewBuilder
    private var servicesCard: some View {
        InspectorCard("Services") {
            if let details, !details.services.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(details.services) { service in
                        ServiceRow(service: service, workspaceOpener: workspaceOpener)
                    }
                    if let router = details.routerStatus {
                        ServiceHealthRow(label: "Router", status: router)
                    }
                    if let ssh = details.sshAgentStatus {
                        ServiceHealthRow(label: "SSH agent", status: ssh)
                    }
                }
            } else {
                Text(project.status == .running ? "Loading services…" : "Start the project to see its services.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Database credentials

    @ViewBuilder
    private var databaseCard: some View {
        let canOpenTool = project.status == .running && viewModel.effectiveDefaultDatabaseTool != nil
        InspectorCard(
            "Database",
            headerActionTitle: canOpenTool ? "Open in \(viewModel.effectiveDefaultDatabaseTool?.displayName ?? "client")" : nil,
            headerAction: canOpenTool ? { Task { await viewModel.launchDefaultDatabaseTool() } } : nil
        ) {
            if project.status == .running, let db = details?.databaseInfo {
                VStack(alignment: .leading, spacing: 6) {
                    CopyableRow(label: "Database", value: db.name)
                    CopyableRow(label: "Username", value: db.username)
                    CopyableRow(label: "Password", value: db.password, isSecret: true)
                    if let hostPort = details?.databaseHostPort {
                        CopyableRow(label: "Host", value: "127.0.0.1")
                        CopyableRow(label: "Port", value: hostPort)
                    } else {
                        Label(
                            "Database port is not published to the host. Use the Database button to open a client.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if viewModel.effectiveDefaultDatabaseTool == nil {
                        Label("Install TablePlus, Sequel Ace, Querious, or DBeaver to open databases here.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Start the project to see database credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Environment

    private var environmentCard: some View {
        InspectorCard("Environment") {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        envRow("PHP version") {
                            HStack(spacing: 6) {
                                Text(project.phpVersion ?? "Unknown")
                                    .font(.system(.body, design: .monospaced))
                                Menu {
                                    ForEach(viewModel.supportedPHPVersions, id: \.self) { version in
                                        Button("PHP \(version)") {
                                            Task { await viewModel.setPHPVersionForSelectedProject(version) }
                                        }
                                        .disabled(project.phpVersion == version)
                                    }
                                } label: { Text("Change") }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .disabled(viewModel.isSelectedProjectBusy)
                            }
                        }
                        envRow("Project type") {
                            Text(project.projectType.displayName).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        if !project.docroot.isEmpty {
                            envRow("Docroot") {
                                Text(project.docroot)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Color.clear.frame(height: 0)
                        }
                        if let mutagen = project.mutagenStatus, project.mutagenEnabled {
                            envRow("Mutagen") { Text(mutagen).foregroundStyle(.secondary) }
                        } else {
                            Color.clear.frame(height: 0)
                        }
                    }
                    if viewModel.selectedProjectXdebugEnabled != nil || viewModel.selectedProjectXHGuiEnabled != nil {
                        GridRow {
                            if let xdebugEnabled = viewModel.selectedProjectXdebugEnabled {
                                envRow("Xdebug") {
                                    Toggle("Xdebug", isOn: Binding(
                                        get: { xdebugEnabled },
                                        set: { newValue in Task { await viewModel.setXdebugForSelectedProject(newValue) } }
                                    ))
                                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                                    .disabled(viewModel.isSelectedProjectBusy)
                                }
                            } else {
                                Color.clear.frame(height: 0)
                            }
                            if let xhguiEnabled = viewModel.selectedProjectXHGuiEnabled {
                                envRow("XHProf (XHGui)") {
                                    Toggle("XHProf", isOn: Binding(
                                        get: { xhguiEnabled },
                                        set: { newValue in Task { await viewModel.setXHGuiForSelectedProject(newValue) } }
                                    ))
                                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                                    .disabled(viewModel.isSelectedProjectBusy)
                                }
                            } else {
                                Color.clear.frame(height: 0)
                            }
                        }
                    }
                }

                if project.xhguiStatus == .disabled {
                    Button {
                        Task { await viewModel.enableXHGuiForSelectedProject() }
                    } label: {
                        Label("Enable XHGui", systemImage: "chart.bar.xaxis")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(project.status != .running || viewModel.isSelectedProjectBusy)
                }

                HStack(spacing: 8) {
                    Button {
                        workspaceOpener.openFolder(project.appRoot + "/.ddev", editor: viewModel.effectiveDefaultEditor)
                    } label: { Label(".ddev/", systemImage: "folder") }
                    Button {
                        workspaceOpener.openFile(project.appRoot + "/.ddev/config.yaml", editor: viewModel.effectiveDefaultEditor)
                    } label: { Label("config.yaml", systemImage: "doc.text") }
                    Spacer()
                    Button {
                        showConfigEditor = true
                    } label: { Label("Edit Config", systemImage: "slider.horizontal.3") }
                    .disabled(viewModel.isSelectedProjectBusy)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func envRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        GridRow {
            EmptyView()
        }
        // Placeholder — replaced inline below; see note.
    }
}
```

> **Implementation note for `envRow`:** the helper above is a stub to keep the snippet compilable in isolation. Replace it with a plain label+value pair (not its own `GridRow`, since it's used *inside* `GridRow` columns):
>
> ```swift
> private func envRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
>     HStack(alignment: .firstTextBaseline, spacing: 8) {
>         Text(label).foregroundStyle(.secondary)
>         Spacer(minLength: 8)
>         trailing()
>     }
>     .font(.callout)
> }
> ```
>
> Use **this** version. Each `GridRow { envRow(...) ; envRow(...) }` then yields two columns. Verify alignment by building and eyeballing in Task 9; if the two-column `Grid` fights the `HStack` widths, fall back to a `VStack` of `envRow`s in one column (acceptable).

- [ ] **Step 2: Confirm `MacWorkspaceOpener` is passed**

`OverviewTabContent` is already constructed with `workspaceOpener:` and `showConfigEditor:` in `ProjectInspectorView.tabContent` (`:214`). No call-site change needed. Confirm `openFile(_:editor:)` and `openFolder(_:editor:)` exist on `MacWorkspaceOpener` (they're used in the original code, so they do).

- [ ] **Step 3: Compile**

Run: `swift build` → `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/DDEVUIApp/Views/Inspector/InspectorOverviewTab.swift
git commit -m "feat: Overview tab as Services/Database/Environment card grid"
```

---

### Task 7: Manage tab — Run card with `RunTarget` + unified runner (with unit test)

Introduce a pure `RunTarget` enum (unit-tested), then build the Run card: Framework commands dropdown (reused as-is), Custom commands as a dropdown, and one unified "Run a command" runner replacing `ToolRunnerView` + `ExecConsoleView`. Delete the replaced views.

**Files:**
- Create: `Sources/DDEVUIApp/Models/RunTarget.swift`
- Create: `Tests/DDEVUIAppTests/RunTargetTests.swift`
- Modify: `Sources/DDEVUIApp/Views/Inspector/InspectorManageTab.swift` (add Run card + runner; delete `ToolRunnerView`, `ToolRow`, `ExecConsoleView`, `CustomCommandsView`)

- [ ] **Step 1: Write the failing `RunTarget` test**

Create `Tests/DDEVUIAppTests/RunTargetTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

final class RunTargetTests: XCTestCase {
    func testWordPressTargetsAreToolsThenExecServices() {
        let targets = RunTarget.available(for: .wordpress)
        XCTAssertEqual(targets, [
            .tool(.composer), .tool(.npm), .tool(.wp),
            .exec(.web), .exec(.db)
        ])
    }

    func testDrupalIncludesDrush() {
        let targets = RunTarget.available(for: .drupal10)
        XCTAssertTrue(targets.contains(.tool(.drush)))
        XCTAssertFalse(targets.contains(.tool(.wp)))
    }

    func testLabelsAreNonEmptyAndDistinguishToolFromService() {
        XCTAssertEqual(RunTarget.tool(.composer).label, "Composer")
        XCTAssertEqual(RunTarget.exec(.web).label, "Web shell")
        XCTAssertFalse(RunTarget.exec(.db).label.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RunTargetTests`
Expected: FAIL — `cannot find 'RunTarget' in scope`.

- [ ] **Step 3: Implement `RunTarget`**

Create `Sources/DDEVUIApp/Models/RunTarget.swift`:

```swift
import Foundation

/// A single selectable target for the Manage tab's unified "Run a command" control. Either a
/// framework tool (`ddev <tool> …`) or a raw exec service (`ddev exec --service …`). Pure model so
/// the available-targets logic is unit-testable independent of the view model.
enum RunTarget: Hashable, Identifiable {
    case tool(DDEVTool)
    case exec(DDEVExecService)

    var id: String {
        switch self {
        case .tool(let t): "tool.\(t.rawValue)"
        case .exec(let s): "exec.\(s.rawValue)"
        }
    }

    var label: String {
        switch self {
        case .tool(let t): t.displayName
        case .exec(let s): "\(s.displayName) shell"
        }
    }

    var placeholder: String {
        switch self {
        case .tool(let t): t.placeholder
        case .exec: "e.g. ls -la"
        }
    }

    /// Tools relevant to the project type, followed by the raw exec services.
    static func available(for type: DDEVProjectType) -> [RunTarget] {
        DDEVTool.tools(for: type).map(RunTarget.tool) + DDEVExecService.allCases.map(RunTarget.exec)
    }
}
```

> Note the test expects `RunTarget.exec(.web).label == "Web shell"` — `DDEVExecService.web.displayName` is `"Web"`, so `"\(displayName) shell"` gives `"Web shell"`. ✔

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter RunTargetTests`
Expected: PASS.

- [ ] **Step 5: Replace the command views in `InspectorManageTab.swift`**

In `InspectorManageTab.swift`, **delete** `ToolRunnerView`, `ToolRow`, `ExecConsoleView`, and `CustomCommandsView`. Add the new Run card and runner:

```swift
/// Run card — framework + custom command dropdowns plus one unified runner (tools + exec).
struct RunCard: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    var body: some View {
        InspectorCard("Run", systemImage: "play.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Commands and tools run inside the project's containers. Output appears in the Logs tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Quick commands: framework dropdown (already a Menu) + custom dropdown.
                FrameworkCommandLauncherView(project: project, viewModel: viewModel)

                if !viewModel.customCommands.isEmpty {
                    Menu {
                        ForEach(viewModel.customCommands) { command in
                            Button {
                                Task { await viewModel.runCustomCommandForSelectedProject(command) }
                            } label: {
                                Label(command.name, systemImage: "terminal")
                            }
                            .help(command.description ?? "ddev \(command.name)")
                        }
                    } label: {
                        Label("Custom", systemImage: "star")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(viewModel.isSelectedProjectBusy)
                }

                RunCommandRow(project: project, viewModel: viewModel)

                if project.status != .running {
                    Text("Start the project to run commands.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// The unified runner: a target picker (tools + exec services) + an arguments field + Run.
private struct RunCommandRow: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    @State private var target: RunTarget
    @State private var args = ""

    init(project: DDEVProject, viewModel: ProjectDashboardViewModel) {
        self.project = project
        self.viewModel = viewModel
        _target = State(initialValue: RunTarget.available(for: project.projectType).first ?? .exec(.web))
    }

    private var targets: [RunTarget] { RunTarget.available(for: project.projectType) }

    private var canRun: Bool {
        project.status == .running
            && !viewModel.isSelectedProjectBusy
            && !args.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("Target", selection: $target) {
                ForEach(targets) { t in
                    Text(t.label).tag(t)
                }
            }
            .labelsHidden()
            .fixedSize()

            TextField(target.placeholder, text: $args)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(run)

            Button("Run", action: run)
                .buttonStyle(.borderedProminent)
                .disabled(!canRun)
        }
    }

    private func run() {
        guard canRun else { return }
        let toRun = args
        let chosen = target
        Task {
            switch chosen {
            case .tool(let tool):
                await viewModel.runToolForSelectedProject(tool, argumentString: toRun)
            case .exec(let service):
                await viewModel.runExecForSelectedProject(command: toRun, service: service)
            }
        }
    }
}
```

- [ ] **Step 6: Compile and test**

Run: `swift build` → `Build complete!`
Run: `swift test --filter RunTargetTests` → PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/DDEVUIApp/Models/RunTarget.swift Tests/DDEVUIAppTests/RunTargetTests.swift Sources/DDEVUIApp/Views/Inspector/InspectorManageTab.swift
git commit -m "feat: unified Run card with RunTarget (replaces tool rows + exec box)"
```

---

### Task 8: Manage tab — Database + Project grouped cards, wired into `ManageTabContent`

Group the remaining Manage sections into two cards and lay the Manage tab out as: Run (full width) on top, Database + Project side by side beneath. The grouped sub-views (`DatabaseOperationsView`, `SnapshotManagerView`, `ShareView`, `AddonManagerView`) are reused as-is.

**Files:**
- Modify: `Sources/DDEVUIApp/Views/Inspector/InspectorManageTab.swift` (replace `ManageTabContent`)

- [ ] **Step 1: Replace `ManageTabContent`**

Replace the `ManageTabContent` struct with:

```swift
struct ManageTabContent: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RunCard(project: project, viewModel: viewModel)

                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        InspectorCard("Database", systemImage: "cylinder.split.1x2") {
                            VStack(alignment: .leading, spacing: 12) {
                                DatabaseOperationsView(project: project, viewModel: viewModel)
                                SnapshotManagerView(project: project, viewModel: viewModel)
                            }
                        }
                        InspectorCard("Project", systemImage: "gearshape") {
                            VStack(alignment: .leading, spacing: 12) {
                                ShareView(project: project, viewModel: viewModel)
                                AddonManagerView(project: project, viewModel: viewModel)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }
}
```

> **Note on nested section headers:** `DatabaseOperationsView`, `SnapshotManagerView`, `ShareView`, and `AddonManagerView` currently render their own `InspectorSection("…")` titles internally. Inside the new cards that produces a card title plus an inner section title (e.g. card "Database" → inner "Database"/"Files"/"Snapshots"). That's acceptable and actually reads as sub-sections. If it looks heavy in Task 9, the lightweight fix is to drop the outer `InspectorCard` title text for those two cards (pass an empty grouping) — decide visually, do not restructure the sub-views.

- [ ] **Step 2: Compile**

Run: `swift build` → `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/DDEVUIApp/Views/Inspector/InspectorManageTab.swift
git commit -m "feat: Manage tab as Run / Database / Project cards"
```

---

### Task 9: Full verification pass

No code unless a defect is found. Build everything, run the whole test suite, then drive the real app and walk the checklist.

**Files:** none (verification only).

- [ ] **Step 1: Full build + full test suite**

Run: `swift build` → `Build complete!`
Run: `swift test` → all pass (specifically `InspectorTabTests`, `ProjectLaunchLinksTests`, `RunTargetTests`, and the pre-existing suite).

- [ ] **Step 2: Build the app bundle and drive it (per the `verify-ddevui-app` memory)**

Build a bundle via `xcodebuild` (not `swift run` — it crashes on `UNUserNotificationCenter`), launch it, **foreground it before judging state**, and drive with cua-driver.

- [ ] **Step 3: Manual checklist — walk a running project**

  - Header: thumbnail sits beside the title; status/meta/path correct.
  - Action bar: `Open Site`, `Restart`/`Stop`, `Database` (default + menu of tools), and `Open ▾` (Shell web/db/MySQL + each editor) all fire.
  - Tab-row URL strip: chips open the right URLs; overflow `⋯` holds the rest; **Primary is not duplicated**; whole strip greys out when the project is stopped.
  - Overview: Services / Database / Environment cards render in the grid; credentials copy + reveal work; "Open in <tool>" launches; PHP `Change`, Xdebug/XHProf toggles, `.ddev/`·`config.yaml`·`Edit Config`, and `Enable XHGui` (when disabled) all work.
  - Manage: Framework ▾ + Custom ▾ dropdowns run; the unified runner runs a tool (composer) and an exec (web/db) with output landing in Logs; Import/Export, Snapshots, Share, Add-ons all reachable.
  - Logs: unchanged (viewer + command history).
  - Resize the pane narrow: Overview and Manage grids reflow to a single column without clipping.

- [ ] **Step 4: Commit any fixes**

If Step 3 surfaced defects, fix them with focused commits (`fix: …`), then re-run Steps 1–3.

---

## Self-review (completed by plan author)

**Spec coverage:** Header beside-title (T3) ✓ · action bar daily set + Open menu (T4) ✓ · URL strip pinned, Primary excluded, greyed when stopped (T5) ✓ · Overview 3-card grid with Open-in-TablePlus (T6) ✓ · Manage 3 grouped cards (T7, T8) ✓ · Framework/Custom dropdowns + merged runner (T7) ✓ · Logs unchanged (untouched) ✓ · file split of the 1348-line view (T1, T2) ✓ · no feature removed (all sibling views reused; tool rows/exec merged not dropped) ✓ · toolbar More menu untouched (never modified) ✓.

**Placeholder scan:** The only stub is `envRow` in T6 Step 1, deliberately flagged with the correct replacement in the following note (the isolated snippet wouldn't compile otherwise). No "TBD/handle errors/similar to" placeholders.

**Type consistency:** `RunTarget` cases `.tool(DDEVTool)`/`.exec(DDEVExecService)`, `.available(for:)`, `.label`, `.placeholder` are used identically in the test (T7 S1), the model (T7 S3), and the runner (T7 S5). View-model calls (`runToolForSelectedProject(_:argumentString:)`, `runExecForSelectedProject(command:service:)`, `launchDefaultDatabaseTool()`, `enableXHGuiForSelectedProject()`, `setPHPVersionForSelectedProject(_:)`, `setXdebugForSelectedProject(_:)`, `setXHGuiForSelectedProject(_:)`) match the verified signatures. Sibling-view initializers `(project:viewModel:)` match. `projectLaunchLinks(_:_:)` is left untouched and filtered at the call site to satisfy `ProjectLaunchLinksTests`.
