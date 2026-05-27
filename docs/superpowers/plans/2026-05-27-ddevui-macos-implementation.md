# DDEVUI macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first native SwiftUI/Xcode-buildable DDEVUI app for Apple silicon macOS Tahoe 26.x+.

**Architecture:** Create a Swift package that Xcode can open and build, with a SwiftUI executable app target and a test target. Keep DDEV interaction behind a command-runner boundary so the UI never shells out directly.

**Tech Stack:** Swift 6.3, SwiftUI, Foundation, AppKit `NSWorkspace`, XCTest, DDEV CLI.

---

## File Structure

- `Package.swift`: Swift package manifest for the app executable and tests.
- `Sources/DDEVUIApp/DDEVUIApp.swift`: SwiftUI `@main` app entry.
- `Sources/DDEVUIApp/Views/ContentView.swift`: Main Finder-style shell.
- `Sources/DDEVUIApp/Views/ProjectListView.swift`: Project list/search/filter.
- `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`: Selected project actions.
- `Sources/DDEVUIApp/Views/CommandOutputView.swift`: Command output rendering.
- `Sources/DDEVUIApp/Models/DDEVProject.swift`: Project data model and JSON decoding.
- `Sources/DDEVUIApp/Models/CommandResult.swift`: Captured command execution result.
- `Sources/DDEVUIApp/Models/AppSettings.swift`: Local settings model.
- `Sources/DDEVUIApp/Services/CommandRunning.swift`: Protocol and process runner.
- `Sources/DDEVUIApp/Services/DDEVCommandService.swift`: DDEV command adapter.
- `Sources/DDEVUIApp/Services/WorkspaceOpening.swift`: Editor/Finder/site opening.
- `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`: UI state and actions.
- `Tests/DDEVUIAppTests/DDEVProjectDecodingTests.swift`: JSON parsing tests.
- `Tests/DDEVUIAppTests/DDEVCommandServiceTests.swift`: Command mapping tests.
- `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`: View model behavior tests.

The first implementation uses Swift Package Manager because this empty repo has no existing Xcode project and `xcodegen` is not installed. Xcode can open and build the package directly. A generated `.xcodeproj` or notarized archive pipeline can be added later if distribution needs it.

## Task 1: Create Buildable SwiftUI Package Skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/DDEVUIApp/DDEVUIApp.swift`
- Create: `Sources/DDEVUIApp/Views/ContentView.swift`
- Create: `Tests/DDEVUIAppTests/SmokeTests.swift`

- [ ] **Step 1: Write the package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DDEVUI",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "DDEVUI", targets: ["DDEVUIApp"])
    ],
    targets: [
        .executableTarget(
            name: "DDEVUIApp",
            path: "Sources/DDEVUIApp"
        ),
        .testTarget(
            name: "DDEVUIAppTests",
            dependencies: ["DDEVUIApp"],
            path: "Tests/DDEVUIAppTests"
        )
    ]
)
```

- [ ] **Step 2: Add minimal SwiftUI app entry**

Create `Sources/DDEVUIApp/DDEVUIApp.swift`:

```swift
import SwiftUI

