# Website Thumbnails — Design

**Date:** 2026-06-04
**Status:** Proposed (pre-implementation)

## Problem

When you open a project's overview you can't confirm at a glance that it's the *right* site. With many similarly-named client projects (`acme-staging` vs `acme-prod`, or cryptic names), the project name and type icon are weak identity cues. A screenshot of the site's homepage is a strong visual fingerprint — you recognise the actual page, not a label.

## Goals

- Capture a **screenshot of each project's homepage** (`primaryURL`) and use it as a visual identity cue.
- Show it **large in the inspector Overview header** — the view that actually confirms "yes, right site."
- Show it **small in the list row, replacing the project-type icon** when a thumbnail exists (grown to ~36pt row height); fall back to the existing `projectType.symbol` when there isn't one. No new horizontal space.
- **Cache thumbnails to disk** so:
  - **stopped** projects (which have no reachable URL) still show their last-known homepage, and
  - launch **paints cached thumbnails instantly** (cached-first, like the project list).
- Capture **cheaply and rarely**: on app launch for running projects that lack a thumbnail, and when a project transitions **stopped → running**. Never on a timer, never per-selection.

## Non-Goals

- **Live / continuously-refreshed thumbnails.** These are *indicators*, not live views. A running site's thumbnail refreshes only when it's (re)started — or on first launch if missing.
- **Capturing stopped projects.** Impossible — a stopped project has no reachable homepage. The disk cache is their only source.
- **Stale styling / dimming.** Always show the newest thumbnail we have, plainly.
- **Full-page / scroll capture.** Top-of-viewport only.
- **Favicon / og:image extraction.** Considered and rejected: generic/identical for CMS sites (most clients are WordPress), so a poor differentiator. The full screenshot is the distinctive cue.
- **Manual "refresh thumbnail" button.** Restarting the project already recaptures, so the escape hatch exists. Could add later.
- **TTL-based staleness refresh** (recapture if older than N days). Noted as an easy future add; out of scope for v1.

## Decisions (locked during brainstorming)

1. **Capture mechanism:** off-screen `WKWebView` + `takeSnapshot(with:)`, downscaled to a PNG. No third-party headless browser, no shelling out. The app is **not sandboxed** (`codesign` shows no entitlements), so no network entitlement is needed to reach `*.ddev.site`.
2. **Trigger:** app launch for `running && missing-thumbnail` projects, plus every **stopped → running** transition. No timer, no per-selection capture.
3. **Storage:** one PNG per project on disk under `…/Application Support/DDEVUI/thumbnails/<id>.png`, owner-only (`0o600`) perms, pruned alongside vanished projects. Read-first on launch.
4. **Overview placement:** large thumbnail in the inspector header; placeholder (type symbol on a subtle fill) when none.
5. **List placement:** thumbnail replaces the type icon when present, grown to a ~36pt rounded rect (two-line row height); else the existing `projectType.symbol`.
6. **Freshness:** newest-we-have, no dimming.
7. **TLS:** rely on the system-trusted mkcert CA (normal DDEV setup); a navigation-challenge handler trusts the server cert **only for the exact host being captured, and only when it ends in `.ddev.site`** as a safety net; `https → http` fallback on failure. Never blanket-accept certs.

## Architecture

### 1. Capture service
New file `Sources/DDEVUIApp/Services/WebsiteThumbnailer.swift`:

```swift
public protocol WebsiteThumbnailing: Sendable {
    /// Renders `url` in an off-screen web view and returns a downscaled PNG, or nil on failure.
    func capture(url: URL) async -> Data?
}

@MainActor
public final class WebKitWebsiteThumbnailer: WebsiteThumbnailing { /* WKWebView */ }

public final class StubWebsiteThumbnailer: WebsiteThumbnailing { /* tests/previews */ }
```

- `WebKitWebsiteThumbnailer` is `@MainActor` (WebKit is main-thread-bound). It builds a `WKWebView` sized to a desktop viewport (~1200×900) hosted off-screen, with a `WKNavigationDelegate` that:
  - on `didReceive challenge`: trusts the server trust **only** for the target host when it ends in `.ddev.site`; otherwise performs default handling;
  - reports `didFinish` / `didFail`.
