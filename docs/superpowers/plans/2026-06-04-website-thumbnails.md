# Website Thumbnails Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a cached screenshot of each DDEV project's homepage as a visual identity cue — large in the inspector Overview, and small in place of the type icon in the project list.

**Architecture:** An injected `WebsiteThumbnailing` captures `primaryURL` in an off-screen `WKWebView` and returns a downscaled PNG `Data`. An injected `ThumbnailStoring` persists one PNG per project on disk (mirrors `ProjectCacheStoring`). `ProjectDashboardViewModel` loads cached thumbnails on launch into `thumbnails: [ID: Data]`, and (off the hot path) captures any running project that is missing a thumbnail or just transitioned to running. Two small views render `Data`-or-fallback-symbol.

**Tech Stack:** Swift 6.2 (tools) / SwiftPM, macOS 26, SwiftUI (`@Observable`), WebKit (`WKWebView`/`WKSnapshotConfiguration`), AppKit (`NSImage`), XCTest. Build: `swift build`. Test: `swift test --filter <ClassName>`.

---

## Conventions for every task
- Branch is `feat/website-thumbnails` (already checked out). One commit per task. **No "Co-Authored-By: Claude" trailer** (project rule, per memory).
- Tests: `@MainActor final class … : XCTestCase`, `@testable import DDEVUIApp`.
- In-memory/stub doubles live in **Sources** next to their protocol and are `public` (mirrors `InMemoryProjectCacheStore`), so previews and tests share them.
- The view model holds **PNG `Data`**, never `NSImage` (keeps the VM `Sendable`-clean and AppKit-free). Decoding to `Image` happens in the view layer.
- After each task: the named test(s) pass AND `swift build` is clean (only the pre-existing `Assets.xcassets` resource warning is acceptable).
- TDD for logic tasks (1, 3, 4). The WebKit capturer (Task 2) and view tasks (5–8) are verified by `swift build` + the manual checklist in Task 8 (a real `WKWebView` and a running site can't be unit-tested).

## File structure
- **Create:**
  - `Sources/DDEVUIApp/Services/ThumbnailStore.swift` — `ThumbnailStoring` protocol + `FileThumbnailStore` + `InMemoryThumbnailStore`.
  - `Sources/DDEVUIApp/Services/WebsiteThumbnailer.swift` — `WebsiteThumbnailing` protocol + `WebKitWebsiteThumbnailer` + `StubWebsiteThumbnailer`.
  - `Sources/DDEVUIApp/Views/ProjectThumbnailView.swift` — shared thumbnail-or-symbol view.
  - `Tests/DDEVUIAppTests/ThumbnailStoreTests.swift`.
- **Modify:**
  - `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` — inject the two deps, add `thumbnails` state, load on launch, capture selection + execution, prune.
  - `Sources/DDEVUIApp/Views/ProjectListView.swift` — `ProjectRow` leading view swap.
  - `Sources/DDEVUIApp/Views/ProjectInspectorView.swift` — header thumbnail.
  - `Sources/DDEVUIApp/Views/ContentView.swift` — capture trigger in `.task`; pass stubs in the `#Preview`.
  - `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift` — capture-logic tests.

---

### Task 1: `ThumbnailStoring` + `FileThumbnailStore` + `InMemoryThumbnailStore`

**Files:**
- Create: `Sources/DDEVUIApp/Services/ThumbnailStore.swift`
- Test: `Tests/DDEVUIAppTests/ThumbnailStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/DDEVUIAppTests/ThumbnailStoreTests.swift`:
```swift
import XCTest
@testable import DDEVUIApp

final class ThumbnailStoreTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ddevui-thumb-tests-\(UUID().uuidString)", isDirectory: true)
    }

    func testSaveThenLoadAllRoundTrips() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileThumbnailStore(directory: dir)

        try await store.save(Data([0x1, 0x2, 0x3]), projectID: "aqua-pura")
        try await store.save(Data([0x4, 0x5]), projectID: "agilebugs")

        let all = await store.loadAll()
        XCTAssertEqual(all["aqua-pura"], Data([0x1, 0x2, 0x3]))
        XCTAssertEqual(all["agilebugs"], Data([0x4, 0x5]))
    }

    func testLoadAllOnMissingDirectoryReturnsEmpty() async {
        let all = await FileThumbnailStore(directory: tempDir()).loadAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testPruneDeletesOnlyNonLiveIDs() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileThumbnailStore(directory: dir)
        try await store.save(Data([0x1]), projectID: "keep")
        try await store.save(Data([0x2]), projectID: "drop")

        await store.prune(keeping: ["keep"])

        let all = await store.loadAll()
        XCTAssertEqual(Array(all.keys), ["keep"])
    }

    func testSavedFileIsOwnerOnly() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileThumbnailStore(directory: dir)
        try await store.save(Data([0x1]), projectID: "aqua-pura")

        let perms = try FileManager.default.attributesOfItem(
            atPath: dir.appendingPathComponent("aqua-pura.png").path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o600)
    }

    func testIDWithPathSeparatorIsSanitized() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileThumbnailStore(directory: dir)

        try await store.save(Data([0x9]), projectID: "a/b")   // must not escape the directory

        let all = await store.loadAll()
        XCTAssertEqual(all["a_b"], Data([0x9]))                // separator replaced with "_"
    }

    func testInMemoryStoreRoundTrips() async throws {
        let store = InMemoryThumbnailStore()
        try await store.save(Data([0x7]), projectID: "x")
        await store.prune(keeping: ["x"])
        let all = await store.loadAll()
        XCTAssertEqual(all["x"], Data([0x7]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ThumbnailStoreTests`
Expected: FAIL — `cannot find 'FileThumbnailStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/DDEVUIApp/Services/ThumbnailStore.swift`:
```swift
import Foundation

public protocol ThumbnailStoring: Sendable {
    /// All cached thumbnails, keyed by project id. Read once on launch. Missing dir → empty.
    func loadAll() async -> [String: Data]
    /// Persist (overwrite) one project's PNG.
    func save(_ data: Data, projectID: String) async throws
    /// Delete cached files for projects no longer present.
    func prune(keeping liveIDs: Set<String>) async
}

/// Disk-backed PNG cache, one `<id>.png` per project. Non-actor-isolated value type with `async`
/// members, so encode + disk I/O run off the `@MainActor` caller (mirrors `FileProjectCacheStore`).
public struct FileThumbnailStore: ThumbnailStoring {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
            .appendingPathComponent("DDEVUI", isDirectory: true)
            .appendingPathComponent("thumbnails", isDirectory: true)
    }

    /// Project ids are ddev project names; replace path separators so an id can't escape `directory`.
    private func fileURL(for projectID: String) -> URL {
        let safe = projectID.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return directory.appendingPathComponent("\(safe).png", isDirectory: false)
    }

    public func loadAll() async -> [String: Data] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [:] }

        var result: [String: Data] = [:]
        for url in entries where url.pathExtension == "png" {
            if let data = try? Data(contentsOf: url) {
                result[url.deletingPathExtension().lastPathComponent] = data
            }
        }
        return result
    }

    public func save(_ data: Data, projectID: String) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(for: projectID)
        try data.write(to: url, options: .atomic)
        // Owner-only: machine-only cache, not world-readable (mirrors the project cache, audit S1).
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func prune(keeping liveIDs: Set<String>) async {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for url in entries where url.pathExtension == "png" {
            let id = url.deletingPathExtension().lastPathComponent
            if !liveIDs.contains(id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

public final class InMemoryThumbnailStore: ThumbnailStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data]

    public init(thumbnails: [String: Data] = [:]) { self.storage = thumbnails }

    public func loadAll() async -> [String: Data] { lock.withLock { storage } }

    public func save(_ data: Data, projectID: String) async throws {
        lock.withLock { storage[projectID] = data }
    }

    public func prune(keeping liveIDs: Set<String>) async {
        lock.withLock { storage = storage.filter { liveIDs.contains($0.key) } }
    }
}
```

> Note: `testIDWithPathSeparatorIsSanitized` expects the *sanitized* id (`a_b`) as the key on `loadAll`, because the filename is the source of truth on disk. That is intended — sanitization is deterministic, so the view model (which also keys by raw project id) must never produce ids containing `/` or `:`; ddev project names don't, so this is purely defensive.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ThumbnailStoreTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Services/ThumbnailStore.swift Tests/DDEVUIAppTests/ThumbnailStoreTests.swift
git commit -m "feat: disk-backed project thumbnail store"
```

---

### Task 2: `WebsiteThumbnailing` + WebKit capturer + stub

**Files:**
- Create: `Sources/DDEVUIApp/Services/WebsiteThumbnailer.swift`

This task has no unit tests (a real `WKWebView` + reachable site can't be unit-tested). It is verified by `swift build` and exercised end-to-end in Task 8's manual checklist. The `StubWebsiteThumbnailer` it adds is what makes Tasks 3–4 testable.

- [ ] **Step 1: Write the implementation**

Create `Sources/DDEVUIApp/Services/WebsiteThumbnailer.swift`:
```swift
import Foundation
#if canImport(WebKit)
import WebKit
import AppKit
#endif

public protocol WebsiteThumbnailing: Sendable {
    /// Renders `url` off-screen and returns a downscaled PNG, or nil on failure/timeout.
    func capture(url: URL) async -> Data?
}

/// Test/preview double. Returns a queued response per absolute URL (absent → nil) and records calls.
public final class StubWebsiteThumbnailer: WebsiteThumbnailing, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Data]
    private var recorded: [URL] = []

    public init(responses: [String: Data] = [:]) { self.responses = responses }

    public var capturedURLs: [URL] { lock.withLock { recorded } }

    public func capture(url: URL) async -> Data? {
        lock.withLock {
            recorded.append(url)
            return responses[url.absoluteString]
        }
    }
}

