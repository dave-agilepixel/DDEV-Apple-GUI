import Foundation

public struct ProjectGroup: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var colorID: GroupColor
    /// Project ids (DDEVProject.id == project name). Identity only — display order of members
    /// comes from the main `projects` array, not this list.
    public var memberIDs: [String]

    public init(id: UUID = UUID(), name: String, colorID: GroupColor, memberIDs: [String] = []) {
        self.id = id
        self.name = name
        self.colorID = colorID
        self.memberIDs = memberIDs
    }
}

public enum GroupColor: String, Codable, CaseIterable, Sendable {
    case blue, teal, green, yellow, orange, red, purple, gray
}