@main
struct DDEVUIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1040, minHeight: 680)
        }
    }
}
```

- [ ] **Step 3: Add a minimal content view**

Create `Sources/DDEVUIApp/Views/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("Projects", systemImage: "shippingbox")
                Label("Running", systemImage: "play.circle")
                Label("WordPress", systemImage: "w.circle")
                Label("Settings", systemImage: "gearshape")
            }
            .navigationTitle("DDEVUI")
        } content: {
            Text("Projects")
                .font(.title)
        } detail: {
            Text("Select a project")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 4: Add a smoke test**

Create `Tests/DDEVUIAppTests/SmokeTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

final class SmokeTests: XCTestCase {
    func testTestBundleLoads() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 5: Verify build and tests**

Run:

```bash
swift test
swift build
```

Expected: both commands pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: Add SwiftUI app skeleton"
```

## Task 2: Decode DDEV Project List JSON

**Files:**
- Create: `Sources/DDEVUIApp/Models/DDEVProject.swift`
- Create: `Tests/DDEVUIAppTests/DDEVProjectDecodingTests.swift`

- [ ] **Step 1: Write failing JSON decoding tests**

Create `Tests/DDEVUIAppTests/DDEVProjectDecodingTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

final class DDEVProjectDecodingTests: XCTestCase {
    func testDecodesProjectsFromDDEVListPayload() throws {
        let data = """
        {
          "raw": [
            {
              "name": "aqua-pura",
              "approot": "/Users/dave/Development/agilepixel/aqua-pura",
              "shortroot": "~/Development/agilepixel/aqua-pura",
              "status": "running",
              "status_desc": "running",
              "type": "wordpress",
              "docroot": "",
              "primary_url": "https://aqua-pura.ddev.site",
              "httpurl": "http://aqua-pura.ddev.site",
              "httpsurl": "https://aqua-pura.ddev.site",
              "mailpit_url": "http://aqua-pura.ddev.site:8025",
              "mailpit_https_url": "https://aqua-pura.ddev.site:8026",
              "xhgui_url": "http://aqua-pura.ddev.site:8143",
              "xhgui_https_url": "https://aqua-pura.ddev.site:8142",
              "mutagen_enabled": true,
              "mutagen_status": "ok"
            }
          ]
        }
        """.data(using: .utf8)!

        let projects = try DDEVProject.decodeListPayload(data)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "aqua-pura")
        XCTAssertEqual(projects[0].appRoot, "/Users/dave/Development/agilepixel/aqua-pura")
        XCTAssertEqual(projects[0].status, .running)
        XCTAssertEqual(projects[0].projectType, .wordpress)
        XCTAssertEqual(projects[0].primaryURL?.absoluteString, "https://aqua-pura.ddev.site")
        XCTAssertTrue(projects[0].isWordPress)
    }

    func testNonWordPressProjectIsNotWordPress() throws {
        let project = DDEVProject(
            name: "agilebugs",
            appRoot: "/tmp/agilebugs",
            shortRoot: "~/agilebugs",
            status: .paused,
            statusDescription: "paused",
            projectType: .laravel,
            docroot: "public",
            primaryURL: nil,
            httpURL: nil,
            httpsURL: nil,
            mailpitURL: nil,
            mailpitHTTPSURL: nil,
            xhguiURL: nil,
            xhguiHTTPSURL: nil,
            mutagenEnabled: true,
            mutagenStatus: "ok"
        )

        XCTAssertFalse(project.isWordPress)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter DDEVProjectDecodingTests
```

Expected: fail because `DDEVProject` is not defined.

- [ ] **Step 3: Implement the project model**

Create `Sources/DDEVUIApp/Models/DDEVProject.swift`:

```swift
import Foundation

public struct DDEVProject: Identifiable, Equatable, Sendable {
    public var id: String { name }

    public let name: String
    public let appRoot: String
    public let shortRoot: String
    public let status: DDEVProjectStatus
    public let statusDescription: String
    public let projectType: DDEVProjectType
    public let docroot: String
    public let primaryURL: URL?
    public let httpURL: URL?
    public let httpsURL: URL?
    public let mailpitURL: URL?
    public let mailpitHTTPSURL: URL?
    public let xhguiURL: URL?
    public let xhguiHTTPSURL: URL?
    public let mutagenEnabled: Bool
    public let mutagenStatus: String?

    public var isWordPress: Bool {
        projectType == .wordpress || projectType == .wpBedrock
    }
}

public enum DDEVProjectStatus: String, Codable, Sendable {
    case running
    case paused
    case stopped
    case unknown
}

public enum DDEVProjectType: String, Codable, Sendable {
    case wordpress
    case wpBedrock = "wp-bedrock"
    case laravel
    case generic
    case other
}

extension DDEVProject {
    public static func decodeListPayload(_ data: Data) throws -> [DDEVProject] {
        let payload = try JSONDecoder().decode(DDEVListPayload.self, from: data)
        return payload.raw.map(DDEVProject.init(raw:))
    }

    private init(raw: RawDDEVProject) {
        self.name = raw.name
        self.appRoot = raw.approot
        self.shortRoot = raw.shortroot
        self.status = DDEVProjectStatus(rawValue: raw.status) ?? .unknown
        self.statusDescription = raw.statusDesc
        self.projectType = DDEVProjectType(rawValue: raw.type) ?? .other
        self.docroot = raw.docroot
        self.primaryURL = URL(string: raw.primaryURL)
        self.httpURL = URL(string: raw.httpURL)
        self.httpsURL = URL(string: raw.httpsURL)
        self.mailpitURL = URL(string: raw.mailpitURL)
        self.mailpitHTTPSURL = URL(string: raw.mailpitHTTPSURL)
        self.xhguiURL = URL(string: raw.xhguiURL)
        self.xhguiHTTPSURL = URL(string: raw.xhguiHTTPSURL)
        self.mutagenEnabled = raw.mutagenEnabled
        self.mutagenStatus = raw.mutagenStatus
    }
}

private struct DDEVListPayload: Decodable {
    let raw: [RawDDEVProject]
}

private struct RawDDEVProject: Decodable {
    let name: String
    let approot: String
    let shortroot: String
    let status: String
    let statusDesc: String
    let type: String
    let docroot: String
    let primaryURL: String
    let httpURL: String
    let httpsURL: String
    let mailpitURL: String
    let mailpitHTTPSURL: String
    let xhguiURL: String
    let xhguiHTTPSURL: String
    let mutagenEnabled: Bool
    let mutagenStatus: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case approot
        case shortroot
        case status
        case statusDesc = "status_desc"
        case type
        case docroot
        case primaryURL = "primary_url"
        case httpURL = "httpurl"
        case httpsURL = "httpsurl"
        case mailpitURL = "mailpit_url"
        case mailpitHTTPSURL = "mailpit_https_url"
        case xhguiURL = "xhgui_url"
        case xhguiHTTPSURL = "xhgui_https_url"
        case mutagenEnabled = "mutagen_enabled"
        case mutagenStatus = "mutagen_status"
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run:

```bash
swift test --filter DDEVProjectDecodingTests
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Models/DDEVProject.swift Tests/DDEVUIAppTests/DDEVProjectDecodingTests.swift
git commit -m "feat: Decode DDEV project list"
```

## Task 3: Add Command Runner And DDEV Service

**Files:**
- Create: `Sources/DDEVUIApp/Models/CommandResult.swift`
- Create: `Sources/DDEVUIApp/Services/CommandRunning.swift`
- Create: `Sources/DDEVUIApp/Services/DDEVCommandService.swift`
- Create: `Tests/DDEVUIAppTests/DDEVCommandServiceTests.swift`

- [ ] **Step 1: Write command mapping tests**

Create `Tests/DDEVUIAppTests/DDEVCommandServiceTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

final class DDEVCommandServiceTests: XCTestCase {
    func testListProjectsRunsDDEVListJSON() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success(stdout: #"{"raw":[]}"#)))
        let service = DDEVCommandService(commandRunner: runner)

        _ = try await service.listProjects()

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["list", "-j"], workingDirectory: nil)
        ])
    }

    func testLifecycleCommandsUseProjectName() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner)

        _ = try await service.start(projectName: "aqua-pura")
        _ = try await service.stop(projectName: "aqua-pura")
        _ = try await service.restart(projectName: "aqua-pura")
        _ = try await service.unlink(projectName: "aqua-pura")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["start", "aqua-pura"], workingDirectory: nil),
            CommandSpec(executable: "ddev", arguments: ["stop", "aqua-pura"], workingDirectory: nil),
            CommandSpec(executable: "ddev", arguments: ["restart", "aqua-pura"], workingDirectory: nil),
            CommandSpec(executable: "ddev", arguments: ["stop", "--unlist", "aqua-pura"], workingDirectory: nil)
        ])
    }

    func testWordPressPresetCommandsRunInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner)

        _ = try await service.updateWordPressCore(in: "/Users/dave/site")
        _ = try await service.updateWordPressPlugins(in: "/Users/dave/site")
        _ = try await service.updateWordPressThemes(in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["wp", "core", "update"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["wp", "plugin", "update", "--all"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["wp", "theme", "update", "--all"], workingDirectory: "/Users/dave/site")
        ])
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter DDEVCommandServiceTests
```

Expected: fail because command service types are missing.

- [ ] **Step 3: Implement command result and runner**

Create `Sources/DDEVUIApp/Models/CommandResult.swift`:

```swift
import Foundation

