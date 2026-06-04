/// A single selectable target for the Manage tab's unified "Run a command" control. Either a
/// framework tool (`ddev <tool> …`) or a raw exec service (`ddev exec --service …`). Pure model so
/// the available-targets logic is unit-testable independent of the view model.
enum RunTarget: Hashable, Sendable, Identifiable {
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
