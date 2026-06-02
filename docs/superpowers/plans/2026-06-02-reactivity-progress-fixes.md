# Reactivity & Progress Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three project-lifecycle defects in the DDEV UI — new projects not auto-starting, no determinate start progress, and stale state after a manual start.

**Architecture:** Three independent changes on branch `fix/reactivity-progress`, one commit each (Bug 1 → Bug 3 → Bug 2). Bug 1 chains `config`→`start` in the view model. Bug 3 stops `DDEVProject.applying(details:)` discarding the live `status` that `ddev describe -j` already returns, and republishes the selected project's detail after a mutation. Bug 2 adds an optional streaming line-handler to the command runner (via default-implemented protocol requirements, so no existing stub changes), a pure monotonic `StartProgressParser`, and a donut in the project row that falls back to indeterminate when progress is unknown.

**Tech Stack:** Swift 6.3 / SwiftPM, SwiftUI, `@Observable` view model, XCTest. Tests run with `swift test --filter <ClassName>`.

---

## Conventions for every task

- Run a single test class with: `swift test --filter <ClassName>` (regex over test names).
- Tests are `@MainActor final class … : XCTestCase` with `async` methods, `@testable import DDEVUIApp`.
- Commit messages: Conventional Commits. **Do NOT add a Claude co-author trailer** (project rule).
- After each task: the named test passes AND `swift build` succeeds (no warnings introduced).

## File structure (what changes and why)

**Bug 1**
- Modify `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` — `configureProject(folder:…)` chains a start, with no-rollback failure handling.
- Modify `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift` — add `configureError`/`startFolderError` injection to `FakeDDEVService`; new tests.

**Bug 3**
- Modify `Sources/DDEVUIApp/Models/DDEVProjectDetails.swift` — model + decode top-level `status`/`status_desc`.
- Modify `Sources/DDEVUIApp/Models/DDEVProject.swift` — `applying(details:)` adopts the describe status.
- Modify `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` — `reDescribe` republishes `selectedProjectDetails` for the selected project.
- Modify `Tests/DDEVUIAppTests/DDEVProjectDetailsDecodingTests.swift`, `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift` — new tests.

**Bug 2**
- Modify `Sources/DDEVUIApp/Services/CommandRunning.swift` — optional `onOutputLine` handler + per-line drain.
- Create `Sources/DDEVUIApp/Models/StartProgressParser.swift` — pure stage→fraction parser.
- Modify `Sources/DDEVUIApp/Models/ProjectCommandState.swift` — add `startProgress: Double?`.
- Modify `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` — progress-aware `DDEVServicing` methods, line consumption on the main actor, progress wiring for start/restart.
- Modify `Sources/DDEVUIApp/Views/ProjectListView.swift` — determinate/indeterminate donut.
- Create `Tests/DDEVUIAppTests/StartProgressParserTests.swift`; modify `ProcessCommandRunnerTests.swift`, `ProjectDashboardViewModelTests.swift`.
- Create `Tests/DDEVUIAppTests/Fixtures/ddev-start-output.txt` — captured real output (Task 6).

---

# Bug 1 — Auto-start newly configured projects

### Task 1: Configure-then-start, no rollback on start failure

**Files:**
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift:363` (`configureProject`)
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

- [ ] **Step 1: Add failure injection to `FakeDDEVService`**

In `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`, add two stored properties + init params to `FakeDDEVService` (it already follows this "optional injected error" pattern with `listError`, `importError`, …). Add after the existing `diagnosticError` property and its init param/assignment:

```swift
    // (property list, near the other `let …Error: Error?`)
    private let configureError: Error?
    private let startFolderError: Error?
```

```swift
    // (init parameters, after `diagnosticError: Error? = nil`)
        configureError: Error? = nil,
        startFolderError: Error? = nil
```

```swift
    // (init body, after `self.diagnosticError = diagnosticError`)
        self.configureError = configureError
        self.startFolderError = startFolderError
```

Then make `configureProject` and `startProject` honor them. Replace the existing `FakeDDEVService.startProject(in:)` and `configureProject(in:…)` bodies:

```swift
    func startProject(in appRoot: String) async throws -> CommandResult {
        record("start-folder:\(appRoot)")
        if let startFolderError { throw startFolderError }
        return commandResult(arguments: ["start"], workingDirectory: appRoot)
    }

    func configureProject(in appRoot: String, name: String, type: DDEVProjectType, docroot: String) async throws -> CommandResult {
        record("config:\(appRoot):\(name):\(type.rawValue):\(docroot)")
        if let configureError { throw configureError }
        return commandResult(
            arguments: ["config", "--project-name=\(name)", "--project-type=\(type.rawValue)", "--docroot=\(docroot)"],
            workingDirectory: appRoot
        )
    }