public struct CommandResult: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let startedAt: Date
    public let finishedAt: Date
    public let wasCancelled: Bool

    public var succeeded: Bool { exitCode == 0 && !wasCancelled }

    public static func success(stdout: String = "") -> CommandResult {
        let now = Date()
        return CommandResult(
            executable: "ddev",
            arguments: [],
            workingDirectory: nil,
            exitCode: 0,
            stdout: stdout,
            stderr: "",
            startedAt: now,
            finishedAt: now,
            wasCancelled: false
        )
    }
}
```

Create `Sources/DDEVUIApp/Services/CommandRunning.swift`:

```swift
import Foundation

public struct CommandSpec: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?

    public init(executable: String, arguments: [String], workingDirectory: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

public protocol CommandRunning: Sendable {
    func run(_ spec: CommandSpec) async throws -> CommandResult
}

public enum CommandRunnerError: Error, Equatable {
    case nonZeroExit(CommandResult)
}

public final class ProcessCommandRunner: CommandRunning, @unchecked Sendable {
    public init() {}

    public func run(_ spec: CommandSpec) async throws -> CommandResult {
        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [spec.executable] + spec.arguments
        if let workingDirectory = spec.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let result = CommandResult(
            executable: spec.executable,
            arguments: spec.arguments,
            workingDirectory: spec.workingDirectory,
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            startedAt: startedAt,
            finishedAt: Date(),
            wasCancelled: false
        )

        if result.succeeded {
            return result
        }

        throw CommandRunnerError.nonZeroExit(result)
    }
}

public final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    public private(set) var commands: [CommandSpec] = []
    private let result: Result<CommandResult, Error>

    public init(result: Result<CommandResult, Error>) {
        self.result = result
    }

    public func run(_ spec: CommandSpec) async throws -> CommandResult {
        commands.append(spec)
        return try result.get()
    }
}
```

- [ ] **Step 4: Implement DDEV command service**

Create `Sources/DDEVUIApp/Services/DDEVCommandService.swift`:

```swift
import Foundation

