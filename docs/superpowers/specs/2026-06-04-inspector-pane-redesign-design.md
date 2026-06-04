# Project Inspector Pane Redesign — Design

**Date:** 2026-06-04
**Status:** Proposed (pre-implementation)

## Problem

The right-hand inspector pane reads as a "scatter shot of every idea in one place" rather than a considered tool. Concretely:

- **Database is fragmented across three locations.** Launch-the-GUI lives in the action bar, credentials live on the Overview tab, and import/export + snapshots live on the Manage tab. The user's single most frequent area is the most scattered.
- **The action bar wastes prime real estate on non-daily actions.** Shell and "open in editor" sit front-and-centre, while the things actually used daily aren't all promoted.
- **Content dribbles one-item-per-row.** The Overview tab renders ~12 full-width label/value rows; small pieces of text each consume a whole row instead of using horizontal space.
- **The Manage tab is a pile of 8 stacked sections** (Framework Commands, Custom Commands, Tools, Run Command/exec, Database Import/Export, Share, Snapshots, Add-ons) in a single scroll, with repeating loops of buttons.

This is an information-architecture and layout problem, not a missing-feature problem.

## Goals

- **Reflect actual usage.** Promote the user's daily drivers — **Open Site, Start/Stop/Restart, Database (TablePlus), Logs** — and demote everything else.
- **Un-scatter the database.** Day-to-day GUI launch stays a permanent top-level button; credentials stay glanceable on Overview; setup-time import/export + snapshots are grouped together on Manage. Each lives in exactly one sensible place.
- **Replace one-per-row dribble with a card grid** on the Overview tab.
- **Collapse the Manage pile into 3 grouped cards**, turning repeating button loops into dropdowns and merging the two "type a command" tools into one runner.
- **Pin frequently-clicked URLs** to the right of the tab strip so they're reachable from any tab.
- **No feature loss.** Everything currently reachable stays reachable.
- **Split the 1348-line `ProjectInspectorView.swift`** into focused files as part of the work.

## Non-Goals

- **No changes to the sidebar, project list, or top toolbar.** Scope is the inspector pane only. The top-right toolbar **More** menu (Move to Group, Unlink, Delete DDEV Data, Move Source to Trash) is untouched.
- **No new DDEV capabilities.** Pure reorganisation + layout.
- **No change to the Logs tab's behaviour.** It may receive the same card-styling polish, but its content (log viewer + command history) and logic are unchanged.
- **No change to the underlying view model API/commands.** This is a view-layer redesign; `ProjectDashboardViewModel` methods are reused as-is. (The merged runner is a view-layer composition over existing `runToolForSelectedProject` / `runExecForSelectedProject`.)
- **No change to capture/thumbnail logic** from the website-thumbnails work — the thumbnail simply moves position within the header.

## Decisions (locked during brainstorming)