- Flow: load `url` with a hard timeout (~12s) → on finish, wait a short settle (~750ms) → `takeSnapshot` → `NSImage` → crop to the top region → downscale to a master (~640×400) → PNG `Data`. Timeout/failure → `nil`.
- **Sendability:** returns `Data` (Sendable). `NSImage` never crosses the actor boundary — it stays inside the `@MainActor` capturer.
- The WebKit impl is **not unit-testable** (needs a real web view + reachable site); the protocol exists so the *trigger logic* in the view model is testable with `StubWebsiteThumbnailer`.

### 2. Thumbnail store
New file `Sources/DDEVUIApp/Services/ThumbnailStore.swift`, mirroring `ProjectCacheStoring` / `FileProjectCacheStore`:

```swift
public protocol ThumbnailStoring: Sendable {
    func loadAll() async -> [String: Data]          // projectID -> PNG, read once on launch
    func save(_ data: Data, projectID: String) async throws
    func prune(keeping liveIDs: Set<String>) async  // delete files for vanished projects
}

public struct FileThumbnailStore: ThumbnailStoring { /* dir of <id>.png */ }
public final class InMemoryThumbnailStore: ThumbnailStoring { /* test double */ }
```

- `FileThumbnailStore` is a non-actor-isolated value type with `async` members, so PNG encode + disk I/O run **off** the `@MainActor` caller (same rationale as the project cache, audit M3).
- Directory `…/Application Support/DDEVUI/thumbnails/`. One `<sanitized-id>.png` per project; `0o600` perms (audit S1 — the dir holds machine-only data). Project ids are ddev project names; sanitize defensively (reject/replace path separators) before using as a filename.
- `loadAll()` reads the directory once on launch into a `[id: Data]` map.

### 3. View model integration (`ProjectDashboardViewModel`)
- **New injected deps** (init params with real defaults, stubbed in previews/tests):
  `thumbnailer: WebsiteThumbnailing = WebKitWebsiteThumbnailer()`,
  `thumbnailStore: ThumbnailStoring = FileThumbnailStore()`.
- **New observable state:** `public private(set) var thumbnails: [DDEVProject.ID: Data] = [:]` — PNG `Data` keyed by id. **`Data`, not `NSImage`**, to keep the view model AppKit-free and `Sendable`-clean; the view layer decodes to an `Image` (memoized — see §4).
- **Load on launch:** in the existing `loadCachedProjectsThenRefresh()` path, call `thumbnailStore.loadAll()` and populate `thumbnails` so cached thumbnails paint with the cached project list. Then enqueue captures for running projects missing one.
- **Capture orchestration:** a single **serialized, low-priority** capture queue (one web view at a time — never N concurrently). Each job: pick `primaryURL` (retry once with `httpURL` if it differs and the first attempt returns `nil`) → `thumbnailer.capture` → on success `thumbnailStore.save` + update `thumbnails[id]`. Best-effort; cancellable on background. Off the hot refresh path — it must not block `refreshProjectsFromDDEV`.
- **Trigger points:**
  - **Launch:** enqueue `projects.filter { $0.status == .running && thumbnails[$0.id] == nil }`.
  - **stopped → running:** computed in `applyProjects(_:)`, which still has the previous `self.projects` before reassignment — diff statuses and enqueue any project that just became `.running` (refresh even if a thumbnail exists, so a restart updates it).
- **Pruning:** extend `applyProjects(_:)` to drop vanished ids from `thumbnails` and call `thumbnailStore.prune(keeping: liveIDs)`, mirroring the existing command-state / group-membership pruning.