public final class DDEVCommandService: Sendable {
    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func listProjects() async throws -> [DDEVProject] {
        let result = try await commandRunner.run(CommandSpec(executable: "ddev", arguments: ["list", "-j"]))
        return try DDEVProject.decodeListPayload(Data(result.stdout.utf8))
    }

    @discardableResult
    public func start(projectName: String) async throws -> CommandResult {
        try await runDDEV(["start", projectName])
    }

    @discardableResult
    public func stop(projectName: String) async throws -> CommandResult {
        try await runDDEV(["stop", projectName])
    }

    @discardableResult
    public func restart(projectName: String) async throws -> CommandResult {
        try await runDDEV(["restart", projectName])
    }

    @discardableResult
    public func unlink(projectName: String) async throws -> CommandResult {
        try await runDDEV(["stop", "--unlist", projectName])
    }

    @discardableResult
    public func deleteDDEVData(projectName: String) async throws -> CommandResult {
        try await runDDEV(["delete", projectName])
    }

    @discardableResult
    public func launchDatabaseTool(_ tool: DDEVDatabaseTool, in appRoot: String) async throws -> CommandResult {
        try await runDDEV([tool.rawValue], workingDirectory: appRoot)
    }

    @discardableResult
    public func updateWordPressCore(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["wp", "core", "update"], workingDirectory: appRoot)
    }

    @discardableResult
    public func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["wp", "plugin", "update", "--all"], workingDirectory: appRoot)
    }

    @discardableResult
    public func updateWordPressThemes(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["wp", "theme", "update", "--all"], workingDirectory: appRoot)
    }

    private func runDDEV(_ arguments: [String], workingDirectory: String? = nil) async throws -> CommandResult {
        try await commandRunner.run(CommandSpec(executable: "ddev", arguments: arguments, workingDirectory: workingDirectory))
    }
}

public enum DDEVDatabaseTool: String, CaseIterable, Sendable {
    case sequelAce = "sequelace"
    case tablePlus = "tableplus"
    case querious = "querious"
    case dbeaver = "dbeaver"
}
```

- [ ] **Step 5: Verify tests pass**

Run:

```bash
swift test --filter DDEVCommandServiceTests
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/DDEVUIApp/Models/CommandResult.swift Sources/DDEVUIApp/Services Tests/DDEVUIAppTests/DDEVCommandServiceTests.swift
git commit -m "feat: Add DDEV command service"
```

## Task 4: Build Dashboard View Model

**Files:**
- Create: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
- Create: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

- [ ] **Step 1: Write view model tests**

Create `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

@MainActor
final class ProjectDashboardViewModelTests: XCTestCase {
    func testRefreshLoadsProjectsAndSelectsFirstProject() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.projects, [.sampleWordPress])
        XCTAssertEqual(viewModel.selectedProject, .sampleWordPress)
        XCTAssertNil(viewModel.lastErrorMessage)
    }

    func testSearchFiltersProjects() {
        let viewModel = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []))
        viewModel.projects = [.sampleWordPress, .sampleLaravel]
        viewModel.searchText = "agile"

        XCTAssertEqual(viewModel.filteredProjects, [.sampleLaravel])
    }

    func testWordPressActionsOnlyAvailableForWordPressProjects() {
        let viewModel = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []))

        XCTAssertTrue(viewModel.canRunWordPressActions(for: .sampleWordPress))
        XCTAssertFalse(viewModel.canRunWordPressActions(for: .sampleLaravel))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter ProjectDashboardViewModelTests
