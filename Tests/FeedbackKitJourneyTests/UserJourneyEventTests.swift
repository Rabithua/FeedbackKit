import FeedbackKitJourney
import Foundation
import Testing

struct UserJourneyEventTests {
    @Test func initStoresTheProvidedValues() {
        let occurredAt = Date(timeIntervalSince1970: 3_000)
        let kind = UserJourneySessionKind(rawValue: "checkout")

        let event = UserJourneyEvent(
            target: .kinds([kind]),
            name: "payment.confirmed",
            payload: ["amount": .int(42)],
            occurredAt: occurredAt
        )

        guard case .kinds(let kinds) = event.target else {
            Issue.record("Expected a kind-targeted event")
            return
        }
        #expect(kinds == [kind])
        #expect(event.name == "payment.confirmed")
        #expect(event.payload == ["amount": .int(42)])
        #expect(event.occurredAt == occurredAt)
    }

    @Test func payloadDefaultsToEmptyAndOccurredAtDefaultsToNow() {
        let before = Date.now

        let event = UserJourneyEvent(target: .all, name: "app.launched")

        let after = Date.now
        #expect(event.payload.isEmpty)
        #expect(event.occurredAt >= before)
        #expect(event.occurredAt <= after)
    }
}

struct UserJourneyPayloadValueTests {
    @Test func scalarsEncodeAsBareJSONValues() throws {
        #expect(String(decoding: try JSONEncoder().encode(UserJourneyPayloadValue.int(42)), as: UTF8.self) == "42")
        #expect(String(decoding: try JSONEncoder().encode(UserJourneyPayloadValue.bool(true)), as: UTF8.self) == "true")
        #expect(String(decoding: try JSONEncoder().encode(UserJourneyPayloadValue.string("a")), as: UTF8.self) == "\"a\"")
    }

    @Test func containersEncodeAsNaturalJSONStructures() throws {
        let payload: UserJourneyPayloadValue = .dictionary([
            "amount": .int(42),
            "tags": .array([.string("new"), .bool(false)]),
            "nested": .dictionary(["ratio": .double(0.5)]),
        ])

        let encoded = try JSONEncoder().encode(payload)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(object["amount"] as? Int == 42)
        let tags = try #require(object["tags"] as? [Any])
        #expect(tags[0] as? String == "new")
        #expect(tags[1] as? Bool == false)
        #expect((object["nested"] as? [String: Any])?["ratio"] as? Double == 0.5)
    }

    @Test func naturalJSONDecodesIntoTypedCases() throws {
        let json = #"{"count":1,"ratio":1.5,"label":"x","flags":[true,false],"nested":{"deep":2}}"#

        let decoded = try JSONDecoder().decode(UserJourneyPayloadValue.self, from: Data(json.utf8))

        #expect(decoded == .dictionary([
            "count": .int(1),
            "ratio": .double(1.5),
            "label": .string("x"),
            "flags": .array([.bool(true), .bool(false)]),
            "nested": .dictionary(["deep": .int(2)]),
        ]))
    }

    @Test func valuesAreEquatableByCaseAndContent() {
        #expect(UserJourneyPayloadValue.string("a") == .string("a"))
        #expect(UserJourneyPayloadValue.string("a") != .string("b"))
        #expect(UserJourneyPayloadValue.int(1) != .double(1))
        #expect(UserJourneyPayloadValue.bool(true) != .int(1))
        #expect(UserJourneyPayloadValue.array([.int(1), .int(2)]) == .array([.int(1), .int(2)]))
        #expect(UserJourneyPayloadValue.array([.int(1), .int(2)]) != .array([.int(2), .int(1)]))
        #expect(UserJourneyPayloadValue.dictionary(["a": .bool(true)]) == .dictionary(["a": .bool(true)]))
    }

    @Test func nestedPayloadRoundTripsThroughJSON() throws {
        let payload: UserJourneyPayloadValue = .dictionary([
            "name": .string("checkout"),
            "step": .int(3),
            "progress": .double(0.5),
            "completed": .bool(false),
            "tags": .array([.string("new"), .string("returning")]),
            "nested": .dictionary(["depth": .int(2)]),
        ])

        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(UserJourneyPayloadValue.self, from: encoded)

        #expect(decoded == payload)
    }
}
