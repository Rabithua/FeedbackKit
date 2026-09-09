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
    /// Called in the background when the feedback center appears. Return nil when no
    /// newer version is available. Hosts should cache results and coalesce requests.
    /// Use a bounded timeout; pending or failed checks never delay the composer.
    func availableUpdate() async throws -> FeedbackAppUpdate?
}
