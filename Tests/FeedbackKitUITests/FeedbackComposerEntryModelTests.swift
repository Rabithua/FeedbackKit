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

    @Test func bugReportPromptsBeforeComposingAndContinuesWithoutRechecking() async {
        let checker = UpdateChecker(result: update)
        let model = FeedbackComposerEntryModel(kind: .bug, updateChecker: checker)
        #expect(model.phase == .checking)
        await model.checkForUpdate()
        #expect(model.phase == .update(update))
        model.continueFeedback()
        await model.checkForUpdate()
        #expect(model.phase == .composing)
        #expect(await checker.calls == 1)
    }

    @Test(arguments: [FeedbackKind.suggestion, .praise, .conversation])
    func otherKindsNeverCheckForUpdates(kind: FeedbackKind) async {
        let checker = UpdateChecker(result: update)
        let model = FeedbackComposerEntryModel(kind: kind, updateChecker: checker)
        await model.checkForUpdate()
        #expect(model.phase == .composing)
        #expect(await checker.calls == 0)
    }

    @Test func missingCheckerPreservesExistingBehavior() async {
        let model = FeedbackComposerEntryModel(kind: .bug, updateChecker: nil)
        await model.checkForUpdate()
        #expect(model.phase == .composing)
    }

    @Test(arguments: [false, true])
    func noUpdateOrFailedCheckAllowsFeedback(fails: Bool) async {
        let model = FeedbackComposerEntryModel(kind: .bug, updateChecker: UpdateChecker(fails: fails))
        await model.checkForUpdate()
        #expect(model.phase == .composing)
    }

    @Test func dismissedCheckCannotPresentALateUpdate() async {
        let checker = DelayedUpdateChecker()
        let model = FeedbackComposerEntryModel(kind: .bug, updateChecker: checker)
        let task = Task { await model.checkForUpdate() }
        while await !checker.started { await Task.yield() }
        task.cancel()
        await checker.finish(with: update)
        await task.value
        #expect(model.phase == .checking)
    }

    @Test func skippingASlowCheckCannotInterruptTheComposerLater() async {
        let checker = DelayedUpdateChecker()
        let model = FeedbackComposerEntryModel(kind: .bug, updateChecker: checker)
        let task = Task { await model.checkForUpdate() }
        while await !checker.started { await Task.yield() }
        model.continueFeedback()
        await checker.finish(with: update)
        await task.value
        #expect(model.phase == .composing)
    }

    @Test func aNewBugReportChecksAgainAfterAPreviousReminderWasDismissed() async {
        let checker = UpdateChecker(result: update)
        let first = FeedbackComposerEntryModel(kind: .bug, updateChecker: checker)
        await first.checkForUpdate()
        first.continueFeedback()
        let second = FeedbackComposerEntryModel(kind: .bug, updateChecker: checker)
        await second.checkForUpdate()
        #expect(second.phase == .update(update))
        #expect(await checker.calls == 2)
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
