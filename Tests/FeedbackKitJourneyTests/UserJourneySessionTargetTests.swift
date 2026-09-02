@testable import FeedbackKitJourney
import Foundation
import Testing

private extension UserJourneySessionKind {
    static let checkout = UserJourneySessionKind(rawValue: "checkout")
    static let onboarding = UserJourneySessionKind(rawValue: "onboarding")
}

struct UserJourneySessionTargetTests {
    private let checkoutChat = UserJourneySession(kind: .checkout, objectID: "chat-1138")
    private let onboardingChat = UserJourneySession(kind: .onboarding, objectID: "chat-1138")
    private let checkoutOther = UserJourneySession(kind: .checkout, objectID: "chat-9999")
    private let untraced = UserJourneySession(kind: .checkout)

    @Test func allMatchesEverySession() {
        #expect(UserJourneySessionTarget.all.matches(checkoutChat))
        #expect(UserJourneySessionTarget.all.matches(untraced))
    }

    @Test func kindsMatchByKind() {
        let target = UserJourneySessionTarget.kinds(.checkout)

        #expect(target.matches(checkoutChat))
        #expect(target.matches(onboardingChat) == false)
        #expect(UserJourneySessionTarget.kinds(.checkout, .onboarding).matches(onboardingChat))
        // A collected set stays spellable, and an empty list matches nothing.
        #expect(UserJourneySessionTarget.kinds([.checkout, .onboarding]).matches(checkoutChat))
        #expect(UserJourneySessionTarget.kinds().matches(checkoutChat) == false)
    }

    @Test func objectIDsMatchByTracedObject() {
        #expect(UserJourneySessionTarget.objectIDs("chat-1138").matches(checkoutChat))
        #expect(UserJourneySessionTarget.objectIDs("chat-1138", "chat-9999").matches(checkoutOther))
        #expect(UserJourneySessionTarget.objectIDs("chat-9999").matches(checkoutChat) == false)
        #expect(UserJourneySessionTarget.objectIDs().matches(checkoutChat) == false)
        // A collected list stays spellable.
        #expect(UserJourneySessionTarget.objectIDs(["chat-1138"]).matches(checkoutChat))
    }

    /// Identifiers are compared as digests, never as the raw strings.
    @Test func objectTargetsCompareDigests() throws {
        let chat = try #require(UserJourneyObjectHash("chat-1138"))

        #expect(checkoutChat.objectHash == chat)
        guard case .objects(let hashes) = UserJourneySessionTarget.objectID("chat-1138").criterion
        else {
            Issue.record("Expected an object criterion")
            return
        }
        #expect(hashes == [chat])
    }

    @Test func objectIDMatchesTheSessionsTracingIt() {
        let target = UserJourneySessionTarget.objectID("chat-1138")

        #expect(target.matches(checkoutChat))
        #expect(target.matches(onboardingChat))
        #expect(target.matches(checkoutOther) == false)
        #expect(target.matches(untraced) == false)
    }

    @Test func aBlankObjectIdentifierTargetsNothingRatherThanEverything() {
        #expect(UserJourneySessionTarget.objectID("  ").matches(checkoutChat) == false)
        #expect(UserJourneySessionTarget.objectID("  ").matches(untraced) == false)
    }

    @Test func criteriaAggregate() {
        let both = UserJourneySessionTarget.allOf(.kinds(.checkout), .objectID("chat-1138"))
        #expect(both.matches(checkoutChat))
        #expect(both.matches(onboardingChat) == false)
        #expect(both.matches(checkoutOther) == false)

        let either = UserJourneySessionTarget.anyOf(.kinds(.onboarding), .objectID("chat-9999"))
        #expect(either.matches(onboardingChat))
        #expect(either.matches(checkoutOther))
        #expect(either.matches(untraced) == false)

        // Nesting composes: onboarding, or a checkout tracing that one chat.
        let nested = UserJourneySessionTarget.anyOf(
            .kinds(.onboarding),
            .allOf(.kinds(.checkout), .objectID("chat-1138"))
        )
        #expect(nested.matches(onboardingChat))
        #expect(nested.matches(checkoutChat))
        #expect(nested.matches(checkoutOther) == false)
    }

    @Test func emptyAggregatesTakeTheNeutralAnswer() {
        #expect(UserJourneySessionTarget.anyOf().matches(checkoutChat) == false)
        #expect(UserJourneySessionTarget.allOf().matches(checkoutChat))
    }

    /// A collected list stays spellable, and lands in the same case as the
    /// variadic form.
    @Test func aggregatesAcceptACollectedListToo() {
        let criteria: [UserJourneySessionTarget] = [.kinds(.checkout), .objectID("chat-1138")]

        #expect(UserJourneySessionTarget.allOf(criteria).matches(checkoutChat))
        #expect(UserJourneySessionTarget.allOf(criteria).matches(checkoutOther) == false)
        guard case .allOf(let collected) = UserJourneySessionTarget.allOf(criteria).criterion,
              case .allOf(let spread) = UserJourneySessionTarget.allOf(
                  .kinds(.checkout),
                  .objectID("chat-1138")
              ).criterion
        else {
            Issue.record("Both spellings should build the aggregate case")
            return
        }
        #expect(collected.count == spread.count)
    }

    @Test func aPredicateCanRouteOnAnythingIncludingRecordedState() {
        let target = UserJourneySessionTarget.matching { $0.events.count < 2 }
        let session = UserJourneySession(kind: .checkout)

        session.append(UserJourneyEvent(target: target, name: "step.one"))
        session.append(UserJourneyEvent(target: target, name: "step.two"))
        session.append(UserJourneyEvent(target: target, name: "step.three"))

        #expect(session.events.map(\.name) == ["step.one", "step.two"])
    }
}
