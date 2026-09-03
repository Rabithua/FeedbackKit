import FeedbackKitCore
import Foundation
import Observation

/// A ready-to-present administrator reply and the fully loaded conversation it belongs to.
public struct FeedbackReplyPresentation: Hashable, Identifiable, Sendable {
    public let event: FeedbackInboxEvent
    public let detail: FeedbackDetail

    public var id: Int { event.sequence }
    public var feedbackID: String { event.feedbackId }
    public var cursor: Int { event.sequence }

    public init(event: FeedbackInboxEvent, detail: FeedbackDetail) {
        self.event = event
        self.detail = detail
    }
}

/// Coordinates opt-in foreground checks for replies without owning app lifecycle observation.
///
/// Hosts explicitly call ``beginForegroundCycle()`` when their scene becomes active and
/// ``endForegroundCycle()`` when it enters the background. Repeated active notifications in the
/// same cycle produce at most one completed inbox check. A cancelled in-flight call can be retried.
@MainActor
@Observable
public final class FeedbackReplyInboxController {
    /// The item a host can drive with `sheet(item:)`. Setting it to `nil` dismisses the sheet.
    public var pendingPresentation: FeedbackReplyPresentation?
    public private(set) var isChecking = false
    public private(set) var isAcknowledging = false
    public private(set) var lastAcknowledgedCursor: Int?
    public private(set) var lastError: Error?

    let client: FeedbackClient

    @ObservationIgnored private var cycle: UInt = 0
    @ObservationIgnored private var checkedCycle: UInt?
    @ObservationIgnored private var checkGeneration: UInt = 0
    @ObservationIgnored private var checkTask: Task<FeedbackReplyPresentation?, Error>?

    public init(client: FeedbackClient) {
        self.client = client
    }

    /// Checks once during the current foreground cycle and prepares only the newest unread reply.
    ///
    /// The check is side-effect free for an app that has never established a visitor identity.
    /// Inbox pages are exhausted before a reply is selected, and its conversation is loaded before
    /// ``pendingPresentation`` changes.
    public func beginForegroundCycle() async {
        if checkedCycle == cycle {
            guard checkTask?.isCancelled == true else { return }
        }
        checkedCycle = cycle
        guard pendingPresentation == nil else { return }

        let activeCycle = cycle
        checkGeneration &+= 1
        let activeGeneration = checkGeneration
        let task = Task<FeedbackReplyPresentation?, Error> { [client] in
            try await Self.loadLatestReply(using: client)
        }
        checkTask = task
        isChecking = true
        lastError = nil

        do {
            let presentation = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard activeCycle == cycle, activeGeneration == checkGeneration else { return }
            checkTask = nil
            isChecking = false
            if pendingPresentation == nil {
                pendingPresentation = presentation
            }
        } catch is CancellationError {
            guard activeCycle == cycle, activeGeneration == checkGeneration else { return }
            checkedCycle = nil
            checkTask = nil
            isChecking = false
        } catch {
            guard activeCycle == cycle, activeGeneration == checkGeneration else { return }
            checkTask = nil
            isChecking = false
            lastError = error
        }
    }

    /// Ends the current cycle, cancels its in-flight check, and allows one check next time.
    public func endForegroundCycle() {
        cycle &+= 1
        checkGeneration &+= 1
        checkedCycle = nil
        checkTask?.cancel()
        checkTask = nil
        isChecking = false
    }

    /// Acknowledges the reply cursor. The default conversation sheet invokes this on appearance.
    public func acknowledge(_ presentation: FeedbackReplyPresentation) async {
        guard pendingPresentation?.id == presentation.id,
              isAcknowledging == false,
              presentation.cursor > (lastAcknowledgedCursor ?? 0)
        else { return }

        isAcknowledging = true
        lastError = nil
        defer { isAcknowledging = false }
        do {
            guard let cursor = try await client.acknowledgeExistingVisitorInbox(
                cursor: presentation.cursor
            ) else { return }
            guard pendingPresentation?.id == presentation.id else { return }
            lastAcknowledgedCursor = max(lastAcknowledgedCursor ?? 0, cursor)
        } catch is CancellationError {
        } catch {
            lastError = error
        }
    }

    /// Clears the currently prepared presentation.
    public func dismissPresentation() {
        pendingPresentation = nil
    }

    /// Clears `presentation` only if it is still the currently prepared item.
    public func dismissPresentation(_ presentation: FeedbackReplyPresentation) {
        guard pendingPresentation?.id == presentation.id else { return }
        pendingPresentation = nil
    }

    nonisolated private static func loadLatestReply(
        using client: FeedbackClient
    ) async throws -> FeedbackReplyPresentation? {
        guard var page = try await client.existingVisitorInbox() else { return nil }

        var acknowledgedCursor = page.acknowledgedCursor
        var requestedCursor: Int?
        var latestReply = page.events
            .filter { $0.type == .adminReply && $0.sequence > acknowledgedCursor }
            .max(by: { $0.sequence < $1.sequence })

        while page.hasMore {
            try Task.checkCancellation()
            let cursor = page.nextCursor
            guard (requestedCursor.map { cursor > $0 } ?? (page.events.isEmpty == false)) else {
                throw FeedbackClientError(
                    kind: .invalidResponse,
                    context: FeedbackFailureContext(operation: .inbox)
                )
            }
            requestedCursor = cursor
            guard let nextPage = try await client.existingVisitorInbox(after: cursor) else {
                return nil
            }
            guard nextPage.nextCursor > cursor || nextPage.hasMore == false else {
                throw FeedbackClientError(
                    kind: .invalidResponse,
                    context: FeedbackFailureContext(operation: .inbox)
                )
            }
            acknowledgedCursor = max(acknowledgedCursor, nextPage.acknowledgedCursor)
            if latestReply?.sequence ?? 0 <= acknowledgedCursor {
                latestReply = nil
            }
            if let reply = nextPage.events
                .filter({ $0.type == .adminReply && $0.sequence > acknowledgedCursor })
                .max(by: { $0.sequence < $1.sequence }),
               reply.sequence > (latestReply?.sequence ?? acknowledgedCursor)
            {
                latestReply = reply
            }
            page = nextPage
        }

        guard let latestReply, latestReply.sequence > acknowledgedCursor else { return nil }
        try Task.checkCancellation()
        guard let detail = try await client.existingVisitorFeedback(id: latestReply.feedbackId) else {
            return nil
        }
        try Task.checkCancellation()
        return FeedbackReplyPresentation(event: latestReply, detail: detail)
    }
}
