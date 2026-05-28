import Foundation

public enum DockerRuntime: String, Equatable, Sendable, CaseIterable, Identifiable {
    case dockerDesktop
    case orbstack

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dockerDesktop: "Docker Desktop"
        case .orbstack: "OrbStack"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .dockerDesktop: "com.docker.docker"
        case .orbstack: "dev.kdrag0n.OrbStack"
        }
    }

    public var installURL: URL {
        switch self {
        case .dockerDesktop:
            URL(string: "https://www.docker.com/products/docker-desktop/")!
        case .orbstack:
            URL(string: "https://orbstack.dev/download")!
        }
    }

    public var brewInstallCommand: String {
        switch self {
        case .dockerDesktop: "brew install --cask docker"
        case .orbstack: "brew install --cask orbstack"
        }
    }
}

public enum DockerStatus: Equatable, Sendable {
    case checking
    case ok
    case starting(DockerRuntime)
    case notRunning(DockerRuntime)
    case missing
}

public enum DDEVStatus: Equatable, Sendable {
    case checking
    case ok(version: String?)
    case missing
}

public struct PrerequisiteState: Equatable, Sendable {
    public let docker: DockerStatus
    public let ddev: DDEVStatus

    public init(docker: DockerStatus, ddev: DDEVStatus) {
        self.docker = docker
        self.ddev = ddev
    }

    public static let initial = PrerequisiteState(docker: .checking, ddev: .checking)

    public var allSatisfied: Bool {
        if case .ok = docker, case .ok = ddev { return true }
        return false
    }

    public var isStillChecking: Bool {
        if case .checking = docker { return true }
        if case .checking = ddev { return true }
        return false
    }
}

public enum DDEVInstallMethod {
    public static let brewCommand = "brew install ddev/ddev/ddev"
    public static let installURL = URL(string: "https://ddev.readthedocs.io/en/stable/users/install/")!
}
