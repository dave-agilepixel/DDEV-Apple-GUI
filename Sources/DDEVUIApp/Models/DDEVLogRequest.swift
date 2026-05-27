import Foundation

public struct DDEVLogRequest: Equatable, Sendable {
    public enum Service: String, CaseIterable, Identifiable, Sendable {
        case web
        case db
        case router

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .web:
                "Web"
            case .db:
                "Database"
            case .router:
                "Router"
            }
        }
    }

    public static let supportedTailCounts = [50, 100, 250, 500]

    public let service: Service
    public let tailCount: Int
    public let includeTimestamps: Bool

    public init(service: Service = .web, tailCount: Int = 100, includeTimestamps: Bool = false) {
        self.service = service
        self.tailCount = tailCount
        self.includeTimestamps = includeTimestamps
    }
}
