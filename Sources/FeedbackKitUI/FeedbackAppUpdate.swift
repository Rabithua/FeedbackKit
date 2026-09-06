import Foundation

/// An update the host has confirmed is newer than the installed app.
public struct FeedbackAppUpdate: Equatable, Sendable {
    public let currentVersion: String
    public let latestVersion: String
    public let url: URL

    public init(currentVersion: String, latestVersion: String, url: URL) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.url = url
    }
}

/// Supplies the host's update policy without coupling FeedbackKit to an app or store.
public protocol FeedbackAppUpdateChecking: Sendable {
    /// Return nil when no newer version is available. Use a bounded timeout and
    /// honor cancellation; failures allow the user to continue reporting a bug.
    func availableUpdate() async throws -> FeedbackAppUpdate?
}