```

Expected: fail because `ProjectDashboardViewModel` and fake service protocol are missing.

- [ ] **Step 3: Implement service protocol and view model**

Create `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`:

```swift
import Foundation

public protocol DDEVServicing: Sendable {
    func listProjects() async throws -> [DDEVProject]
    func start(projectName: String) async throws -> CommandResult
    func stop(projectName: String) async throws -> CommandResult
    func restart(projectName: String) async throws -> CommandResult
    func unlink(projectName: String) async throws -> CommandResult
}

extension DDEVCommandService: DDEVServicing {}

@MainActor
public final class ProjectDashboardViewModel: ObservableObject {
    @Published public var projects: [DDEVProject] = []
    @Published public var selectedProject: DDEVProject?
    @Published public var searchText = ""
    @Published public var isRunningCommand = false
    @Published public var lastCommandResult: CommandResult?
    @Published public var lastErrorMessage: String?

    private let ddevService: DDEVServicing

    public init(ddevService: DDEVServicing = DDEVCommandService()) {
        self.ddevService = ddevService
    }

    public var filteredProjects: [DDEVProject] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return projects }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(trimmedSearch)
                || project.shortRoot.localizedCaseInsensitiveContains(trimmedSearch)
                || project.projectType.rawValue.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    public func refresh() async {
        await runAndCapture {
            let loadedProjects = try await ddevService.listProjects()
            projects = loadedProjects
            if selectedProject == nil || !loadedProjects.contains(where: { $0.id == selectedProject?.id }) {
                selectedProject = loadedProjects.first
            }
            return nil
        }
    }

    public func startSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await ddevService.start(projectName: selectedProject.name)
        }
    }

    public func stopSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await ddevService.stop(projectName: selectedProject.name)
        }
    }

    public func restartSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await ddevService.restart(projectName: selectedProject.name)
        }
    }

    public func unlinkSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await ddevService.unlink(projectName: selectedProject.name)
        }
    }

    public func canRunWordPressActions(for project: DDEVProject?) -> Bool {
        project?.isWordPress == true
    }

    private func runMutation(_ operation: @escaping () async throws -> CommandResult) async {
        await runAndCapture {
            let result = try await operation()
            lastCommandResult = result
            await refresh()
            return result
        }
    }

    private func runAndCapture(_ operation: @escaping () async throws -> CommandResult?) async {
        isRunningCommand = true
        lastErrorMessage = nil
        defer { isRunningCommand = false }

        do {
            _ = try await operation()
        } catch {
            lastErrorMessage = String(describing: error)
        }
    }
}
```

- [ ] **Step 4: Add test fixtures**

Append to `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`:

```swift
private struct FakeDDEVService: DDEVServicing {
    let projects: [DDEVProject]

    func listProjects() async throws -> [DDEVProject] { projects }
    func start(projectName: String) async throws -> CommandResult { .success() }
    func stop(projectName: String) async throws -> CommandResult { .success() }
    func restart(projectName: String) async throws -> CommandResult { .success() }
    func unlink(projectName: String) async throws -> CommandResult { .success() }
}

extension DDEVProject {
    static let sampleWordPress = DDEVProject(
        name: "aqua-pura",
        appRoot: "/Users/dave/Development/agilepixel/aqua-pura",
        shortRoot: "~/Development/agilepixel/aqua-pura",
        status: .running,
        statusDescription: "running",
        projectType: .wordpress,
        docroot: "",
        primaryURL: URL(string: "https://aqua-pura.ddev.site"),
        httpURL: nil,
        httpsURL: nil,
        mailpitURL: nil,
        mailpitHTTPSURL: nil,
        xhguiURL: nil,
        xhguiHTTPSURL: nil,
        mutagenEnabled: true,
        mutagenStatus: "ok"
    )

