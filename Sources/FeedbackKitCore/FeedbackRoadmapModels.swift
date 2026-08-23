import Foundation

public enum RoadmapStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case urgent
    case later
    case undecided

    public var id: Self { self }
}

public struct FeedbackRoadmapItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let type: String
    public let roadmapStage: RoadmapStage
    public let rank: Int
    public let archivedAt: Date?
    public let title: String
    public let body: String
    public let locale: String?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct FeedbackRelease: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let version: String
    public let releasedAt: Date
    public let body: String
    public let locale: String?
    public let items: [FeedbackRoadmapItem]

    public static func versionDescending(_ lhs: Self, _ rhs: Self) -> Bool {
        let comparison = lhs.normalizedVersion.compare(
            rhs.normalizedVersion,
            options: [.caseInsensitive, .numeric]
        )
        if comparison != .orderedSame { return comparison == .orderedDescending }
        if lhs.releasedAt != rhs.releasedAt { return lhs.releasedAt > rhs.releasedAt }
        return lhs.id > rhs.id
    }

    public var normalizedVersion: String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }
}
