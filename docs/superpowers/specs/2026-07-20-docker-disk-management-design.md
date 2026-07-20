# Docker Disk Management — Design

**Date:** 2026-07-20
**Status:** Proposed (pre-implementation)

## Problem

DDEV project starts fail outright when the Docker VM's disk fills. The failure is
opaque: Mutagen reports `mkdir /home/dave/.mutagen: no space left on device`, which
names neither the real cause nor the fix. Recovery today means dropping to a terminal
and running `docker builder prune` / `docker image prune` by hand.

This keeps recurring because nothing in the app watches headroom, and because the
existing **Delete DDEV Images** button looks like a cleanup tool while covering only a
fraction of what accumulates.

Real measurements from the 2026-07-20 incident (34 registered projects):

| Category | Size | Notes |
| --- | --- | --- |
| Mutagen sync volumes (37) | 24.2 GB | Disposable — rebuilt on next start |
| Database volumes (37) | 15.9 GB | Real data, must be protected |
| Images | 41.5 GB | 18.6 GB reclaimable |
| Build cache | 6.0 GB | Fully disposable |

The dominant consumer is **Mutagen sync cache for projects that aren't even running** —
precisely the category no existing button touches. `ddev delete images` would have freed
a subset of one of four categories and left the start still failing.

Three projects (`davidsonbuilding`, `nairngolfclub`, `westlife`) have volumes but no
registered DDEV project — orphaned leftovers, including their databases.

## Goals

- **Warn before the failure**, via the menu bar, with enough headroom left to act.
- **Explain what is consuming the disk**, broken down by category and by project.
- **Offer a one-click safe reclaim** that cannot destroy a database.
- **Allow deliberate per-item removal** of databases and orphans, behind explicit confirmation.
- **Collapse the overlapping existing buttons** into this one coherent surface.

## Non-Goals