    static let sampleLaravel = DDEVProject(
        name: "agilebugs",
        appRoot: "/Users/dave/Development/agilepixel/agilebugs",
        shortRoot: "~/Development/agilepixel/agilebugs",
        status: .paused,
        statusDescription: "paused",
        projectType: .laravel,
        docroot: "public",
        primaryURL: URL(string: "https://agilebugs.ddev.site"),
        httpURL: nil,
        httpsURL: nil,
        mailpitURL: nil,
        mailpitHTTPSURL: nil,
        xhguiURL: nil,
        xhguiHTTPSURL: nil,
        mutagenEnabled: true,
        mutagenStatus: "ok"
    )
}
```

- [ ] **Step 5: Verify tests pass**

Run:

```bash
swift test --filter ProjectDashboardViewModelTests
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/DDEVUIApp/ViewModels Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift
git commit -m "feat: Add project dashboard state"
```

## Task 5: Wire Project List And Inspector UI

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ContentView.swift`
- Create: `Sources/DDEVUIApp/Views/ProjectListView.swift`
- Create: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`
- Create: `Sources/DDEVUIApp/Views/CommandOutputView.swift`

- [ ] **Step 1: Replace content view with dashboard shell**

Update `Sources/DDEVUIApp/Views/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ProjectDashboardViewModel()

    var body: some View {
        NavigationSplitView {
            List {
                Label("Projects", systemImage: "shippingbox")
                Label("Running", systemImage: "play.circle")
                Label("WordPress", systemImage: "w.circle")
                Label("Settings", systemImage: "gearshape")
            }
            .navigationTitle("DDEVUI")
        } content: {
            ProjectListView(viewModel: viewModel)
        } detail: {
            ProjectInspectorView(viewModel: viewModel)
        }
        .task {
            await viewModel.refresh()
        }
        .toolbar {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 2: Add project list view**

Create `Sources/DDEVUIApp/Views/ProjectListView.swift`:

```swift
import SwiftUI

struct ProjectListView: View {
    @ObservedObject var viewModel: ProjectDashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            List(selection: $viewModel.selectedProject) {
                ForEach(viewModel.filteredProjects) { project in
                    ProjectRow(project: project)
                        .tag(project)
                }
            }
        }
        .navigationTitle("Projects")
    }

    private var searchBar: some View {
        TextField("Search projects", text: $viewModel.searchText)
            .textFieldStyle(.roundedBorder)
            .padding()
    }
}

private struct ProjectRow: View {
    let project: DDEVProject

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.name)
                    .font(.headline)
                Spacer()
                Text(project.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(project.status == .running ? .green : .secondary)
            }
            HStack {
                Text(project.projectType.rawValue)
                Text(project.shortRoot)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Add inspector view**

Create `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`:

```swift
import SwiftUI

struct ProjectInspectorView: View {
    @ObservedObject var viewModel: ProjectDashboardViewModel

    var body: some View {
        Group {
            if let project = viewModel.selectedProject {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(project)
                        lifecycleActions
                        dailyTools(project)
                        if viewModel.canRunWordPressActions(for: project) {
                            wordpressActions
                        }
                        dangerActions
                        CommandOutputView(result: viewModel.lastCommandResult, errorMessage: viewModel.lastErrorMessage)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("No Project Selected", systemImage: "shippingbox")
            }
        }
    }

    private func header(_ project: DDEVProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(.largeTitle.bold())
            Text(project.appRoot)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var lifecycleActions: some View {
        actionSection("Lifecycle") {
            Button("Start") { Task { await viewModel.startSelectedProject() } }
            Button("Stop") { Task { await viewModel.stopSelectedProject() } }
            Button("Restart") { Task { await viewModel.restartSelectedProject() } }
        }
    }

    private func dailyTools(_ project: DDEVProject) -> some View {
        actionSection("Daily Tools") {
            Button("Open Site") {
                if let url = project.primaryURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .disabled(project.primaryURL == nil)
            Button("Open Folder") {
                NSWorkspace.shared.open(URL(fileURLWithPath: project.appRoot))
            }
        }
    }

    private var wordpressActions: some View {
        actionSection("WordPress") {
            Button("Update Core") {}
            Button("Update Plugins") {}
            Button("Update Themes") {}
        }
    }

    private var dangerActions: some View {
        actionSection("Danger") {
            Button("Unlink From List", role: .destructive) {
                Task { await viewModel.unlinkSelectedProject() }
            }
            Button("Delete DDEV Data", role: .destructive) {}
            Button("Delete Source Folder", role: .destructive) {}
        }
    }

    private func actionSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            HStack {
                content()
            }
            .buttonStyle(.bordered)
        }
    }
}
```

- [ ] **Step 4: Add command output view**

Create `Sources/DDEVUIApp/Views/CommandOutputView.swift`:

```swift
import SwiftUI

struct CommandOutputView: View {
    let result: CommandResult?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Command Output")
                .font(.headline)
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if let result {
                Text(result.stdout.isEmpty ? "No output" : result.stdout)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
```

- [ ] **Step 5: Verify build**

Run:

```bash
swift build
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/DDEVUIApp/Views Sources/DDEVUIApp/DDEVUIApp.swift
git commit -m "feat: Add project dashboard UI"
```

## Task 6: Add Editor, DB, And WordPress Actions

**Files:**
- Create: `Sources/DDEVUIApp/Services/WorkspaceOpening.swift`
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`

- [ ] **Step 1: Add workspace opener**

Create `Sources/DDEVUIApp/Services/WorkspaceOpening.swift`:

```swift
import AppKit
import Foundation

public enum EditorChoice: String, CaseIterable, Sendable {
    case cursor = "Cursor"
    case visualStudioCode = "Visual Studio Code"
    case finder = "Finder"
}

public protocol WorkspaceOpening: Sendable {
    func openURL(_ url: URL)
    func openFolder(_ path: String, editor: EditorChoice)
}

public final class MacWorkspaceOpener: WorkspaceOpening, @unchecked Sendable {
    public init() {}

    public func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func openFolder(_ path: String, editor: EditorChoice) {
        let url = URL(fileURLWithPath: path)
        switch editor {
        case .finder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .cursor:
            open(url, withBundleIdentifier: "com.todesktop.230313mzl4w4u92")
        case .visualStudioCode:
            open(url, withBundleIdentifier: "com.microsoft.VSCode")
        }
    }

    private func open(_ url: URL, withBundleIdentifier bundleIdentifier: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
```

- [ ] **Step 2: Extend view model actions**

Add methods to `ProjectDashboardViewModel`:

```swift
public func launchDatabaseTool(_ tool: DDEVDatabaseTool) async {
    guard let selectedProject else { return }
    await runMutation {
        try await ddevService.launchDatabaseTool(tool, in: selectedProject.appRoot)
    }
}

public func updateWordPressCore() async {
    guard let selectedProject, selectedProject.isWordPress else { return }
    await runMutation {
        try await ddevService.updateWordPressCore(in: selectedProject.appRoot)
    }
}

public func updateWordPressPlugins() async {
    guard let selectedProject, selectedProject.isWordPress else { return }
    await runMutation {
        try await ddevService.updateWordPressPlugins(in: selectedProject.appRoot)
    }
}

public func updateWordPressThemes() async {
    guard let selectedProject, selectedProject.isWordPress else { return }
    await runMutation {
        try await ddevService.updateWordPressThemes(in: selectedProject.appRoot)
    }
}
```

Also extend `DDEVServicing` with these methods:

```swift
func launchDatabaseTool(_ tool: DDEVDatabaseTool, in appRoot: String) async throws -> CommandResult
func updateWordPressCore(in appRoot: String) async throws -> CommandResult
func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult
func updateWordPressThemes(in appRoot: String) async throws -> CommandResult
```

- [ ] **Step 3: Wire buttons in inspector**

Update DB and WP sections in `ProjectInspectorView`:

```swift
private func dailyTools(_ project: DDEVProject) -> some View {
    actionSection("Daily Tools") {
        Button("Open Site") {
            if let url = project.primaryURL {
                NSWorkspace.shared.open(url)
            }
        }
        .disabled(project.primaryURL == nil)
        Button("Open Folder") {
            NSWorkspace.shared.open(URL(fileURLWithPath: project.appRoot))
        }
        Menu("Database") {
            Button("Sequel Ace") { Task { await viewModel.launchDatabaseTool(.sequelAce) } }
            Button("TablePlus") { Task { await viewModel.launchDatabaseTool(.tablePlus) } }
            Button("Querious") { Task { await viewModel.launchDatabaseTool(.querious) } }
            Button("DBeaver") { Task { await viewModel.launchDatabaseTool(.dbeaver) } }
        }
    }
}

private var wordpressActions: some View {
    actionSection("WordPress") {
        Button("Update Core") { Task { await viewModel.updateWordPressCore() } }
        Button("Update Plugins") { Task { await viewModel.updateWordPressPlugins() } }
        Button("Update Themes") { Task { await viewModel.updateWordPressThemes() } }
    }
}
```

- [ ] **Step 4: Verify build**

Run:

```bash
swift build
swift test
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp
git commit -m "feat: Add daily project actions"
```

## Task 7: Add Confirmation And Add Folder Flows

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ContentView.swift`
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`

- [ ] **Step 1: Add delete and add-folder view model methods**

Add to `ProjectDashboardViewModel`:

```swift
public func deleteSelectedDDEVData() async {
    guard let selectedProject else { return }
    await runMutation {
        try await ddevService.deleteDDEVData(projectName: selectedProject.name)
    }
}

public func startProject(atFolder path: String) async {
    await runAndCapture {
        let result = try await ddevService.startProject(in: path)
        await refresh()
        return result
    }
}

public func configureProject(folder: String, name: String, type: DDEVProjectType, docroot: String) async {
    await runAndCapture {
        let result = try await ddevService.configureProject(
            in: folder,
            name: name,
            type: type,
            docroot: docroot
        )
        await refresh()
        return result
    }
}
```

Also extend `DDEVServicing` and `DDEVCommandService`:

```swift
@discardableResult
public func startProject(in appRoot: String) async throws -> CommandResult {
    try await runDDEV(["start"], workingDirectory: appRoot)
}

@discardableResult
public func configureProject(in appRoot: String, name: String, type: DDEVProjectType, docroot: String) async throws -> CommandResult {
    try await runDDEV(
        ["config", "--project-name=\(name)", "--project-type=\(type.rawValue)", "--docroot=\(docroot)"],
        workingDirectory: appRoot
    )
}
```

- [ ] **Step 2: Add destructive confirmation dialogs**

In `ProjectInspectorView`, add state:

```swift
@State private var confirmUnlink = false
@State private var confirmDeleteDDEVData = false
```

Change danger buttons to set those booleans, then add:

```swift
.confirmationDialog("Unlink this project from DDEV?", isPresented: $confirmUnlink) {
    Button("Unlink", role: .destructive) {
        Task { await viewModel.unlinkSelectedProject() }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This removes the project from the DDEV list but leaves files and database data alone.")
}
.confirmationDialog("Delete DDEV data?", isPresented: $confirmDeleteDDEVData) {
    Button("Delete DDEV Data", role: .destructive) {
        Task { await viewModel.deleteSelectedDDEVData() }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This removes DDEV project data including database data. It does not delete the source folder.")
}
```

- [ ] **Step 3: Add folder picker toolbar action**

In `ContentView`, add a toolbar button:

```swift
Button {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
        Task { await viewModel.startProject(atFolder: url.path) }
    }
} label: {
    Label("Add Folder", systemImage: "folder.badge.plus")
}
```

- [ ] **Step 4: Verify build and tests**

Run:

```bash
swift build
swift test
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp
git commit -m "feat: Add project safety flows"
```

## Task 8: Manual Integration Check

**Files:**
- Modify: `docs/superpowers/specs/2026-05-27-ddevui-macos-design.md` only if implementation discoveries require a spec correction.

- [ ] **Step 1: Run all automated checks**

Run:

```bash
swift test
swift build
```

Expected: pass.

- [ ] **Step 2: Launch the app**

Run:

```bash
swift run DDEVUI
```

Expected: the app opens a native macOS window.

- [ ] **Step 3: Verify local DDEV discovery**

In the app:

- Confirm projects from `ddev list -j` appear.
- Select a WordPress project and confirm WordPress actions are visible.
- Select a non-WordPress project and confirm WordPress actions are hidden.

- [ ] **Step 4: Verify safe actions**

Use a low-risk project:

- Refresh project list.
- Open site.
- Open folder.
- Start a paused project.
- Stop it again.

Expected: command output is visible and project list refreshes.

- [ ] **Step 5: Commit any fixes**

If changes were required:

```bash
git add Sources Tests docs
git commit -m "fix: Stabilise DDEVUI integration"
```

If no changes were required, do not create an empty commit.

## Self-Review

- Spec coverage: The plan covers native SwiftUI app creation, DDEV project listing, lifecycle actions, editor/Finder opening, DB command delegation, WP safe presets, command output, delete confirmations, Add Folder starting existing projects, new-project `ddev config` service support, and testing.
- Language scan: No red-flag filler language or intentionally blank implementation steps remain.
- Type consistency: `DDEVProject`, `CommandResult`, `CommandSpec`, `DDEVCommandService`, and `ProjectDashboardViewModel` are used consistently across tasks.