1. **Scope = the whole inspector pane** (header, action bar, all three tabs), kept at **3 tabs** (refined "Approach A"). A dedicated Database tab was considered and rejected: database import/export is setup-time, not daily, so a DB tab would be rarely opened.
2. **Daily set** (from the user's own selection): Open Site · Start/Stop/Restart · Database GUI · Logs. DB import/export and the TablePlus GUI were initially flagged daily; clarified that **import/export is new-site-setup only**, while the **TablePlus GUI is used regularly** for quick edits. Shell and editor are **not** daily.
3. **Header:** homepage thumbnail moves **beside** the title (was a full-width ~360×200 hero) to reclaim vertical space; status badge, meta chips (type · PHP · Mutagen), folder path retained.
4. **Action bar = daily set only:** `Open Site` (primary) · `Restart`/`Stop` (or `Start`) · **`Database ▾`** (split: launch default DB tool + menu of other tools) · spacer · **`Open ▾`** (shell targets + editor with editor choices). Shell & editor demoted into `Open ▾`.
5. **URLs pinned to the tab row:** right-aligned quick-launch chips for common destinations (HTTPS, Mailpit, XHGui…), with HTTP + add-on service UIs folded into a `⋯` overflow menu so the row never wraps. **Primary** is not duplicated (it's the `Open Site` button). Chips are **greyed out (disabled) when the project is stopped.**
6. **Overview tab = 3 cards in a grid:** **Services** + **Database (credentials)** side by side, **Environment** full-width beneath (two-column interior). The URLs card is removed (now on the tab row).
7. **Manage tab = 3 grouped cards:** **Run** (full-width), **Database** (import/export + snapshots), **Project** (share + add-ons).
8. **Repeating button loops → dropdowns:** Framework commands stays a dropdown; **Custom commands becomes a dropdown** (`Custom ▾`) instead of a wrapped button row.
9. **Merged runner:** the per-tool rows (composer/npm/drush/wp) **and** the separate exec box collapse into a **single "Run a command"** control — a target picker (`composer · npm · drush · wp · web · db`) + an arguments field + Run. Chosen explicitly over keeping tools visible.
10. **Logs tab unchanged.**

## Architecture

### Information architecture (target)

```
Pinned region (every tab)
├─ Header        thumbnail │ title + status badge │ meta chips │ folder path
├─ Action bar    Open Site │ Restart/Stop(/Start) │ Database ▾ │ ··· │ Open ▾
├─ DB drift banner (conditional)
└─ Tab row       [Overview | Manage | Logs]            …right→  Open: HTTPS · Mailpit · XHGui · ⋯ ▾

Overview tab (inspect)                Manage tab (do)                 Logs tab
┌────────────┬────────────┐          ┌──────────────────────────┐    (unchanged)
│ Services   │ Database   │          │ ▶ Run (full width)       │    log viewer +
│            │ (creds)    │          ├─────────────┬────────────┤    command history
├────────────┴────────────┤          │ 🛢 Database │ ⚙ Project  │
│ Environment (full width) │          └─────────────┴────────────┘
└─────────────────────────┘
```

### Shared component: `InspectorCard`

A new reusable card replacing/augmenting today's `InspectorSection` (which is just a header + content with no container). Signature roughly:

```swift
private struct InspectorCard<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var headerAction: (() -> Void)? = nil      // e.g. "Open in TablePlus"
    var headerActionLabel: String? = nil
    @ViewBuilder let content: Content
}
```

Renders a titled, bordered, rounded container (matching the app's existing `glassEffect`/rounded-rect idiom) with an optional trailing header action. Used by every Overview and Manage card so spacing/typography are consistent.

### Overview tab

- **Layout:** a 2-column grid. SwiftUI `Grid` (or a small wrapper) with Services + Database in row 1 and Environment spanning both columns in row 2. Collapses to a single column when the pane is narrow.
- **Services card:** the existing `ServiceRow` / `ServiceHealthRow` list (per-service health + ports, router, ssh-agent), moved into a card. Logic unchanged.
- **Database card:** the existing `CopyableRow` credentials (database / username / password-masked / host:port), plus a header action **"Open in TablePlus"** wired to `viewModel.launchDefaultDatabaseTool()`. Only shown when `project.status == .running` and `details?.databaseInfo` exists (unchanged condition). When no DB tool is installed, the existing "Install TablePlus…" hint shows here.
- **Environment card (full width):** PHP version + `Change ▾` menu, project type, docroot, mutagen status, Xdebug toggle, XHProf toggle — arranged in a **two-column** interior grid instead of one `metaRow` per line — plus the `.ddev/` · `config.yaml` · `Edit Config` buttons. Logic unchanged.

### Manage tab

- **Layout:** Run card full-width on top; Database + Project cards side by side beneath (single column when narrow).
- **Run card:**
  - *Quick commands* row: the existing `FrameworkCommandLauncherView` dropdown + a new **`Custom ▾`** dropdown built from `viewModel.customCommands` (replaces `CustomCommandsView`'s wrapped button row). Both hidden when empty / not applicable, as today.
  - *Run a command* row: a **new unified runner** view replacing `ToolRunnerView` + `ExecConsoleView`. A target `Picker` enumerates the framework tools (`DDEVTool.tools(for: project.projectType)`) and the exec services (`DDEVExecService.allCases`, i.e. web/db). The arguments `TextField` + Run button dispatch to:
    - `runToolForSelectedProject(tool, argumentString:)` when the target is a tool, or
    - `runExecForSelectedProject(command:service:)` when the target is a service.
  - Disabled / "start the project" messaging preserved from the originals.
- **Database card:** the existing `DatabaseOperationsView` (import/export) + `SnapshotManagerView` (create/restore/list/clean-up), grouped under one card with two labelled sub-sections. Logic unchanged.
- **Project card:** the existing `ShareView` + `AddonManagerView`, grouped. Logic unchanged.

### Pinned region

- **Header:** restructure `header(_:)` so `ProjectThumbnailView` sits in an `HStack` beside the title/meta block (smaller, ~16:10, capped width) rather than stacked above it.
- **Action bar:** keep `Open Site` / lifecycle / `Database` split button; **remove** the standalone `shellSplitButton` and `editorSplitButton` from the bar and fold them into a single **`Open ▾`** menu (shell targets via `DDEVShellTarget`, editors via `viewModel.availableEditors`). The bar keeps its `glassEffect` container.
- **URL quick-launch strip:** new view in the tab row, right-aligned, built from the shared `projectLaunchLinks(project, details)` (minus the Primary entry, which `Open Site` covers). Show the first N as chips; overflow into a `⋯` menu. Disabled when `project.status != .running`. This reuses the existing single source of truth so the strip and the toolbar Open menu can't drift.
- **Tab row:** `tabPicker` (segmented) stays on the left with its unseen-log-activity dot; the URL strip is added trailing in the same row.

### File split

Split `Sources/DDEVUIApp/Views/ProjectInspectorView.swift` (1348 lines) into a folder of focused files (names indicative):

- `ProjectInspectorView.swift` — the pane shell: tab state, `pinnedRegion`, `tabContent` switch, toolbar `More` menu, sheets/confirmations.
- `InspectorHeaderBar.swift` — `header`, action bar, `Open ▾`, `Database`/lifecycle buttons, URL quick-launch strip, `DBDriftBanner`, `ProjectStatusBadge`.
- `InspectorOverviewTab.swift` — Overview cards (Services / Database creds / Environment), `ServiceRow`, `ServiceHealthRow`, `CopyableRow`.
- `InspectorManageTab.swift` — Run card + unified runner, regrouped Database/Project cards.
- `InspectorLogsTab.swift` — `LogsTabContent` + command history.
- `InspectorComponents.swift` — `InspectorCard`, `InspectorSection` (if still needed), `LaunchLink` + `projectLaunchLinks`, `FlowLayout`/`FlowHStack`, label styles, `SourceFolderDeleteSheet`.

`ToolRunnerView`, `ToolRow`, `ExecConsoleView`, and `CustomCommandsView` are **replaced** by the Run card + unified runner and deleted.

## Edge cases

- **Project stopped:** URL chips greyed/disabled; Database credentials card hidden (no `databaseInfo`); action-bar lifecycle shows `Start`; Run/Manage actions show their existing "start the project" hints.
- **No URLs exposed:** strip is empty/hidden (don't render an empty "Open" label).
- **Many URLs / add-on UIs:** beyond N chips, the rest fold into the `⋯` overflow menu; the row never wraps.
- **No custom commands:** `Custom ▾` hidden (as today).
- **No DB tool installed:** Database action button disabled + the existing install hint shown in the Overview Database card.
- **No snapshots / no add-ons:** existing empty states preserved inside their grouped card.
- **Narrow pane:** Overview and Manage grids collapse to a single column.
- **Tab switch / project switch:** selection resets to Overview and unseen-log-activity logic unchanged.

## Risks & mitigations

- **Behaviour change: merged runner.** The biggest functional change. Mitigation: it composes over the *existing* view-model methods (no new command logic), the target picker exposes the same tools/services as before, and disabled/empty messaging is preserved. Discoverability trade-off accepted explicitly by the user.
- **Large refactor / regression risk.** Mitigation: keep `ProjectInspectorView`'s public surface and the `InspectorTab` enum stable so `ProjectInspectorTabTests.swift` keeps passing; move logic verbatim into new files before re-layouting; build + manual pass per tab.
- **Grid behaviour at narrow widths.** Mitigation: explicit single-column fallback; verify against the smallest practical pane width.
- **Scope creep into the Logs tab / sidebar.** Mitigation: Non-Goals fence it off; Logs gets styling parity at most.

## Testing

- **Existing:** `ProjectInspectorTabTests.swift` must continue to pass (tab enum / display names / system images unchanged).
- **Manual verification (per `verify-ddevui-app` memory — build a bundle via xcodebuild, drive with cua-driver, foreground before judging):**
  - Header: thumbnail beside title; status/meta/path correct.
  - Action bar: Open Site / lifecycle / Database split / `Open ▾` (shell targets + editors) all fire.
  - URL strip: chips open correct URLs; overflow menu holds the rest; greyed when stopped.
  - Overview: Services / Database (with "Open in TablePlus") / Environment cards render in the grid; credentials copy + reveal work; PHP `Change`, Xdebug/XHProf toggles work.
  - Manage: Framework ▾ + Custom ▾ dropdowns; unified runner runs a tool (composer) and an exec (web/db) with output landing in Logs; import/export, snapshots, share, add-ons all reachable.
  - Logs: unchanged.
  - Narrow-pane single-column reflow.
- **New unit tests** only if the unified runner gains non-trivial target→dispatch logic worth isolating (e.g. a small enum/helper mapping a picked target to the right view-model call); otherwise this is view-layer and covered by manual verification.

## File structure

- **Create:** `Sources/DDEVUIApp/Views/Inspector/` containing `ProjectInspectorView.swift`, `InspectorHeaderBar.swift`, `InspectorOverviewTab.swift`, `InspectorManageTab.swift`, `InspectorLogsTab.swift`, `InspectorComponents.swift` (or keep flat in `Views/` with `Inspector…` prefixes — decide in the plan).
- **Modify:** none of the sibling feature views' logic changes; they're recomposed into cards (`FrameworkCommandLauncherView`, `DatabaseOperationsView`, `SnapshotManagerView`, `ShareView`, `AddonManagerView`, `LogsViewerView`, `CommandOutputView` reused as-is).
- **Delete:** `ToolRunnerView`/`ToolRow`, `ExecConsoleView`, `CustomCommandsView` (replaced by the Run card + unified runner + `Custom ▾`).
- **Tests:** keep `ProjectInspectorTabTests.swift`; add a small runner-dispatch test if the helper warrants it.