```

- [ ] **Step 2: Write the failing tests**

Add to the appropriate section of `ProjectDashboardViewModelTests.swift`:

```swift
    func testConfigureProjectStartsItAfterConfiguring() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)

        await viewModel.configureProject(folder: "/tmp/newsite", name: "newsite", type: .wordpress, docroot: "")

        let commands = service.commands
        let configIdx = commands.firstIndex { $0.hasPrefix("config:/tmp/newsite") }
        let startIdx = commands.firstIndex { $0.hasPrefix("start-folder:/tmp/newsite") }
        XCTAssertNotNil(configIdx, "config must run")
        XCTAssertNotNil(startIdx, "start must run after configuring")
        XCTAssertLessThan(configIdx!, startIdx!, "config precedes start")
        XCTAssertNil(viewModel.globalErrorMessage)
    }

    func testConfigureFailureDoesNotStart() async {
        let service = FakeDDEVService(
            projects: [.sampleWordPress],
            configureError: CommandRunnerError.nonZeroExit(.success(stdout: "", stderr: "bad config"))
        )
        let viewModel = ProjectDashboardViewModel(ddevService: service)

        await viewModel.configureProject(folder: "/tmp/newsite", name: "newsite", type: .wordpress, docroot: "")

        XCTAssertFalse(service.commands.contains { $0.hasPrefix("start-folder") }, "no start when config fails")
        XCTAssertNotNil(viewModel.globalErrorMessage)
    }

    func testStartFailureAfterConfigStillRefreshesAndSurfacesError() async {
        let service = FakeDDEVService(
            projects: [.sampleWordPress],
            startFolderError: CommandRunnerError.nonZeroExit(
                CommandResult(executable: "ddev", arguments: ["start"], workingDirectory: "/tmp/newsite",
                              exitCode: 1, stdout: "", stderr: "port in use",
                              startedAt: .distantPast, finishedAt: .distantPast, wasCancelled: false))
        )
        let viewModel = ProjectDashboardViewModel(ddevService: service)

        await viewModel.configureProject(folder: "/tmp/newsite", name: "newsite", type: .wordpress, docroot: "")

        XCTAssertTrue(service.commands.contains { $0.hasPrefix("config:") })
        XCTAssertTrue(service.commands.contains { $0.hasPrefix("start-folder:") })
        XCTAssertTrue(service.commands.contains("list"), "list still refreshes so the configured project appears")
        XCTAssertNotNil(viewModel.globalErrorMessage, "start failure is surfaced, not swallowed")
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: the three new tests FAIL (current `configureProject` never starts; no `start-folder` recorded).

- [ ] **Step 4: Implement the chain**

Replace `ProjectDashboardViewModel.configureProject(folder:name:type:docroot:)` (currently at `:363`):

```swift
    public func configureProject(folder: String, name: String, type: DDEVProjectType, docroot: String) async {
        isRunningGlobalCommand = true
        globalErrorMessage = nil
        defer { isRunningGlobalCommand = false }

        // 1. Configure. A failure here means nothing was registered — surface it and stop.
        do {
            _ = try await ddevService.configureProject(in: folder, name: name, type: type, docroot: docroot)
        } catch CommandRunnerError.nonZeroExit(let result) {
            globalErrorMessage = "Command failed with exit code \(result.exitCode)."
            return
        } catch {
            globalErrorMessage = error.presentableMessage
            return
        }

        // 2. Auto-start the freshly-configured project. A start failure must NOT roll back the
        //    registration (the project is legitimately configured), so we record the error but
        //    still fall through to the refresh below.
        do {
            _ = try await ddevService.startProject(in: folder)
        } catch CommandRunnerError.nonZeroExit(let result) {
            globalErrorMessage = "Project configured, but start failed (exit code \(result.exitCode))."
        } catch {
            globalErrorMessage = "Project configured, but start failed: \(error.presentableMessage)"
        }

        // 3. Refresh regardless of start outcome so the new project always appears in the list.
        do { try await refreshProjectsFromDDEV() } catch { /* keep any start-failure message */ }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: PASS (all three new tests, plus existing tests unchanged).

- [ ] **Step 6: Commit**

```bash
git add Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "fix(projects): auto-start a newly configured project (no rollback on start failure)"
```

---

# Bug 3 — Immediate, correct state after a manual mutation

### Task 2: `DDEVProjectDetails` carries the describe status

**Files:**
- Modify: `Sources/DDEVUIApp/Models/DDEVProjectDetails.swift`
- Test: `Tests/DDEVUIAppTests/DDEVProjectDetailsDecodingTests.swift`

- [ ] **Step 1: Write the failing decode test**

Add to `DDEVProjectDetailsDecodingTests`:

```swift
    func testDecodesProjectStatus() throws {
        let data = #"{"raw":{"php_version":"8.4","status":"running","status_desc":"running"}}"#.data(using: .utf8)!
        let details = try DDEVProjectDetails.decodeDescribePayload(data)
        XCTAssertEqual(details.status, .running)
        XCTAssertEqual(details.statusDescription, "running")
    }

    func testMissingStatusDecodesToUnknown() throws {
        let data = #"{"raw":{"php_version":"8.4"}}"#.data(using: .utf8)!
        let details = try DDEVProjectDetails.decodeDescribePayload(data)
        XCTAssertEqual(details.status, .unknown)
        XCTAssertEqual(details.statusDescription, "")
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter DDEVProjectDetailsDecodingTests`
Expected: FAIL to compile — `details.status` / `statusDescription` don't exist yet.

- [ ] **Step 3: Add the stored properties + defaulted init params**

In `Sources/DDEVUIApp/Models/DDEVProjectDetails.swift`, add two stored properties to `DDEVProjectDetails` (after `xhguiStatus`):

```swift
    public let status: DDEVProjectStatus
    public let statusDescription: String
```

Add init parameters (with defaults so the four existing call sites keep compiling) — place at the end of the parameter list, after `services`:

```swift
        services: [DDEVServiceInfo] = [],
        status: DDEVProjectStatus = .unknown,
        statusDescription: String = ""
```

And in the init body:

```swift
        self.status = status
        self.statusDescription = statusDescription
```

- [ ] **Step 4: Decode `status` / `status_desc` from the raw payload**

In `RawDDEVProjectDetails`, add fields + coding keys:

```swift
    let status: String?
    let statusDesc: String?
```

```swift
    // inside CodingKeys
        case status
        case statusDesc = "status_desc"
```

And in `toDetails()`, pass them through:

```swift
        DDEVProjectDetails(
            phpVersion: phpVersion,
            xhguiStatus: xhguiStatus.map { DDEVXHGuiStatus(rawValue: $0) ?? .unknown },
            nodeJSVersion: nodeJSVersion,
            routerStatus: routerStatus,
            sshAgentStatus: sshAgentStatus,
            databaseInfo: dbinfo?.toDatabaseInfo(),
            services: decodeServices(),
            status: status.flatMap { DDEVProjectStatus(rawValue: $0) } ?? .unknown,
            statusDescription: statusDesc ?? ""
        )
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter DDEVProjectDetailsDecodingTests`
Expected: PASS (new tests + existing decode tests unchanged — the new init params are defaulted).

- [ ] **Step 6: Commit**

```bash
git add Sources/DDEVUIApp/Models/DDEVProjectDetails.swift Tests/DDEVUIAppTests/DDEVProjectDetailsDecodingTests.swift
git commit -m "feat(model): decode top-level status/status_desc from ddev describe"
```

### Task 3: `applying(details:)` adopts the live status; selected detail republished

**Files:**
- Modify: `Sources/DDEVUIApp/Models/DDEVProject.swift:278` (`applying(details:)`)
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift:874` (`reDescribe`)
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

- [ ] **Step 1: Write the failing test for `applying`**

Add to `ProjectDashboardViewModelTests.swift` (model-level behavior, fine to live here):

```swift
    func testApplyingDetailsAdoptsLiveStatus() {
        let stopped = DDEVProject.sampleWordPress.withStatus(.stopped)
        let running = DDEVProjectDetails(phpVersion: "8.3", status: .running, statusDescription: "running")
        XCTAssertEqual(stopped.applying(details: running).status, .running)
    }

    func testApplyingUnknownStatusKeepsExistingStatus() {
        let running = DDEVProject.sampleWordPress // .running
        let detailWithoutStatus = DDEVProjectDetails(phpVersion: "8.3") // status defaults to .unknown
        XCTAssertEqual(running.applying(details: detailWithoutStatus).status, .running,
                       "an unknown describe status must not clobber a known one")
    }
```

- [ ] **Step 2: Write the failing VM test for post-start state**

```swift
    func testStartReflectsRunningStatusAndRefreshesSelectedDetail() async {
        let runningDetails = DDEVProjectDetails(phpVersion: "8.3", status: .running, statusDescription: "running")
        let stopped = DDEVProject.sampleWordPress.withStatus(.stopped)
        let service = FakeDDEVService(projects: [stopped], describeDetails: ["aqua-pura": runningDetails])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.projects = [stopped]               // seed directly to avoid refresh-time enrichment
        viewModel.selectedProject = stopped

        await viewModel.start(stopped)

        XCTAssertEqual(viewModel.projects.first?.status, .running,
                       "the re-describe after start flips the cached status to running")
        XCTAssertEqual(viewModel.selectedProjectDetails?.status, .running,
                       "the inspector overview detail is refreshed for the selected project")
        XCTAssertFalse(service.commands.contains("list"),
                       "minimal fix: only the affected project is re-described, no global list")
    }
```

- [ ] **Step 3: Run to verify they fail**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: FAIL — `applying` currently preserves the old status, and `reDescribe` never sets `selectedProjectDetails`.

- [ ] **Step 4: Update `applying(details:)`**

In `Sources/DDEVUIApp/Models/DDEVProject.swift`, change the `status` / `statusDescription` arguments inside `applying(details:)` (they currently read `status: status, statusDescription: statusDescription`):

```swift
            // Trust describe for the live status (it returns top-level `status`/`status_desc`),
            // but never let a missing/unknown describe status clobber a known one.
            status: details.status == .unknown ? status : details.status,
            statusDescription: details.status == .unknown ? statusDescription : details.statusDescription,
```

- [ ] **Step 5: Republish `selectedProjectDetails` in `reDescribe`**

In `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`, update `reDescribe(_:)` to reuse the single describe it already performs:

```swift
    private func reDescribe(_ project: DDEVProject) async {
        guard let refreshed = try? await ddevService.describe(projectName: project.name) else { return }
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = projects[index].applying(details: refreshed)
        if selectedProjectFallback?.id == project.id {
            selectedProjectFallback = projects[index]
        }
        // Refresh the inspector's live overview (services/DB) for the selected project from the
        // SAME describe — no second subprocess. Guarded so a stale describe can't overwrite a
        // newer selection's detail.
        if selectedProjectID == project.id {
            selectedProjectDetails = refreshed
        }
        try? await projectCache.saveProjects(projects)
    }
```

- [ ] **Step 6: Run to verify they pass**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: PASS. Also run `swift test --filter ProjectConcurrencyTests` — it asserts `["stop:agilebugs", "describe:agilebugs"]`; still holds (we add no commands).

- [ ] **Step 7: Commit**

```bash
git add Sources/DDEVUIApp/Models/DDEVProject.swift Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "fix(projects): reflect live status + refresh inspector detail after a mutation"
```

---

# Bug 2 — Real stream-and-parse progress donut

### Task 4: Streaming line handler on `CommandRunning`

**Files:**
- Modify: `Sources/DDEVUIApp/Services/CommandRunning.swift`
- Test: `Tests/DDEVUIAppTests/ProcessCommandRunnerTests.swift`

- [ ] **Step 1: Write the failing streaming test**

Add to `ProcessCommandRunnerTests`:

```swift
    func testRunStreamsOutputLines() async throws {
        let runner = ProcessCommandRunner()
        let collector = LineCollector()
        let result = try await runner.run(
            CommandSpec(executable: "sh", arguments: ["-c", "printf 'a\\nb\\nc\\n'"]),
            onOutputLine: { collector.append($0) }
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(collector.snapshot(), ["a", "b", "c"])
    }

    func testRunWithoutHandlerStillReturnsBufferedOutput() async throws {
        let runner = ProcessCommandRunner()
        let result = try await runner.run(CommandSpec(executable: "echo", arguments: ["hello"]))
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }
```

Add this test double at the bottom of the file:

```swift
private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) { lock.withLock { lines.append(line) } }
    func snapshot() -> [String] { lock.withLock { lines } }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ProcessCommandRunnerTests`
Expected: FAIL to compile — `run(_:onOutputLine:)` doesn't exist.

- [ ] **Step 3: Add the protocol requirement + default**

In `Sources/DDEVUIApp/Services/CommandRunning.swift`, change the protocol and add a default so existing conformers (`PreviewCommandRunner`, `RecordingCommandRunner`, `StubCommandRunner`) need no changes:

```swift
public protocol CommandRunning: Sendable {
    func run(_ spec: CommandSpec) async throws -> CommandResult
    /// Streaming variant: invokes `onOutputLine` once per completed output line (stdout+stderr
    /// interleaved as produced) while the child runs. The buffered `CommandResult` is unchanged.
    func run(_ spec: CommandSpec, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult
}

public extension CommandRunning {
    // Default for conformers that don't stream: ignore the handler, run buffered.
    func run(_ spec: CommandSpec, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try await run(spec)
    }
}
```

- [ ] **Step 4: Implement streaming in `ProcessCommandRunner`**

`ProcessCommandRunner` must satisfy BOTH requirements explicitly (so its streaming impl wins over the extension default). Make the existing `run(_:)` delegate, and put the real work in the new method. Replace the current `public func run(_ spec:)` with:

```swift
    public func run(_ spec: CommandSpec) async throws -> CommandResult {
        try await run(spec, onOutputLine: nil)
    }

    public func run(_ spec: CommandSpec, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        let controller = ProcessController()
        let cap = maxCapturedBytes
        let result: CommandResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(returning: try Self.executeBlocking(
                            spec, controller: controller, maxCapturedBytes: cap, onOutputLine: onOutputLine))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            controller.terminate()
        }

        if result.wasCancelled {
            if Task.isCancelled { throw CancellationError() }
            throw CommandRunnerError.timedOut(result)
        }
        if result.succeeded { return result }
        throw CommandRunnerError.nonZeroExit(result)
    }
```

Thread the handler into `executeBlocking` and `drain`. Change the `executeBlocking` signature and the two `drain` calls:

```swift
    private static func executeBlocking(_ spec: CommandSpec, controller: ProcessController, maxCapturedBytes: Int,
                                        onOutputLine: (@Sendable (String) -> Void)?) throws -> CommandResult {
```

```swift
        // line splitters are per-stream so a partial line on one pipe isn't merged with the other
        let stdoutLineBuffer = LineSplitter(onLine: onOutputLine)
        let stderrLineBuffer = LineSplitter(onLine: onOutputLine)

        group.enter()
        readQueue.async {
            Self.drain(stdoutPipe.fileHandleForReading, into: stdoutBuffer, cap: maxCapturedBytes, lineSplitter: stdoutLineBuffer)
            group.leave()
        }

        group.enter()
        readQueue.async {
            Self.drain(stderrPipe.fileHandleForReading, into: stderrBuffer, cap: maxCapturedBytes, lineSplitter: stderrLineBuffer)
            group.leave()
        }
```

After `group.wait()` (so any trailing partial line is flushed), add:

```swift
        stdoutLineBuffer.flush()
        stderrLineBuffer.flush()
```

Update `drain` to feed the splitter:

```swift
    private static func drain(_ handle: FileHandle, into buffer: PipeBuffer, cap: Int, lineSplitter: LineSplitter) {
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break } // EOF
            buffer.appendCapped(chunk, cap: cap)
            lineSplitter.consume(chunk)
        }
    }
```

Add the `LineSplitter` helper (near `PipeBuffer`):

```swift
    /// Splits a byte stream into UTF-8 lines and invokes `onLine` per complete line. Lock-guarded
    /// because the two pipe drains run on a concurrent queue. A no-op when `onLine` is nil.
    private final class LineSplitter: @unchecked Sendable {
        private let lock = NSLock()
        private let onLine: (@Sendable (String) -> Void)?
        private var pending = Data()

        init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

        func consume(_ chunk: Data) {
            guard let onLine else { return }
            let completed: [String] = lock.withLock {
                pending.append(chunk)
                var lines: [String] = []
                while let nl = pending.firstIndex(of: 0x0A) {
                    let lineData = pending[pending.startIndex..<nl]
                    lines.append(String(decoding: lineData, as: UTF8.self)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
                    pending.removeSubrange(pending.startIndex...nl)
                }
                return lines
            }
            completed.forEach(onLine)
        }

        func flush() {
            guard let onLine else { return }
            let leftover: String? = lock.withLock {
                guard !pending.isEmpty else { return nil }
                let s = String(decoding: pending, as: UTF8.self)
                pending.removeAll()
                return s.isEmpty ? nil : s
            }
            if let leftover { onLine(leftover) }
        }
    }
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter ProcessCommandRunnerTests`
Expected: PASS (streaming yields `["a","b","c"]`; buffered behavior unchanged).

- [ ] **Step 6: Commit**

```bash
git add Sources/DDEVUIApp/Services/CommandRunning.swift Tests/DDEVUIAppTests/ProcessCommandRunnerTests.swift
git commit -m "feat(runner): optional per-line streaming handler (buffered result unchanged)"
```

### Task 5: `StartProgressParser` (pure, monotonic, indeterminate fallback)

**Files:**
- Create: `Sources/DDEVUIApp/Models/StartProgressParser.swift`
- Create: `Tests/DDEVUIAppTests/StartProgressParserTests.swift`

> The stage substrings below are an initial best-effort set; **Task 6 captures real output and tunes them.** The tests assert *behavioral* properties (monotonic, `< 1.0` until completion, `nil` when nothing matches) that hold regardless of the exact strings.

- [ ] **Step 1: Write the failing tests**

Create `Tests/DDEVUIAppTests/StartProgressParserTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

final class StartProgressParserTests: XCTestCase {
    func testRecognizedLinesAdvanceMonotonicallyBelowOne() {
        var parser = StartProgressParser()
        let lines = ["Starting myproject...", "Container ddev-myproject-db  Started",
                     "Container ddev-myproject-web  Started", "Waiting for the web server to be ready"]
        var emitted: [Double] = []
        for line in lines { if let f = parser.consume(line) { emitted.append(f) } }

        XCTAssertFalse(emitted.isEmpty, "known DDEV lines should produce progress")
        XCTAssertEqual(emitted, emitted.sorted(), "progress is non-decreasing")
        XCTAssertTrue(emitted.allSatisfy { $0 < 1.0 }, "never reports 100% before completion")
    }

    func testUnrecognizedOutputStaysIndeterminate() {
        var parser = StartProgressParser()
        XCTAssertNil(parser.consume("some unrelated diagnostic chatter"))
        XCTAssertNil(parser.fraction, "no recognized stage -> indeterminate (nil)")
    }

    func testMarkCompletedReachesOne() {
        var parser = StartProgressParser()
        _ = parser.consume("Starting myproject...")
        parser.markCompleted()
        XCTAssertEqual(parser.fraction, 1.0)
    }

    func testProgressNeverDecreasesEvenIfStagesArriveOutOfOrder() {
        var parser = StartProgressParser()
        _ = parser.consume("Waiting for the web server to be ready") // late-stage first
        let afterEarly = parser.consume("Starting myproject...")     // early-stage second
        XCTAssertNotNil(parser.fraction)
        if let afterEarly { XCTAssertGreaterThanOrEqual(afterEarly, 0.0) }
        // fraction must not drop below what the late stage already set
        XCTAssertGreaterThanOrEqual(parser.fraction ?? 0, 0.7)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter StartProgressParserTests`
Expected: FAIL to compile — `StartProgressParser` doesn't exist.

- [ ] **Step 3: Implement the parser**

Create `Sources/DDEVUIApp/Models/StartProgressParser.swift`:

```swift
import Foundation

/// Maps `ddev start` / `ddev restart` output lines to a coarse, **monotonic** progress fraction
/// for the project-row donut. This is a stage estimate, not a true percentage — DDEV emits no
/// percentage. When no stage is recognized (e.g. a future DDEV changes its wording), `fraction`
/// stays `nil` and the UI falls back to an indeterminate spinner rather than showing a wrong or
/// stuck number. `1.0` is reserved for `markCompleted()` (process exit), so a recognized run can
/// never visually "finish" before the command actually returns.
public struct StartProgressParser {
    /// Ordered stage needles → fraction. Matched case-insensitively; a line may match several,
    /// in which case the highest wins. Tuned against captured DDEV v1.25.2 output (see
    /// Tests/DDEVUIAppTests/Fixtures/ddev-start-output.txt).
    private static let stages: [(needle: String, fraction: Double)] = [
        ("starting", 0.10),
        ("building", 0.20),
        ("recreating", 0.30),
        ("creating", 0.30),
        ("started", 0.55),
        ("waiting for", 0.70),
        ("pushing", 0.82),
        ("syncing", 0.82),
        ("successfully started", 0.95),
        ("ready", 0.95)
    ]

    public private(set) var fraction: Double?

    public init() {}

    /// Feeds one output line. Returns the new fraction if this line advanced progress, else `nil`.
    public mutating func consume(_ line: String) -> Double? {
        let lower = line.lowercased()
        var matched: Double?
        for stage in Self.stages where lower.contains(stage.needle) {
            matched = max(matched ?? 0, stage.fraction)
        }
        guard let matched else { return nil }
        let next = max(fraction ?? 0, matched)
        guard next != fraction else { return nil } // no visible change
        fraction = next
        return next
    }

    /// Process exited successfully — pin to 100%.
    public mutating func markCompleted() { fraction = 1.0 }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter StartProgressParserTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Models/StartProgressParser.swift Tests/DDEVUIAppTests/StartProgressParserTests.swift
git commit -m "feat(progress): pure monotonic StartProgressParser with indeterminate fallback"
```

### Task 6: Capture real `ddev start` output and tune the stage table

**Files:**
- Create: `Tests/DDEVUIAppTests/Fixtures/ddev-start-output.txt`
- Modify (tune if needed): `Sources/DDEVUIApp/Models/StartProgressParser.swift`
- Modify: `Tests/DDEVUIAppTests/StartProgressParserTests.swift`

- [ ] **Step 1: Capture real output from a stopped project**

`agilebugs` is a real, currently-stopped project. Capture both streams (DDEV writes status to stderr), piped (non-TTY) like the app runs it:

```bash
ddev start agilebugs > /tmp/ddev-start.out 2> /tmp/ddev-start.err
echo "--- stdout ---"; cat /tmp/ddev-start.out
echo "--- stderr ---"; cat /tmp/ddev-start.err
```

- [ ] **Step 2: Return the project to its prior (stopped) state**

```bash
ddev stop agilebugs
ddev list | grep agilebugs   # confirm it is stopped again
```

- [ ] **Step 3: Save the captured progress lines as a fixture**

Write the meaningful status lines (the union of stdout+stderr, in order) to `Tests/DDEVUIAppTests/Fixtures/ddev-start-output.txt`. (Create the `Fixtures` directory if absent.) These are the lines a user would see scroll by during a start.

- [ ] **Step 4: Tune the stage table to the capture**

Compare the captured lines to `StartProgressParser.stages`. Adjust needles/fractions so that the captured sequence yields a monotonic, sensible ramp ending just below 1.0, and that the final "successfully started"-type line maps highest. Keep needles lowercase substrings.

- [ ] **Step 5: Add a fixture-driven regression test**

Append to `StartProgressParserTests`:

```swift
    func testCapturedRealOutputProducesMonotonicRamp() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ddev-start-output", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        var parser = StartProgressParser()
        var emitted: [Double] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let f = parser.consume(String(line)) { emitted.append(f) }
        }
        XCTAssertGreaterThanOrEqual(emitted.count, 2, "real output advances through at least two stages")
        XCTAssertEqual(emitted, emitted.sorted())
        XCTAssertTrue(emitted.allSatisfy { $0 < 1.0 })
    }
```

> `Bundle.module` requires the fixture to be a package resource. If `swift test` cannot find it, add `resources: [.copy("Fixtures/ddev-start-output.txt")]` to the test target in `Package.swift`:
> ```swift
> .testTarget(
>     name: "DDEVUIAppTests",
>     dependencies: ["DDEVUIApp"],
>     path: "Tests/DDEVUIAppTests",
>     resources: [.copy("Fixtures/ddev-start-output.txt")]
> )
> ```

- [ ] **Step 6: Run to verify it passes**

Run: `swift test --filter StartProgressParserTests`
Expected: PASS (including the fixture-driven test).

- [ ] **Step 7: Commit**

```bash
git add Sources/DDEVUIApp/Models/StartProgressParser.swift Tests/DDEVUIAppTests/StartProgressParserTests.swift Tests/DDEVUIAppTests/Fixtures/ddev-start-output.txt Package.swift
git commit -m "test(progress): tune StartProgressParser against captured ddev v1.25.2 start output"
```

### Task 7: Wire streaming progress through the service and view model

**Files:**
- Modify: `Sources/DDEVUIApp/Models/ProjectCommandState.swift`
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` (protocol + `start`/`restart` + consumption)
- Modify: `Sources/DDEVUIApp/Services/DDEVCommandService.swift` (progress-aware impls)
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

- [ ] **Step 1: Add `startProgress` to per-project state**

In `Sources/DDEVUIApp/Models/ProjectCommandState.swift`, add a property to `ProjectCommandState` (after `outputExpansionRequest`):

```swift
    /// Determinate progress (0…1) for an in-flight start/restart, or `nil` for indeterminate.
    public var startProgress: Double?
```

- [ ] **Step 2: Add progress-aware requirements to `DDEVServicing` with defaults**

In `ProjectDashboardViewModel.swift`, add to the `DDEVServicing` protocol:

```swift
    func start(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult
    func restart(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult
```

And a default-implementation extension right after the protocol (so the 3 test stubs and `DDEVCommandService` need no forced changes; only `DDEVCommandService` will override to actually stream):

```swift
public extension DDEVServicing {
    func start(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try await start(projectName: projectName)
    }
    func restart(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try await restart(projectName: projectName)
    }
}
```

- [ ] **Step 3: Implement streaming in `DDEVCommandService`**

In `Sources/DDEVUIApp/Services/DDEVCommandService.swift`, add progress-aware overloads + a streaming `runDDEV`:

```swift
    @discardableResult
    public func start(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try await runDDEV(["start", projectName], onOutputLine: onOutputLine)
    }

    @discardableResult
    public func restart(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try await runDDEV(["restart", projectName], onOutputLine: onOutputLine)
    }
```

```swift
    private func runDDEV(_ arguments: [String], workingDirectory: String? = nil,
                         onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try await commandRunner.run(
            CommandSpec(executable: ddevExecutable, arguments: arguments, workingDirectory: workingDirectory),
            onOutputLine: onOutputLine
        )
    }
```

- [ ] **Step 4: Write the failing VM wiring test**

Add a focused stub override to `FakeDDEVService` so the test can both assert that streaming was requested and drive the parser deterministically. Add a stored property + init param (same pattern as Task 1) `startOutputLines: [String] = []`, a recorder `private(set) var startStreamed = false` guarded by the lock, and override the progress-aware start:

```swift
    // property
    private let startOutputLines: [String]
    private var startStreamedFlag = false
    var startStreamed: Bool { lock.withLock { startStreamedFlag } }

    // init param (after startFolderError)
        startOutputLines: [String] = [],

    // init body
        self.startOutputLines = startOutputLines

    // override the streaming requirement
    func start(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        record("start:\(projectName)")
        if onOutputLine != nil { lock.withLock { startStreamedFlag = true } }
        for line in startOutputLines { onOutputLine?(line) }
        return commandResult(arguments: ["start", projectName])
    }
```

Then the test:

```swift
    func testStartRequestsStreamingAndClearsProgressOnCompletion() async {
        let service = FakeDDEVService(
            projects: [DDEVProject.sampleWordPress.withStatus(.stopped)],
            startOutputLines: ["Starting aqua-pura...", "Container ddev-aqua-pura-web  Started"]
        )
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        let stopped = DDEVProject.sampleWordPress.withStatus(.stopped)
        viewModel.projects = [stopped]
        viewModel.selectedProject = stopped

        await viewModel.start(stopped)

        XCTAssertTrue(service.startStreamed, "start passes a non-nil progress handler")
        XCTAssertNil(viewModel.state(for: "aqua-pura").startProgress,
                     "progress is cleared once the command completes")
    }
```

- [ ] **Step 5: Run to verify it fails**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: FAIL — `start` does not yet stream or set/clear `startProgress`.

- [ ] **Step 6: Wire consumption into `start`/`restart`**

In `ProjectDashboardViewModel.swift`, replace `start(_:)` and `restart(_:)` so they run through a progress-aware mutation. Add a private helper that funnels lines through an `AsyncStream` consumed on the main actor (the VM is `@MainActor`, so all `commandStates` writes stay on the main actor and stay ordered):

```swift
    public func start(_ project: DDEVProject) async {
        await runProgressMutation(project) { onLine in
            try await self.ddevService.start(projectName: project.name, onOutputLine: onLine)
        }
    }

    public func restart(_ project: DDEVProject) async {
        await runProgressMutation(project) { onLine in
            try await self.ddevService.restart(projectName: project.name, onOutputLine: onLine)
        }
    }
```

Add the helper (next to `runProjectMutation`):

```swift
    /// Like `runProjectMutation`, but streams the command's output lines through a
    /// `StartProgressParser` to publish a determinate `startProgress` for the row donut. Lines are
    /// marshalled onto the main actor via an `AsyncStream`, so `commandStates` is only mutated here.
    /// Progress clears back to `nil` when the command finishes (success or failure).
    private func runProgressMutation(
        _ project: DDEVProject,
        refresh: RefreshScope = .project,
        _ operation: @escaping (_ onLine: @escaping @Sendable (String) -> Void) async throws -> CommandResult
    ) async {
        let id = project.id
        guard !isBusy(project) else { return }

        setActivity(.queued, for: id)
        do { try await scheduler.acquire() } catch { setActivity(.idle, for: id); return }
        setActivity(.running, for: id)

        let (stream, continuation) = AsyncStream<String>.makeStream()
        let consumer = Task { @MainActor in
            var parser = StartProgressParser()
            for await line in stream {
                if let fraction = parser.consume(line) {
                    commandStates[id, default: .init()].startProgress = fraction
                }
            }
        }

        let outcome = await execute { try await operation { line in continuation.yield(line) } }
        continuation.finish()
        await consumer.value

        commandStates[id, default: .init()].startProgress = nil  // clear the donut
        await scheduler.release()
        setActivity(.idle, for: id)

        await finish(outcome, for: project, refresh: refresh)
    }
```

- [ ] **Step 7: Run to verify it passes**

Run: `swift test --filter ProjectDashboardViewModelTests`
Expected: PASS. Also run `swift test --filter ProjectConcurrencyTests` — `start`/`restart` still record `start:<name>`/`restart:<name>` (the concurrency stub inherits the default progress method, which delegates to the gated plain `start`), so concurrency assertions still hold.

- [ ] **Step 8: Commit**

```bash
git add Sources/DDEVUIApp/Models/ProjectCommandState.swift Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Sources/DDEVUIApp/Services/DDEVCommandService.swift Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "feat(progress): stream start/restart output into per-project startProgress"
```

### Task 8: Donut UI in the project row

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ProjectListView.swift:172` (`actionControls`)

- [ ] **Step 1: Replace the busy spinner with a progress-aware donut**

In `ProjectRow.actionControls`, replace the `if viewModel.isBusy(project)` branch's `ProgressView()` with a donut that is determinate when progress is known and indeterminate otherwise:

```swift
    @ViewBuilder
    private var actionControls: some View {
        if viewModel.isBusy(project) {
            ProgressDonut(progress: viewModel.state(for: project.id).startProgress)
                .frame(width: 18, height: 18)
                .help(viewModel.isQueued(project) ? "Queued" : "Running")
                .opacity(viewModel.isQueued(project) ? 0.5 : 1)
        } else {
            HStack(spacing: 4) {
                if project.status == .running {
                    actionButton("Restart", systemImage: "arrow.clockwise") {
                        await viewModel.restart(project)
                    }
                    actionButton("Stop", systemImage: "stop.fill", tint: .red) {
                        await viewModel.stop(project)
                    }
                } else {
                    actionButton("Start", systemImage: "play.fill", tint: .green) {
                        await viewModel.start(project)
                    }
                }
            }
        }
    }
```

- [ ] **Step 2: Add the `ProgressDonut` view**

Add this private view at the bottom of `ProjectListView.swift`:

```swift
/// A small ring indicator. When `progress` is non-nil it fills the ring (0…1); when nil it spins
/// an indeterminate arc. Used for start/restart where determinate progress may be unavailable.
private struct ProgressDonut: View {
    let progress: Double?
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 2.5)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, progress)))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: progress)
            } else {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
            }
        }
    }
}
```

- [ ] **Step 3: Build and manually verify**

```bash
swift build
```
Then run the app from Xcode (or the built product), and:
1. Stop `agilebugs` if running. Click its row's green **Start** (play) button.
2. Confirm: the spinner is now a ring; during start it fills toward (not to) full, and on completion the dot turns green and Start→Restart/Stop **without** pressing the global Refresh.
3. Confirm the inspector overview for that project shows **web/db running** without re-selecting.
4. If a project's start produces no recognized lines, confirm the ring spins indeterminately rather than sticking — never a frozen partial fill.

- [ ] **Step 4: Commit**

```bash
git add Sources/DDEVUIApp/Views/ProjectListView.swift
git commit -m "feat(ui): progress donut for start/restart with indeterminate fallback"
```

---

## Final verification

- [ ] **Full test suite green**

Run: `swift test`
Expected: all tests pass (new + existing).

- [ ] **Manual end-to-end of all three bugs**

1. **Bug 1:** Add Folder → choose an unconfigured folder → fill the sheet → Configure → the project appears **and** comes up running (or shows a clear error if start failed, still listed).
2. **Bug 3:** Start a stopped project from the list → dot goes green, buttons switch, inspector overview updates — all without the global Refresh or re-selecting.
3. **Bug 2:** Start shows the filling donut; an unrecognized-output start shows the spinning (indeterminate) ring.

---

## Self-review (completed by plan author)

- **Spec coverage:** Bug 1 → Task 1. Bug 3 (status carry) → Tasks 2–3. Bug 3 (inspector republish) → Task 3 Step 5. Bug 2 (streaming) → Task 4; (parser) → Tasks 5–6; (state+wiring) → Task 7; (donut + fallback) → Task 8. Non-goal (no polling) respected — no timers added.
- **Placeholder scan:** No TBD/TODO. The only "tune later" is Task 6, which is an explicit capture step with a realistic default table and behavioral tests that hold regardless of exact strings.
- **Type consistency:** `startProgress: Double?` used identically in `ProjectCommandState`, the VM helper, and `ProgressDonut`. `StartProgressParser.consume`/`fraction`/`markCompleted` consistent across parser, tests, and VM. `run(_:onOutputLine:)` signature identical in protocol, `ProcessCommandRunner`, `DDEVCommandService.runDDEV`, and tests. New `DDEVProjectDetails` init params (`status`, `statusDescription`) defaulted, so the 4 existing call sites are untouched.
- **Stub impact:** `DDEVServicing` and `CommandRunning` grow via default-implemented requirements, so `GatedDDEVService`, `SuspendedConfigDDEVService`, `RecordingCommandRunner`, `StubCommandRunner`, `PreviewCommandRunner` need no changes; only `FakeDDEVService` is extended (deliberately, for the new tests).