### 4. UI
- **New `ProjectThumbnailView`** (`Sources/DDEVUIApp/Views/ProjectThumbnailView.swift`): given optional PNG `Data`, a `fallbackSymbol: String`, and a size, renders the thumbnail as a rounded rect (`scaledToFill`, clipped), else the SF Symbol (tinted, matching today's look). Decodes `Data → Image` via a small memoized view-layer cache so list scrolling doesn't re-decode every frame. Used by both placements for consistency.
- **List row (`ProjectRow`):** replace the leading `Image(systemName: project.projectType.symbol).font(.title3).foregroundStyle(.tint).frame(width: 28…)` ([ProjectListView.swift:214](../../../Sources/DDEVUIApp/Views/ProjectListView.swift)) with `ProjectThumbnailView(thumbnail: viewModel.thumbnails[project.id], fallbackSymbol: project.projectType.symbol)` sized ~36×36 rounded rect.
- **Inspector header (`ProjectInspectorView.header(_:)`, line 231):** add a large thumbnail (~16:10, a few hundred px wide, capped) in/above the name + URL block; placeholder when none.
- **Accessibility:** thumbnail carries a label like "Homepage preview for \(name)".

## Edge cases

- **Never-started project:** no thumbnail ever; both placements show the type icon. Expected.
- **Capture failure** (timeout, TLS, 5xx, basic-auth/login wall): no file written; icon shown; retried next launch/start. A login/holding page still captures and is an acceptable fingerprint.
- **https fails, http works:** one retry with `httpURL`.
- **Project renamed in ddev:** new id → no thumbnail; old file pruned as vanished. Acceptable for v1.
- **Project unlinked/deleted:** file pruned, dict entry dropped.
- **Rapid restarts:** capture queue serializes; a capture keyed by id overwrites — latest wins.
- **Backgrounded mid-capture:** queue is best-effort and cancellable; no harm.
- **Disk write fails:** `try?`-swallowed (like the project cache); the in-memory thumbnail still shows for the session.
- **Very tall/wide homepage:** only the top viewport is snapshotted, so aspect is controlled.

## Risks & mitigations

- **`.ddev.site` TLS trust is the #1 risk.** On a normal DDEV machine mkcert's CA is system-trusted, so WKWebView validates. Mitigation: a navigation-challenge handler that trusts the server trust **only** for the exact captured host when it ends in `.ddev.site`, plus `https → http` fallback. Never blanket-accept. **This assumption should be verified against the real machine before/early in the build.**
- **Off-screen WKWebView snapshot timing/reliability.** Mitigation: host the web view off-screen with a real frame, wait for `didFinish` + a settle delay, enforce a hard timeout so a hung load can't wedge the queue; any failure falls back to the icon (graceful, never a crash).
- **Capture resource cost.** Mitigation: serialized one-at-a-time, low priority, only `running && missing` on launch, off the hot path. PNGs are ~10–50KB each on disk.
- **AppKit coupling in the view model.** Mitigation: the VM holds PNG `Data` (Sendable), not `NSImage`; decoding happens in the view layer.

## Testing

- **`FileThumbnailStore`** (`ThumbnailStoreTests.swift`): `save` → `loadAll` round-trip; `prune` deletes only non-live ids; `0o600` perms; id sanitization; missing dir → empty map.
- **View model** (stub thumbnailer + in-memory store, in `ProjectDashboardViewModelTests.swift`):
  - launch populates `thumbnails` from the store (read-first);
  - `running && missing` → capture enqueued, saved, dict updated;
  - `running && already-has-thumbnail` on launch → **not** recaptured;
  - stopped project → never captured;
  - stopped → running transition → capture enqueued (even if one exists);
  - vanished project → pruned from store + dict;
  - `https` capture returns nil then `http` succeeds → retried with `httpURL`.
- **WebKit capturer:** not unit-tested. Manual verification: build the app, open a running project → confirm overview + list thumbnails; restart → thumbnail refreshes; stop → cached thumbnail persists; a never-started project shows the type icon.

## File structure

- **Create:** `Sources/DDEVUIApp/Services/WebsiteThumbnailer.swift` (protocol + WebKit impl + stub), `Sources/DDEVUIApp/Services/ThumbnailStore.swift` (protocol + file + in-memory), `Sources/DDEVUIApp/Views/ProjectThumbnailView.swift`.
- **Modify:** `ProjectDashboardViewModel.swift` (two new injected deps, `thumbnails` state, load-on-launch, capture queue + triggers in `applyProjects`/launch, prune), `ProjectListView.swift` (`ProjectRow` leading-view swap), `ProjectInspectorView.swift` (header thumbnail), `ContentView.swift` (pass stub deps in the preview, mirroring `PreviewCommandRunner`).
- **Tests:** new `ThumbnailStoreTests.swift`; additions to `ProjectDashboardViewModelTests.swift`.
