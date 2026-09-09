import FeedbackKitCore
@testable import FeedbackKitUI
import Foundation
import Testing

private actor UpdateChecker: FeedbackAppUpdateChecking {
    let result: FeedbackAppUpdate?
    let fails: Bool
    private(set) var calls = 0

    init(result: FeedbackAppUpdate? = nil, fails: Bool = false) {
        self.result = result
        self.fails = fails
    }

    func availableUpdate() async throws -> FeedbackAppUpdate? {
        calls += 1
        if fails { throw URLError(.timedOut) }
        return result
    }
}

private actor DelayedUpdateChecker: FeedbackAppUpdateChecking {
    private var continuation: CheckedContinuation<FeedbackAppUpdate?, Never>?
    var started: Bool { continuation != nil }

    func availableUpdate() async throws -> FeedbackAppUpdate? {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(with update: FeedbackAppUpdate) {
        continuation?.resume(returning: update)
        continuation = nil
    }
}

@MainActor
struct FeedbackComposerEntryModelTests {
    private let update = FeedbackAppUpdate(
        currentVersion: "2.0.9",
        latestVersion: "2.0.10",
        url: URL(string: "https://apps.apple.com/app/id6755513897")!
    )

    @Test func completedBackgroundCheckIsReusedAcrossBugReports() async {
        let checker = UpdateChecker(result: update)
        let background = FeedbackAppUpdateModel(checker: checker)
        await background.prefetch()
        let first = FeedbackComposerEntryModel(kind: .bug, availableUpdate: background.update)
        #expect(first.phase == .update(update))
        first.continueFeedback()
        #expect(first.phase == .composing)
        await background.prefetch()
        let second = FeedbackComposerEntryModel(kind: .bug, availableUpdate: background.update)
        #expect(second.phase == .update(update))
        #expect(await checker.calls == 1)
    }

    @Test(arguments: [FeedbackKind.suggestion, .praise, .conversation])
    func otherKindsIgnoreAvailableUpdates(kind: FeedbackKind) {
        let model = FeedbackComposerEntryModel(kind: kind, availableUpdate: update)
        #expect(model.phase == .composing)
    }

    @Test func missingCheckerPreservesExistingBehavior() async {
        let background = FeedbackAppUpdateModel(checker: nil)
        await background.prefetch()
        #expect(FeedbackComposerEntryModel(kind: .bug, availableUpdate: background.update).phase == .composing)
    }

    @Test(arguments: [false, true])
    func noUpdateOrFailedCheckAllowsFeedback(fails: Bool) async {
        let background = FeedbackAppUpdateModel(checker: UpdateChecker(fails: fails))
        await background.prefetch()
        #expect(FeedbackComposerEntryModel(kind: .bug, availableUpdate: background.update).phase == .composing)
    }

    @Test func dismissedCenterDiscardsLateResults() async {
        let checker = DelayedUpdateChecker()
        let background = FeedbackAppUpdateModel(checker: checker)
        let task = Task { await background.prefetch() }
        while await !checker.started { await Task.yield() }
        task.cancel()
        await checker.finish(with: update)
        await task.value
        #expect(background.update == nil)
    }

    @Test func slowCheckNeverBlocksOrInterruptsAnOpenComposer() async {
        let checker = DelayedUpdateChecker()
        let background = FeedbackAppUpdateModel(checker: checker)
        let task = Task { await background.prefetch() }
        while await !checker.started { await Task.yield() }
        // Also covers a bug deep link opened before the prefetch finishes.
        let composer = FeedbackComposerEntryModel(kind: .bug, availableUpdate: background.update)
        #expect(composer.phase == .composing)
        await background.prefetch() // Must not start a duplicate in-flight check.
        await checker.finish(with: update)
        await task.value
        #expect(background.update == update)
        #expect(composer.phase == .composing)
        #expect(FeedbackComposerEntryModel(kind: .bug, availableUpdate: background.update).phase == .update(update))
    }

    @Test(arguments: ["en", "zh-Hans", "zh-Hant", "ja", "ko"])
    func reminderIsLocalizedWithBothVersions(locale: String) {
        let localization = FeedbackLocalization(locale: Locale(identifier: locale))
        for suffix in ["title", "message", "versions", "continue", "open", "failed", "checking", "continue.short", "open.short"] {
            let key = "feedbackkit.update.\(suffix)"
            #expect(localization.text(key) != key)
        }
        let versions = localization.formattedText("feedbackkit.update.versions", "2.0.9", "2.0.10")
        #expect(versions.contains("2.0.9"))
        #expect(versions.contains("2.0.10"))
    }
}