#if canImport(WebKit)
/// Captures a homepage screenshot via an off-screen `WKWebView`.
///
/// VERIFY-AGAINST-DOCS while implementing (these WebKit signatures are the fiddly bits):
///   - `WKWebView.takeSnapshot(with:completionHandler:)` completion is `(NSImage?, Error?)`.
///   - `WKSnapshotConfiguration.rect` crops the captured region (top viewport here).
///   - `urlSession`/navigation `didReceive challenge` completion shape.
/// If the compiler disagrees with the code below, trust the compiler + current WebKit docs.
@MainActor
public final class WebKitWebsiteThumbnailer: NSObject, WebsiteThumbnailing {
    private let viewport: CGSize
    private let targetWidth: CGFloat
    private let settle: Duration
    private let timeout: Duration

    public init(
        viewport: CGSize = CGSize(width: 1200, height: 900),
        targetWidth: CGFloat = 640,
        settle: Duration = .milliseconds(750),
        timeout: Duration = .seconds(12)
    ) {
        self.viewport = viewport
        self.targetWidth = targetWidth
        self.settle = settle
        self.timeout = timeout
    }

    public func capture(url: URL) async -> Data? {
        let webView = WKWebView(frame: CGRect(origin: .zero, size: viewport))
        let coordinator = LoadCoordinator(host: url.host)
        webView.navigationDelegate = coordinator

        // Host off-screen so the page actually lays out and paints.
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: viewport),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.alphaValue = 0
        window.contentView?.addSubview(webView)
        window.orderOut(nil)

        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.removeFromSuperview()
        }

        webView.load(URLRequest(url: url))

        let loaded = await coordinator.waitForLoad(timeout: timeout)
        guard loaded else { return nil }

        try? await Task.sleep(for: settle)

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: viewport)   // top viewport only
        let image: NSImage? = await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: config) { image, _ in
                continuation.resume(returning: image)
            }
        }
        guard let image else { return nil }
        return Self.downscaledPNG(image, targetWidth: targetWidth)
    }

    /// Downscale to `targetWidth` (keeping aspect) and encode PNG.
    private static func downscaledPNG(_ image: NSImage, targetWidth: CGFloat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff),
              source.pixelsWide > 0 else { return nil }

        let scale = targetWidth / CGFloat(source.pixelsWide)
        let size = NSSize(width: targetWidth, height: CGFloat(source.pixelsHigh) * scale)

        let target = NSImage(size: size)
        target.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        target.unlockFocus()

        guard let outTiff = target.tiffRepresentation,
              let rep = NSBitmapImageRep(data: outTiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Bridges `WKNavigationDelegate` callbacks to a single awaitable `waitForLoad`.
@MainActor
private final class LoadCoordinator: NSObject, WKNavigationDelegate {
    private let host: String?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var settled = false

    init(host: String?) { self.host = host }

    func waitForLoad(timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { c in self.continuation = c }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func finish(_ success: Bool) {
        guard !settled else { return }
        settled = true
        continuation?.resume(returning: success)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }

    /// Trust the server cert ONLY for the exact host being captured, and ONLY when it is a
    /// `.ddev.site` host (mkcert-signed local CA). Everything else gets default handling.
    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let host,
              challenge.protectionSpace.host == host,
              host.hasSuffix(".ddev.site") else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
#else
public typealias WebKitWebsiteThumbnailer = StubWebsiteThumbnailer
#endif
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: clean (only the pre-existing `Assets.xcassets` warning). If a WebKit signature is wrong, fix it against the current WebKit docs (see the VERIFY-AGAINST-DOCS note) — the contract (`capture(url:) async -> Data?`) must not change.

- [ ] **Step 3: Commit**

```bash
git add Sources/DDEVUIApp/Services/WebsiteThumbnailer.swift
git commit -m "feat: WebKit website thumbnail capturer + stub"
```

---

### Task 3: View model — inject deps, load thumbnails on launch, capture-on-launch logic

**Files:**
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `ProjectDashboardViewModelTests.swift` (inside the existing `@MainActor final class … : XCTestCase`):
```swift
// MARK: - Thumbnails

func testProjectsToCaptureIncludesRunningMissingAndNewlyRunning() {
    let runningMissing = DDEVProject.sampleWordPress                       // aqua-pura, running, no thumb
    let runningHasThumb = DDEVProject.sampleWithBothURLs                   // dual-url, running, has thumb
    let stopped = DDEVProject.sampleLaravel.withStatus(.stopped)          // agilebugs, stopped

    let toCapture = ProjectDashboardViewModel.projectsToCapture(
        current: [runningMissing, runningHasThumb, stopped],
        previous: [runningHasThumb],                       // dual-url was already running
        existing: [runningHasThumb.id]                     // dual-url already has a thumbnail
    )

    XCTAssertEqual(toCapture.map(\.id), ["aqua-pura"])                       // missing → in
    XCTAssertFalse(toCapture.contains { $0.id == "dual-url" })              // has-thumb + not-new → out
    XCTAssertFalse(toCapture.contains { $0.id == "agilebugs" })            // stopped → never captured
}

func testProjectsToCaptureIncludesNewlyRunningEvenWithThumbnail() {
    let restarted = DDEVProject.sampleWordPress                            // now running
    let toCapture = ProjectDashboardViewModel.projectsToCapture(
        current: [restarted],
        previous: [restarted.withStatus(.stopped)],          // was stopped → newly running
        existing: [restarted.id]                             // already has a thumbnail
    )
    XCTAssertEqual(toCapture.map(\.id), [restarted.id])      // transition forces a refresh
}

func testCaptureThumbnailsStoresAndExposesPNG() async {
    let project = DDEVProject.sampleWordPress                 // primaryURL https://aqua-pura.ddev.site
    let png = Data([0xAA, 0xBB])
    let thumbnailer = StubWebsiteThumbnailer(responses: [project.primaryURL!.absoluteString: png])
    let store = InMemoryThumbnailStore()
    let viewModel = ProjectDashboardViewModel(
        ddevService: FakeDDEVService(projects: []),
        thumbnailer: thumbnailer,
        thumbnailStore: store
    )

    await viewModel.captureThumbnails(for: [project])

    XCTAssertEqual(viewModel.thumbnails[project.id], png)
    let stored = await store.loadAll()
    XCTAssertEqual(stored[project.id], png)
}

func testCaptureFallsBackToHTTPWhenHTTPSReturnsNil() async {
    let project = DDEVProject.sampleWithBothURLs              // helper below
    let png = Data([0xCC])
    let thumbnailer = StubWebsiteThumbnailer(
        responses: [project.httpURL!.absoluteString: png]    // only http succeeds
    )
    let viewModel = ProjectDashboardViewModel(
        ddevService: FakeDDEVService(projects: []),
        thumbnailer: thumbnailer,
        thumbnailStore: InMemoryThumbnailStore()
    )

    await viewModel.captureThumbnails(for: [project])

    XCTAssertEqual(viewModel.thumbnails[project.id], png)
    XCTAssertEqual(thumbnailer.capturedURLs.map(\.absoluteString),
                   [project.primaryURL!.absoluteString, project.httpURL!.absoluteString])
}

func testLaunchLoadsCachedThumbnailsFromStore() async {
    let store = InMemoryThumbnailStore(thumbnails: ["aqua-pura": Data([0x1])])
    let viewModel = ProjectDashboardViewModel(
        ddevService: FakeDDEVService(projects: [.sampleWordPress]),
        projectCache: InMemoryProjectCacheStore(),          // never touch the real on-disk cache
        thumbnailer: StubWebsiteThumbnailer(),
        thumbnailStore: store
    )

    await viewModel.loadCachedProjectsThenRefresh()

    XCTAssertEqual(viewModel.thumbnails["aqua-pura"], Data([0x1]))
}
```

Add this helper near the `DDEVProject` sample extension at the bottom of the test file:
```swift
extension DDEVProject {
    /// A running project exposing BOTH an https primary and a distinct http URL (for fallback tests).
    static let sampleWithBothURLs = DDEVProject(
        name: "dual-url",
        appRoot: "/tmp/dual-url",
        shortRoot: "~/dual-url",
        status: .running,
        statusDescription: "running",
        projectType: .wordpress,                            // type is irrelevant to these tests
        docroot: "",
        primaryURL: URL(string: "https://dual-url.ddev.site"),
        httpURL: URL(string: "http://dual-url.ddev.site"),
        httpsURL: URL(string: "https://dual-url.ddev.site"),
        mailpitURL: nil, mailpitHTTPSURL: nil, xhguiURL: nil, xhguiHTTPSURL: nil,
        xhguiStatus: nil, mutagenEnabled: false, mutagenStatus: nil, phpVersion: nil
    )
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: FAIL — `ProjectDashboardViewModel` has no `projectsToCapture` / `captureThumbnails` / `thumbnails`, and the init has no `thumbnailer:`/`thumbnailStore:` params.

- [ ] **Step 3: Implement in `ProjectDashboardViewModel.swift`**

3a. Add stored deps + state near the other `private let` service deps (around line 231–245):
```swift
    private let thumbnailer: WebsiteThumbnailing
    private let thumbnailStore: ThumbnailStoring

    /// Cached homepage screenshots, PNG `Data` keyed by project id. Painted on launch from disk,
    /// refreshed off the hot path for running projects that are missing one or just (re)started.
    /// `Data` (not `NSImage`) keeps this view model Sendable-clean; the view layer decodes.
    public private(set) var thumbnails: [DDEVProject.ID: Data] = [:]
```

3b. Add the two params to `init` (with real defaults) and assign them. Insert the params after `customCommandDiscovery:` and before `statusPollInterval:`:
```swift
        customCommandDiscovery: CustomCommandDiscovering = FileSystemCustomCommandDiscovery(),
        thumbnailer: WebsiteThumbnailing = WebKitWebsiteThumbnailer(),
        thumbnailStore: ThumbnailStoring = FileThumbnailStore(),
        statusPollInterval: Duration = .seconds(10)
```
And in the body:
```swift
        self.thumbnailer = thumbnailer
        self.thumbnailStore = thumbnailStore
```

3c. Add the pure selection function and the capture executor. Put them near `loadCachedProjects()` (around line 1640):
```swift
    /// Running projects that need a (re)capture: those missing a thumbnail, plus those that just
    /// transitioned stopped→running (so a restart refreshes the shot even if one already exists).
    /// Stopped projects are never captured — they have no reachable URL.
    static func projectsToCapture(
        current: [DDEVProject],
        previous: [DDEVProject],
        existing: Set<DDEVProject.ID>
    ) -> [DDEVProject] {
        let wasRunning = Set(previous.filter { $0.status == .running }.map(\.id))
        return current.filter { project in
            guard project.status == .running else { return false }
            let missing = !existing.contains(project.id)
            let newlyRunning = !wasRunning.contains(project.id)
            return missing || newlyRunning
        }
    }

    /// Captures each project's homepage serially (one web view at a time), preferring `primaryURL`
    /// and retrying once with `httpURL` if the first attempt fails. Persists + exposes each PNG.
    /// Awaitable so callers/tests can sequence it; production callers spawn it off the hot path.
    func captureThumbnails(for projects: [DDEVProject]) async {
        for project in projects {
            guard let primary = project.primaryURL else { continue }
            var data = await thumbnailer.capture(url: primary)
            if data == nil, let http = project.httpURL, http != primary {
                data = await thumbnailer.capture(url: http)
            }
            guard let data else { continue }
            thumbnails[project.id] = data
            try? await thumbnailStore.save(data, projectID: project.id)
        }
    }

    /// Fire-and-forget capture so the hot refresh path is never blocked on web views.
    private func enqueueCaptures(_ projects: [DDEVProject]) {
        guard !projects.isEmpty else { return }
        Task { [weak self] in await self?.captureThumbnails(for: projects) }
    }
```

3d. Load cached thumbnails on launch. In `loadCachedProjectsThenRefresh()` (line 449), load the store first so thumbnails paint with the cached list:
```swift
    public func loadCachedProjectsThenRefresh() async {
        thumbnails = await thumbnailStore.loadAll()
        let loadedCachedProjects = await loadCachedProjects()

        if loadedCachedProjects {
            await refreshProjectsFromDDEVInBackground()
        } else {
            await refresh()
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: PASS (the 5 new tests plus the existing suite).

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "feat: load + capture project thumbnails in the dashboard view model"
```

---

### Task 4: View model — capture on refresh transitions + prune vanished thumbnails

**Files:**
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to the same test class:
```swift
func testRefreshCapturesRunningProjectMissingAThumbnail() async {
    let png = Data([0xDD])
    let thumbnailer = StubWebsiteThumbnailer(
        responses: [DDEVProject.sampleWordPress.primaryURL!.absoluteString: png]
    )
    let viewModel = ProjectDashboardViewModel(
        ddevService: FakeDDEVService(projects: [.sampleWordPress]),  // running, no cache
        projectCache: InMemoryProjectCacheStore(),
        thumbnailer: thumbnailer,
        thumbnailStore: InMemoryThumbnailStore()
    )

    await viewModel.refresh()

    XCTAssertEqual(viewModel.thumbnails["aqua-pura"], png)
}

func testRefreshPrunesThumbnailForVanishedProject() async {
    let store = InMemoryThumbnailStore(thumbnails: [
        "aqua-pura": Data([0x1]),
        "agilebugs": Data([0x2]),
    ])
    // ddev now only reports aqua-pura; agilebugs has vanished.
    let viewModel = ProjectDashboardViewModel(
        ddevService: FakeDDEVService(projects: [.sampleWordPress]),
        projectCache: InMemoryProjectCacheStore(),
        thumbnailer: StubWebsiteThumbnailer(),
        thumbnailStore: store
    )

    await viewModel.loadCachedProjectsThenRefresh()

    XCTAssertNil(viewModel.thumbnails["agilebugs"])              // dropped from memory
    let stored = await store.loadAll()
    XCTAssertNil(stored["agilebugs"])                            // and from disk
    XCTAssertNotNil(viewModel.thumbnails["aqua-pura"])          // survivor kept
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: FAIL — `refresh()` does not yet capture or prune thumbnails (`agilebugs` thumbnail still present; `aqua-pura` not captured).

- [ ] **Step 3: Implement**

3a. Capture on transitions. In `refreshProjectsFromDDEV()` (line 1618), snapshot `previous` before `applyProjects`, and enqueue captures after the save:
```swift
    private func refreshProjectsFromDDEV() async throws {
        let loadedProjects = try await ddevService.listProjects()
        let enrichedProjects = await enrichProjectsWithDetails(loadedProjects)
        let previous = projects
        applyProjects(enrichedProjects)
        try? await projectCache.saveProjects(enrichedProjects)
        await thumbnailStore.prune(keeping: Set(enrichedProjects.map(\.id)))
        enqueueCaptures(Self.projectsToCapture(
            current: enrichedProjects,
            previous: previous,
            existing: Set(thumbnails.keys)
        ))
    }
```
> The `existing` set is read on the main actor here (the VM is `@MainActor`), so it reflects thumbnails already loaded from disk — a running project whose cached thumbnail loaded on launch is *not* recaptured unless it newly transitioned to running.

3b. Prune the in-memory dict in `applyProjects(_:)` alongside the existing `commandStates` prune (after `let liveIDs = Set(projects.map(\.id))`, ~line 1654):
```swift
        thumbnails = thumbnails.filter { liveIDs.contains($0.key) }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "feat: capture thumbnails on start transitions and prune vanished ones"
```

---

### Task 5: `ProjectThumbnailView` shared component

**Files:**
- Create: `Sources/DDEVUIApp/Views/ProjectThumbnailView.swift`

No unit test (view). Verified by `swift build` + Task 8 manual checklist.

- [ ] **Step 1: Implement**

Create `Sources/DDEVUIApp/Views/ProjectThumbnailView.swift`:
```swift
import SwiftUI

/// Renders a project's cached homepage thumbnail as a rounded rect, or falls back to the project
/// type's SF Symbol when there is no thumbnail. Used both in the list row (small) and the inspector
/// header (large), so the fallback looks identical everywhere.
struct ProjectThumbnailView: View {
    let thumbnail: Data?
    let fallbackSymbol: String
    var cornerRadius: CGFloat = 6

    var body: some View {
        ZStack {
            if let thumbnail, let image = NSImage(data: thumbnail) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary.opacity(0.4))
                Image(systemName: fallbackSymbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
```
> Decoding `Data → NSImage` happens inline per render. That is fine for tens of projects; if scroll profiling ever shows jank, memoize the decode in a small `@MainActor` cache (YAGNI for now).

- [ ] **Step 2: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/DDEVUIApp/Views/ProjectThumbnailView.swift
git commit -m "feat: ProjectThumbnailView (thumbnail-or-type-icon)"
```

---

### Task 6: Use the thumbnail in the project list row

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ProjectListView.swift` (`ProjectRow`, lines 213–217)

- [ ] **Step 1: Swap the leading icon for the thumbnail view**

Replace the leading `Image` in `ProjectRow.body` (lines 213–217):
```swift
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: project.projectType.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28, alignment: .center)
```
with:
```swift
        HStack(alignment: .center, spacing: 12) {
            ProjectThumbnailView(
                thumbnail: viewModel.thumbnails[project.id],
                fallbackSymbol: project.projectType.symbol
            )
            .frame(width: 36, height: 36)
            .accessibilityLabel("Homepage preview for \(project.name)")
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/DDEVUIApp/Views/ProjectListView.swift
git commit -m "feat: show project thumbnail in place of the type icon in the list"
```

---

### Task 7: Large thumbnail in the inspector header

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift` (`header(_:)`, line 231)

- [ ] **Step 1: Add the thumbnail to the header**

Read `header(_ project:)` (starts line 231). It is a `VStack(alignment: .leading, spacing: 10)` beginning with `Text(project.name)`. Insert the thumbnail as the first element of that `VStack`, above the name:
```swift
    private func header(_ project: DDEVProject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProjectThumbnailView(
                thumbnail: viewModel.thumbnails[project.id],
                fallbackSymbol: project.projectType.symbol,
                cornerRadius: 10
            )
            .frame(maxWidth: 360)
            .frame(height: 200)
            .accessibilityLabel("Homepage preview for \(project.name)")

            Text(project.name)
            // …existing header content continues unchanged…
```
> Keep every existing line of the header below `Text(project.name)` exactly as-is; only the `ProjectThumbnailView` block is added at the top. If the inspector reads `viewModel` under a different identifier, use that identifier.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/DDEVUIApp/Views/ProjectInspectorView.swift
git commit -m "feat: show large homepage thumbnail in the inspector header"
```

---

### Task 8: Wire the launch capture trigger + preview stubs + manual verification

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ContentView.swift` (the `.task` at line 109; the `#Preview` at line 255)

- [ ] **Step 1: Trigger launch captures after the initial load**

In `ContentView.body`, the first `.task` (lines 109–112) currently is:
```swift
        .task {
            await viewModel.requestNotificationAuthorization()
            await viewModel.loadCachedProjectsThenRefresh()
        }
```
No change is required here for capture-on-launch — `refreshProjectsFromDDEV` (Task 4) already enqueues captures for running-and-missing projects during `loadCachedProjectsThenRefresh()`. Leave this `.task` as-is. (This step is a deliberate no-op checkpoint: confirm by re-reading that the launch path reaches `refreshProjectsFromDDEV`, which it does via both branches of `loadCachedProjectsThenRefresh`.)

- [ ] **Step 2: Keep previews from spawning a real WKWebView**

In the `#Preview` (line 255), pass stub thumbnail deps so previews never open a web view. Update the `ProjectDashboardViewModel(...)` call inside `#Preview`:
```swift
#Preview {
    ContentView(
        viewModel: ProjectDashboardViewModel(
            ddevService: DDEVCommandService(commandRunner: PreviewCommandRunner()),
            thumbnailer: StubWebsiteThumbnailer(),
            thumbnailStore: InMemoryThumbnailStore()
        ),
        prerequisites: PrerequisiteMonitor(
            service: StaticPrerequisiteService(
                state: PrerequisiteState(docker: .ok, ddev: .ok(version: "v1.24.0"))
            )
        )
    )
}
```

- [ ] **Step 3: Build + full test suite**

Run: `swift build && swift test`
Expected: clean build (only the `Assets.xcassets` warning); all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/DDEVUIApp/Views/ContentView.swift
git commit -m "feat: stub thumbnailer in previews; confirm launch capture path"
```

- [ ] **Step 5: Manual verification (build the real app — `swift run` crashes on `UNUserNotificationCenter`, so build a bundle via xcodebuild and launch it; see the verify-ddevui-app memory)**

Confirm, with at least one **running** DDEV project:
- [ ] Opening a running project's inspector shows a homepage screenshot in the header within a few seconds.
- [ ] That project's list row shows the screenshot in place of the type icon (a small ~36pt rounded rect; expect an impressionistic blob, not legible text).
- [ ] A project with no thumbnail yet (never started, or capture failed) shows the **type icon** in both places — no broken/empty box.
- [ ] **Stop** the project → its thumbnail **persists** (served from disk), not blanked.
- [ ] **Restart** the project → the thumbnail refreshes (re-captured on the stopped→running transition).
- [ ] Quit and relaunch the app → thumbnails appear **immediately** with the cached project list (cached-first paint), no capture flash.
- [ ] Confirm files exist at `~/Library/Application Support/DDEVUI/thumbnails/<project>.png` with `-rw-------` permissions (`ls -l`).
- [ ] If thumbnails are blank for a known-good running site, check the `.ddev.site` TLS path: the mkcert CA must be system-trusted (`mkcert -install`). This is the spec's #1 risk.

- [ ] **Step 6: Finalize**

Update this plan's checkboxes, then proceed to merge per the team's process (`superpowers:finishing-a-development-branch`).

---

## Self-review notes (author)
- **Spec coverage:** capture mechanism (T2), disk cache + owner-only + prune (T1, T4), cached-first launch paint (T3), capture-on-launch-missing + on-transition (T3, T4), overview thumbnail (T7), list icon-swap grown to ~36pt (T6), `Data`-not-`NSImage` in the VM (T3), TLS scoped to host + https→http fallback (T2, T3), no dimming / newest-we-have (T5 renders whatever `Data` is present). All spec sections map to a task.
- **Type consistency:** `thumbnails: [DDEVProject.ID: Data]`, `ThumbnailStoring.{loadAll,save,prune}`, `WebsiteThumbnailing.capture(url:)`, `projectsToCapture(current:previous:existing:)`, `captureThumbnails(for:)` — used identically across tasks and tests.
- **Known approximations to tune during build:** viewport (1200×900), target width (640), settle (750ms), timeout (12s), list size (36pt), header height (200pt). These are knobs, not contracts.
