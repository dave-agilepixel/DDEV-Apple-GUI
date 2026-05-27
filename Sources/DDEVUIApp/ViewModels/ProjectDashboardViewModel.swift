import Combine
import Foundation

public protocol DDEVServicing: Sendable {
    func listProjects() async throws -> [DDEVProject]
    func start(projectName: String) async throws -> CommandResult
    func stop(projectName: String) async throws -> CommandResult
    func restart(projectName: String) async throws -> CommandResult
    func unlink(projectName: String) async throws -> CommandResult
    func deleteDDEVData(projectName: String) async throws -> CommandResult
    func startProject(in appRoot: String) async throws -> CommandResult
    func configureProject(in appRoot: String, name: String, type: DDEVProjectType, docroot: String) async throws -> CommandResult
    func launchDatabaseTool(_ tool: DDEVDatabaseTool, in appRoot: String) async throws -> CommandResult
    func updateWordPressCore(in appRoot: String) async throws -> CommandResult
    func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult
    func updateWordPressThemes(in appRoot: String) async throws -> CommandResult
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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projects }

        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || project.shortRoot.localizedCaseInsensitiveContains(query)
                || project.projectType.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    public func refresh() async {
        await runAndCapture {
            let loadedProjects = try await self.ddevService.listProjects()
            self.projects = loadedProjects

            if let selectedProject = self.selectedProject, loadedProjects.contains(where: { $0.id == selectedProject.id }) {
                self.selectedProject = loadedProjects.first { $0.id == selectedProject.id }
            } else {
                self.selectedProject = loadedProjects.first
            }

            return nil
        }
    }

    public func startSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.start(projectName: selectedProject.name)
        }
    }

    public func stopSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.stop(projectName: selectedProject.name)
        }
    }

    public func restartSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.restart(projectName: selectedProject.name)
        }
    }

    public func unlinkSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.unlink(projectName: selectedProject.name)
        }
    }

    public func deleteSelectedDDEVData() async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.deleteDDEVData(projectName: selectedProject.name)
        }
    }

    public func startProject(atFolder path: String) async {
        await runMutation {
            try await self.ddevService.startProject(in: path)
        }
    }

    public func configureProject(folder: String, name: String, type: DDEVProjectType, docroot: String) async {
        await runMutation {
            try await self.ddevService.configureProject(in: folder, name: name, type: type, docroot: docroot)
        }
    }

    public func launchDatabaseTool(_ tool: DDEVDatabaseTool) async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.launchDatabaseTool(tool, in: selectedProject.appRoot)
        }
    }

    public func updateWordPressCore() async {
        guard let selectedProject, selectedProject.isWordPress else { return }
        await runMutation {
            try await self.ddevService.updateWordPressCore(in: selectedProject.appRoot)
        }
    }

    public func updateWordPressPlugins() async {
        guard let selectedProject, selectedProject.isWordPress else { return }
        await runMutation {
            try await self.ddevService.updateWordPressPlugins(in: selectedProject.appRoot)
        }
    }

    public func updateWordPressThemes() async {
        guard let selectedProject, selectedProject.isWordPress else { return }
        await runMutation {
            try await self.ddevService.updateWordPressThemes(in: selectedProject.appRoot)
        }
    }

    public func canRunWordPressActions(for project: DDEVProject?) -> Bool {
        project?.isWordPress == true
    }

    private func runMutation(_ operation: @escaping () async throws -> CommandResult) async {
        await runAndCapture {
            let result = try await operation()
            self.lastCommandResult = result
            await self.refresh()
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