- **Automatic/scheduled reclaim.** Every destructive action is user-initiated. No background deletion, ever.
- **Managing Docker VM disk allocation.** Resizing `Docker.raw` is Docker Desktop's job; we report, we don't resize.
- **Non-DDEV Docker workloads.** Unused images are reclaimed globally (that's what `docker image prune` does), but volume classification and per-project grouping are DDEV-shaped only.
- **Database backup before deletion.** DDEV already has `ddev snapshot` and the app already exposes it. Deleting a database points at that; it doesn't reimplement it.
- **Undo.** Reclaim is not reversible. Safety comes from what we refuse to include in a bulk plan, not from rollback.

## Decisions (locked during brainstorming)

1. **Two surfaces, warning-first.** A menu bar badge is the proactive signal; a dedicated
   sidebar screen is the destination. The menu bar never executes reclaim directly — it
   opens the screen with the plan pre-computed.
2. **Safe-by-default bulk reclaim.** One button covering build cache, unused images, stale
   DDEV images, and Mutagen volumes for stopped projects. Databases for registered
   projects are structurally excluded.
3. **Single confirmation showing the itemised plan** before executing. Not per-category.
4. **Headroom via `df` inside a container**, not by stat-ing `Docker.raw`.
5. **`ddev mutagen reset <project>` preferred** over raw `docker volume rm` for registered
   projects, so DDEV's own state stays consistent. Raw removal only for orphans.
6. **Thresholds 85% (warn) / 93% (critical)**, both overridable in `PreferencesModel`.
7. **Absorb both existing global buttons.** `Delete DDEV Images` becomes a line item in the
   reclaim plan; `Download Images` moves to the screen as a separate "Prefetch images"
   maintenance action. The `ContentView` toolbar entries and their confirmation dialog are
   removed; the underlying service methods are unchanged.

## Architecture

Three new units, each testable in isolation.

### `Services/DockerSystemService.swift`

Mirrors `DDEVCommandService`: injected `CommandRunning` + `DockerExecutableResolver`,
returns decoded models. Consumed through a `DockerSystemServicing` protocol declared at
the top of the view-model file, matching the existing `DDEVServicing` convention.

```swift
public protocol DockerSystemServicing: Sendable {
    func usage() async throws -> DockerUsage
    func headroom() async throws -> DockerHeadroom
    func volumes() async throws -> [DockerVolume]
    func removeVolumes(_ names: [String]) async -> [VolumeRemovalResult]
    func pruneBuildCache() async throws -> CommandResult
    func pruneUnusedImages() async throws -> CommandResult
}
```

| Method | Command | Cost |
| --- | --- | --- |
| `usage()` | `docker system df --format json` | fast |
| `headroom()` | `docker exec <running container> df -Pk /` | ~free |
| `headroom()` fallback | throwaway volume + `df -Pk` in a local image | seconds |
| `volumes()` | `docker system df -v` | **seconds — on-demand only** |
| `pruneBuildCache()` | `docker builder prune -af` | slow |
| `pruneUnusedImages()` | `docker image prune -af` | slow |

`docker system df --format json` emits one JSON object per line for Images, Containers,
Local Volumes, Build Cache. Sizes arrive as human strings (`"42.37GB"`), so parsing needs
a unit-suffix decoder, not `Int64(...)`.

The headroom probe reads the *VM's* overlay filesystem, which is the number that actually
governs failure. Both probe paths were verified to agree exactly:

```
overlay  98759140k total  66888912k used  26820732k avail  71%  /
```

**Division of labour with `DDEVCommandService`.** `DockerSystemService` owns only what
DDEV cannot express. Two plan items are executed by the *existing* `DDEVServicing`
methods, not reimplemented here:

| Plan item | Executed by |
| --- | --- |
| Stale DDEV images | `DDEVServicing.deleteImages()` — existing, unchanged |
| Prefetch images | `DDEVServicing.downloadImages()` — existing, unchanged |
| Mutagen volume, registered project | `ddev mutagen reset <project>` — **new** `DDEVServicing.mutagenReset(project:)` |
| Mutagen volume, orphaned project | `DockerSystemService.removeVolumes()` |
| Database volume (per-item only) | `DockerSystemService.removeVolumes()` |
| Build cache, unused images | `DockerSystemService` |

So `removeVolumes()` is the raw-Docker escape hatch used **only** where no DDEV project
exists to reset, or for a deliberate per-item database removal. `mutagenReset(project:)`
is the one addition to `DDEVCommandService`; it requires the project to be stopped, which
the planner already guarantees.

### `Services/ReclaimPlanner.swift` — pure, no I/O

The safety brain. Input: volumes, the DDEV project list, running container names. Output:
a classified inventory and a `ReclaimPlan`.

```swift
enum VolumeKind { case mutagen, database, other }
enum ProjectState { case running, stopped, orphaned }
```

Classification is by **exact suffix strip then exact-set membership**, never prefix
matching: `<name>_project_mutagen` → `<name>`, `<name>-mariadb` → `<name>`, then look
`<name>` up in the project set. Prefix matching would misclassify real project pairs —
`thethreeswords` and `thethreeswordsguiseley` both exist.

**The safety rule, defined once and enforced only here:**

> A volume is bulk-eligible if and only if it is `.mutagen` and not `.running`, **or** it
> belongs to an `.orphaned` project. A `.database` volume for a registered project is never
> in a bulk plan.

Keeping this pure means the entire safety policy is unit-testable without Docker running.

### `ViewModels/DockerDiskViewModel.swift`

Owns poll state; publishes `headroom`, `usage`, `plan`, `inventory`. Executes reclaim
through the existing `CommandScheduler` actor so it cannot interleave with project
start/stop mutations.

### Data flow

```
refresh cycle ─→ DockerSystemService.headroom()      (cheap, always)
                          │
screen open  ─→ .usage() + .volumes()                (expensive, on demand)
                          │
                          ▼
                 ReclaimPlanner.plan(from:)          (pure)
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
      menu bar badge          Docker Disk screen
```

## UI

### Menu bar — primary warning surface

`MenuBarExtra` icon switches from `shippingbox.fill` to `exclamationmark.triangle.fill`,
tinted warning at 85% and red at 93%. `MenuBarContentView` gains a headroom row above the
project list. **Below the warning threshold the row is absent entirely** — no clutter in
the normal case.

```
▾ DDEVUI  ⚠️
────────────────────────────
 Docker disk  91% · 8.2 GB free
 Reclaim ~30 GB…                →
────────────────────────────
 aqua-pura              ● running
```

"Reclaim…" opens the main window on the Docker Disk screen. It does not execute — a
destructive bulk operation should not be one hover-twitch away.

### Docker Disk screen

New `ProjectSidebarItem.dockerDisk` ("Docker Disk", `internaldrive`), built on the
`DiagnosticsView` full-pane template (`ScrollView` → `VStack(spacing: 22)` →
`.sectionHeaderStyle()` sections).

1. **Headroom** — capacity bar, `66.9 GB of 98.8 GB used · 26.8 GB free`, threshold-tinted.
2. **Breakdown** — Images / Containers / Volumes / Build Cache, size and reclaimable.
3. **Reclaim safely** — the itemised plan and the single primary button.
4. **All volumes** — per-item list grouped by project, showing kind and state. Databases
   individually selectable, each behind its own `confirmationDialog` naming the project.
5. **Maintenance** — "Prefetch images", visually separated, labelled as *consuming* space.

Orphaned projects render as a visually distinct group noted as "no longer a DDEV project" —
the one context where deleting a database is reasonable.

`ByteCountFormatter` has no existing use in the codebase; this introduces an
`Int64.formattedBytes` helper in `Utilities/` for consistency across all sections.

### Thresholds and polling

Warn **85%**, critical **93%**, both in `PreferencesModel`. 85% of ~99 GB leaves ~15 GB —
roughly two project starts of headroom, enough to act without crying wolf. (DDEV's own
warning fires at 5 GB free, which proved too late to be useful.)

Headroom piggybacks on the existing project refresh cycle plus one check at launch; no new
timer. The expensive `volumes()` walk runs only when the screen is open or on explicit
refresh — never on the background cycle.

## Error handling

| Failure | Behaviour |
| --- | --- |
| Docker daemon down | Existing `PrerequisiteSheet` path. No disk row, no warning. Never warn about disk we can't measure. |
| Headroom probe fails (no running container **and** fallback fails) | Show `docker system df` totals only; capacity bar replaced by "headroom unavailable". **A failed probe must never read as 0% free** and trigger a false critical warning. |
| Partial reclaim failure (volume became in-use mid-run) | Continue the batch; report per-item results. One stuck volume neither aborts the run nor leaves ambiguity about what happened. |
| Unparseable CLI output | Typed `DockerSystemError.malformedOutput`, surfaced via the existing `error.presentableMessage`. |

All reclaim runs through `CommandScheduler`.

## Testing

Following the established `RecordingCommandRunner` argv-assertion pattern (XCTest).

**`DockerSystemServiceTests`**
- Exact argv for each command.
- `docker system df --format json` parsing against a fixture captured from the real
  2026-07-20 output, stored in `Tests/DDEVUIAppTests/Fixtures/docker-system-df.json` and
  declared as a `.copy` resource in `Package.swift`.
- Human-readable size parsing: `GB` / `MB` / `kB` / `B` suffixes.
- `df -Pk` parsing: header line skipped, `1024-blocks` converted to bytes.

**`ReclaimPlannerTests`** — the safety-critical suite, pure and Docker-free.
- Running project's mutagen volume is excluded.
- Stopped project's mutagen volume is included.
- Registered project's database is never in a bulk plan.
- Orphaned project's database *is* offered.
- `thethreeswords` vs `thethreeswordsguiseley` are not confused by suffix stripping.
- Unrecognised volume shapes fall to `.other` and are never bulk-eligible.
- A stopped registered project's mutagen volume routes to `mutagenReset`, not `removeVolumes`;
  an orphan's routes to `removeVolumes`. (Guards decision 5 against regression.)

**`DockerDiskViewModelTests`**
- Threshold crossings at 85 / 93 drive the correct badge state.
- A failed headroom probe produces no warning.

## Open risks

- **`docker system df -v` latency** on a machine with 100+ volumes is seconds, not
  milliseconds. Mitigated by making it on-demand, but the screen needs a visible loading
  state rather than appearing hung.
- **`docker system df` size strings are locale/format-dependent** across Docker versions.
  The fixture pins today's format; schema drift surfaces as a typed error rather than
  silently wrong numbers.
- **OrbStack vs Docker Desktop** may differ in how the VM filesystem presents. Both probe
  paths should be verified on OrbStack before release; `DockerRuntime` already distinguishes them.
