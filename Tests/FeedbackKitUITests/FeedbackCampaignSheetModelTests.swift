@testable import FeedbackKitCore
@testable import FeedbackKitUI
import FeedbackKitTestSupport
import Foundation
import Synchronization
import Testing

private actor CampaignSheetCredential: FeedbackVisitorCredentialProviding {
    func credential(for productKey: String) async throws -> String { "campaign-sheet-visitor" }
    func deleteCredential(for productKey: String) async throws {}
}

private actor CampaignSheetDiagnostics: FeedbackDiagnosticsProviding {
    private(set) var snapshotCount = 0

    func makeDiagnosticSnapshot() async throws -> FeedbackDiagnosticSnapshot {
        snapshotCount += 1
        return FeedbackDiagnosticSnapshot(
            data: Data("{}".utf8),
            schemaVersion: 1,
            sha256: String(repeating: "a", count: 64)
        )
    }

    func recordNetwork(
        method: String,
        host: String,
        path: String,
        statusCode: Int?,
        duration: TimeInterval,
        errorCategory: String?
    ) async {}
}

@MainActor
struct FeedbackCampaignSheetModelTests {
    @Test("Pages validate locally before advancing and preserve typed answers")
    func pagesValidateBeforeAdvancing() throws {
        let model = FeedbackCampaignSheetModel(
            campaign: Self.campaign,
            client: makeClient(transport: FeedbackFixtureTransport { _ in
                Issue.record("No request expected")
                return (500, [:], Data())
            })
        )
        let locale = Locale(identifier: "en_US")
        let firstPage = try #require(model.currentPage)

        #expect(model.advance(locale: locale) == false)
        #expect(
            model.validationIssue(
                for: Self.ratingQuestion,
                on: firstPage,
                locale: locale
            ) == .required
        )

        let rating = try #require(model.questionState(for: Self.ratingQuestion))
        let ratingChoice = try #require(
            rating.scalarChoices?.first(where: { $0.value == .number(4) })
        )
        rating.selectScalarChoice(ratingChoice)

        let recommend = try #require(model.questionState(for: Self.recommendQuestion))
        let yes = try #require(
            recommend.scalarChoices?.first(where: { $0.value == .boolean(true) })
        )
        recommend.selectScalarChoice(yes)

        #expect(model.advance(locale: locale))
        #expect(model.currentPageIndex == 1)

        let features = try #require(model.questionState(for: Self.featuresQuestion))
        let choices = try #require(features.arrayChoices)
        features.toggleArrayChoice(choices[0])
        features.toggleArrayChoice(choices[1])
        #expect(features.isArrayChoiceDisabled(choices[2]))
        #expect(features.selectedArrayValues.count == 2)
    }

    @Test("Free arrays use stable row IDs and enforce uniqueness")
    func freeArrayRowsStayStableAndValidate() throws {
        let question = FeedbackCampaignQuestion(
            key: "ideas",
            text: "Ideas",
            answer: .array(
                FeedbackCampaignArrayAnswerSchema(
                    items: .string(
                        FeedbackCampaignStringAnswerSchema(minLength: 1, maxLength: 40)
                    ),
                    minItems: 2,
                    maxItems: 3,
                    uniqueItems: true
                )
            )
        )
        let state = FeedbackCampaignQuestionState(question: question)

        #expect(state.arrayChoices == nil)
        state.addArrayItem()
        state.addArrayItem()
        let ids = state.arrayItems.map(\.id)
        state.arrayItems[0].text = "Same"
        state.arrayItems[1].text = "Same"
        #expect(
            state.resolvedAnswer(locale: Locale(identifier: "en"))
                == .failure(.duplicateItems)
        )

        state.arrayItems[1].text = "Different"
        #expect(state.arrayItems.map(\.id) == ids)
        #expect(
            state.resolvedAnswer(locale: Locale(identifier: "en"))
                == .success(.array([.string("Same"), .string("Different")]))
        )

        state.removeArrayItem(id: ids[0])
        #expect(state.arrayItems.map(\.id) == [ids[1]])
        #expect(
            state.resolvedAnswer(locale: Locale(identifier: "en"))
                == .failure(.tooFewItems)
        )
    }

    @Test("Required arrays reject an empty answer even without minItems")
    func requiredArrayRejectsEmptyAnswer() {
        let question = FeedbackCampaignQuestion(
            key: "required-items",
            text: "Required items",
            answer: .array(
                FeedbackCampaignArrayAnswerSchema(
                    items: .string(FeedbackCampaignStringAnswerSchema(maxLength: 40)),
                    maxItems: 3
                )
            )
        )
        let state = FeedbackCampaignQuestionState(question: question)

        #expect(
            state.resolvedAnswer(locale: Locale(identifier: "en"))
                == .failure(.required)
        )
    }

    @Test("Choice arrays preserve repeated values when uniqueness is disabled")
    func repeatableChoiceArrayPreservesDuplicates() throws {
        let question = FeedbackCampaignQuestion(
            key: "snacks",
            text: "Snacks",
            answer: .array(
                FeedbackCampaignArrayAnswerSchema(
                    items: .string(
                        FeedbackCampaignStringAnswerSchema(
                            allowedValues: ["Apple", "Pear"],
                            maxLength: 20
                        )
                    ),
                    maxItems: 3,
                    uniqueItems: false
                )
            )
        )
        let state = FeedbackCampaignQuestionState(question: question)
        let apple = try #require(state.arrayChoices?.first)

        state.addArrayChoice(apple)
        state.addArrayChoice(apple)

        #expect(state.arrayChoiceCount(apple) == 2)
        #expect(
            state.resolvedAnswer(locale: Locale(identifier: "en"))
                == .success(.array([.string("Apple"), .string("Apple")]))
        )
    }

    @Test("Clearing an optional scalar removes the answer")
    func optionalScalarCanReturnToNil() {
        let question = FeedbackCampaignQuestion(
            key: "optional",
            text: "Optional",
            required: false,
            answer: .string(FeedbackCampaignStringAnswerSchema(maxLength: 40))
        )
        let state = FeedbackCampaignQuestionState(question: question)

        state.text = "Temporary"
        state.text = ""

        #expect(state.hasInput == false)
        #expect(
            state.resolvedAnswer(locale: Locale(identifier: "en"))
                == .success(nil)
        )
    }

    @Test("Numeric input respects locale, integer, range, and interval constraints")
    func numericValidationRespectsSchema() throws {
        let numberQuestion = FeedbackCampaignQuestion(
            key: "amount",
            text: "Amount",
            answer: .number(
                FeedbackCampaignNumberAnswerSchema(
                    minimum: 1,
                    maximum: 3,
                    multipleOf: 0.5
                )
            )
        )
        let numberState = FeedbackCampaignQuestionState(question: numberQuestion)
        let choice = try #require(
            numberState.scalarChoices?.first(where: { $0.value == .number(1.5) })
        )
        numberState.selectScalarChoice(choice)
        #expect(
            numberState.resolvedAnswer(locale: Locale(identifier: "de_DE"))
                == .success(.number(1.5))
        )

        let integerQuestion = FeedbackCampaignQuestion(
            key: "count",
            text: "Count",
            answer: .integer(
                FeedbackCampaignIntegerAnswerSchema(minimum: 1, maximum: 100)
            )
        )
        let integerState = FeedbackCampaignQuestionState(question: integerQuestion)
        #expect(integerState.scalarChoices == nil)
        integerState.text = "1.5"
        #expect(
            integerState.resolvedAnswer(locale: Locale(identifier: "en_US"))
                == .failure(.invalid)
        )
        integerState.text = "101"
        #expect(
            integerState.resolvedAnswer(locale: Locale(identifier: "en_US"))
                == .failure(.tooLarge)
        )

        integerState.text = "12not-a-number"
        #expect(
            integerState.resolvedAnswer(locale: Locale(identifier: "en_US"))
                == .failure(.invalid)
        )

        let hugeInteger = FeedbackCampaignQuestionState(
            question: FeedbackCampaignQuestion(
                key: "huge",
                text: "Huge",
                answer: .integer(
                    FeedbackCampaignIntegerAnswerSchema(
                        minimum: -Double.greatestFiniteMagnitude,
                        maximum: Double.greatestFiniteMagnitude
                    )
                )
            )
        )
        #expect(hugeInteger.scalarChoices == nil)

        let strictStep = FeedbackCampaignQuestionState(
            question: FeedbackCampaignQuestion(
                key: "step",
                text: "Step",
                answer: .number(FeedbackCampaignNumberAnswerSchema(multipleOf: 0.1))
            )
        )
        strictStep.text = "0.30000000001"
        #expect(
            strictStep.resolvedAnswer(locale: Locale(identifier: "en_US"))
                == .failure(.invalidStep)
        )
        strictStep.text = "0.3"
        #expect(
            strictStep.resolvedAnswer(locale: Locale(identifier: "en_US"))
                == .success(.number(0.3))
        )
    }

    @Test("Unchanged campaign retries reuse the idempotency key")
    func unchangedRetryReusesIdempotencyKey() async throws {
        let requests = Mutex<[URLRequest]>([])
        let count = Mutex(0)
        let responseEnvelope = Data(
            #"{"code":"ok","message":"OK","data":{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","type":"survey","title":"Campaign","displayTitle":"Campaign","body":"Summary\nFirst answer","status":"open","visibility":"private","publishedAt":null,"pinnedAt":null,"lastActivityAt":"2026-09-05T01:00:00.000Z","createdAt":"2026-09-05T01:00:00.000Z","updatedAt":"2026-09-05T01:00:00.000Z","diagnosticsIncluded":false}}"#.utf8
        )
        let transport = FeedbackFixtureTransport { request in
            requests.withLock { $0.append(request) }
            let attempt = count.withLock { value in
                value += 1
                return value
            }
            if attempt == 1 {
                return (
                    500,
                    [:],
                    Data(#"{"code":"server_error","message":"Retry"}"#.utf8)
                )
            }
            return (201, [:], responseEnvelope)
        }
        let model = FeedbackCampaignSheetModel(
            campaign: Self.singleQuestionCampaign,
            client: makeClient(transport: transport)
        )
        let state = try #require(model.questionState(for: Self.singleQuestion))
        state.text = "First answer"
        let localization = FeedbackLocalization(locale: Locale(identifier: "en"))

        #expect(
            await model.submit(
                locale: Locale(identifier: "en"),
                localization: localization
            ) == nil
        )
        let response = await model.submit(
            locale: Locale(identifier: "en"),
            localization: localization
        )

        #expect(response?.recordKind == .survey)
        let sent = requests.withLock { $0 }
        #expect(sent.count == 2)
        #expect(
            sent[0].value(forHTTPHeaderField: "Idempotency-Key")
                == sent[1].value(forHTTPHeaderField: "Idempotency-Key")
        )
        let body = try #require(
            JSONSerialization.jsonObject(with: sent[1].httpBody ?? Data()) as? [String: Any]
        )
        let answers = try #require(body["answers"] as? [String: Any])
        #expect(answers["summary"] as? String == "First answer")
        #expect(body["diagnosticArtifactId"] == nil)
    }

    @Test("Editing a failed campaign response rotates the idempotency key")
    func editingFailedResponseRotatesIdempotencyKey() async throws {
        let requests = Mutex<[URLRequest]>([])
        let transport = FeedbackFixtureTransport { request in
            requests.withLock { $0.append(request) }
            return (
                500,
                [:],
                Data(#"{"code":"server_error","message":"Retry"}"#.utf8)
            )
        }
        let model = FeedbackCampaignSheetModel(
            campaign: Self.singleQuestionCampaign,
            client: makeClient(transport: transport)
        )
        let state = try #require(model.questionState(for: Self.singleQuestion))
        let localization = FeedbackLocalization(locale: Locale(identifier: "en"))

        state.text = "First answer"
        _ = await model.submit(locale: Locale(identifier: "en"), localization: localization)
        state.text = "Edited answer"
        _ = await model.submit(locale: Locale(identifier: "en"), localization: localization)

        let sent = requests.withLock { $0 }
        #expect(sent.count == 2)
        #expect(
            sent[0].value(forHTTPHeaderField: "Idempotency-Key")
                != sent[1].value(forHTTPHeaderField: "Idempotency-Key")
        )
    }

    @Test("A response retry reuses its prepared diagnostic artifact")
    func diagnosticRetryReusesPreparedRequest() async throws {
        let diagnostics = CampaignSheetDiagnostics()
        let responseAttempts = Mutex(0)
        let diagnosticIDs = Mutex<[String?]>([])
        let responseEnvelope = Data(
            #"{"code":"ok","message":"OK","data":{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","type":"survey","title":"Campaign","displayTitle":"Campaign","body":"Summary\nAnswer","status":"open","visibility":"private","publishedAt":null,"pinnedAt":null,"lastActivityAt":"2026-09-05T01:00:00.000Z","createdAt":"2026-09-05T01:00:00.000Z","updatedAt":"2026-09-05T01:00:00.000Z","diagnosticsIncluded":true}}"#.utf8
        )
        let transport = FeedbackFixtureTransport { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/v1/api/client/bootstrap"):
                let json = #"{"code":"ok","message":"OK","data":{"product":{"slug":"app","name":"App","defaultLocale":"en","defaultFeedbackVisibility":"private","iconUrl":null,"attachmentLimits":{"count":5,"imageBytes":100,"videoBytes":200},"diagnostics":{"enabled":true,"maxBytes":262144,"schemaVersions":[1]}},"activity":{"entries":[],"nextCursor":null},"roadmap":[],"changelog":[],"visitor":{"displayCode":"ABC-123","lastReadCursor":0},"inbox":{"events":[],"nextCursor":0,"acknowledgedCursor":0,"unreadCount":0,"hasMore":false}}}"#
                return (200, [:], Data(json.utf8))
            case ("POST", "/v1/api/client/diagnostics/presign"):
                let json = #"{"code":"ok","message":"OK","data":{"diagnosticArtifactId":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","uploadUrl":"https://storage.example/private","headers":{"Content-Type":"application/json","Content-Length":"2","X-Amz-Checksum-Sha256":"test-base64-checksum"},"expiresIn":900}}"#
                return (200, [:], Data(json.utf8))
            case ("PUT", "/private"):
                return (200, [:], Data())
            case ("POST", "/v1/api/client/diagnostics/finalize"):
                return (200, [:], Data(#"{"code":"ok","message":"OK","data":{"id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd"}}"#.utf8))
            case ("POST", "/v1/api/client/campaigns/99999999-9999-4999-8999-999999999999/responses"):
                let object = try #require(
                    JSONSerialization.jsonObject(with: request.httpBody ?? Data())
                        as? [String: Any]
                )
                diagnosticIDs.withLock { $0.append(object["diagnosticArtifactId"] as? String) }
                let attempt = responseAttempts.withLock { value in
                    value += 1
                    return value
                }
                return attempt == 1
                    ? (500, [:], Data(#"{"code":"server_error","message":"Retry"}"#.utf8))
                    : (201, [:], responseEnvelope)
            default:
                Issue.record("Unexpected request: \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                return (500, [:], Data())
            }
        }
        let client = makeClient(transport: transport, diagnostics: diagnostics)
        let model = FeedbackCampaignSheetModel(campaign: Self.singleQuestionCampaign, client: client)
        await model.load(locale: Locale(identifier: "en"))
        model.includesDiagnostics = true
        let state = try #require(model.questionState(for: Self.singleQuestion))
        state.text = "Answer"
        let localization = FeedbackLocalization(locale: Locale(identifier: "en"))

        #expect(await model.submit(locale: Locale(identifier: "en"), localization: localization) == nil)
        #expect(await model.submit(locale: Locale(identifier: "en"), localization: localization) != nil)

        let paths = await transport.requests.compactMap(\.url?.path)
        #expect(paths.count { $0 == "/v1/api/client/diagnostics/presign" } == 1)
        #expect(paths.count { $0 == "/private" } == 1)
        #expect(paths.count { $0 == "/v1/api/client/diagnostics/finalize" } == 1)
        #expect(await diagnostics.snapshotCount == 1)
        let ids = diagnosticIDs.withLock { $0 }
        #expect(ids.count == 2)
        #expect(ids.allSatisfy { $0 == "dddddddd-dddd-4ddd-8ddd-dddddddddddd" })
    }

    @Test("Campaign read acknowledgement is attempted once and never blocks the form")
    func readFailureIsObservedButNonBlocking() async {
        let events = Mutex<[FeedbackClientEvent]>([])
        let transport = FeedbackFixtureTransport { request in
            #expect(request.url?.path.hasSuffix("/read") == true)
            return (500, [:], Data(#"{"code":"server_error","message":"Unavailable"}"#.utf8))
        }
        let client = makeClient(
            transport: transport,
            observer: FeedbackClientObserver { event in events.withLock { $0.append(event) } }
        )
        let model = FeedbackCampaignSheetModel(campaign: Self.singleQuestionCampaign, client: client)

        await model.markReadIfNeeded()
        await model.markReadIfNeeded()

        #expect(await transport.requests.count == 1)
        #expect(model.form != nil)
        #expect(model.loadError == nil)
        #expect(events.withLock { $0.last?.operation } == .campaignRead)
        #expect(events.withLock { $0.last?.outcome } == .failed)
    }

    @Test("An answered campaign and a missing campaign become terminal states")
    func campaignTerminalStates() async {
        let answered = FeedbackCampaign(
            id: Self.singleQuestionCampaign.id,
            title: Self.singleQuestionCampaign.title,
            description: "",
            elements: Self.singleQuestionCampaign.elements,
            publishedAt: .now,
            updatedAt: .now,
            respondedAt: .now
        )
        let noNetwork = FeedbackFixtureTransport { _ in
            Issue.record("An answered Campaign must not submit")
            return (500, [:], Data())
        }
        let answeredModel = FeedbackCampaignSheetModel(
            campaign: answered,
            client: makeClient(transport: noNetwork)
        )
        #expect(
            await answeredModel.submit(
                locale: Locale(identifier: "en"),
                localization: FeedbackLocalization(locale: Locale(identifier: "en"))
            ) == nil
        )

        let missingTransport = FeedbackFixtureTransport { _ in
            (404, [:], Data(#"{"code":"not_found","message":"Gone"}"#.utf8))
        }
        let missingModel = FeedbackCampaignSheetModel(
            campaignID: Self.singleQuestionCampaign.id,
            client: makeClient(transport: missingTransport)
        )
        await missingModel.load(locale: Locale(identifier: "en"))
        #expect(missingModel.isUnavailable)
        #expect(missingModel.loadError == nil)
    }

    @Test("Campaign diagnostics remain off until the visitor explicitly opts in")
    func diagnosticsStartOff() {
        let model = FeedbackCampaignSheetModel(
            campaign: Self.singleQuestionCampaign,
            client: makeClient(transport: FeedbackFixtureTransport { _ in
                Issue.record("No request expected")
                return (500, [:], Data())
            })
        )

        #expect(model.includesDiagnostics == false)
        #expect(model.diagnosticsAvailable == false)
    }

    @Test("Campaign ID presentation loads only the requested campaign")
    func campaignIDLoadsRequestedCampaign() async throws {
        let requests = Mutex<[URLRequest]>([])
        let campaignData = try FeedbackCoding.encoder().encode(Self.singleQuestionCampaign)
        let campaignJSON = try JSONSerialization.jsonObject(with: campaignData)
        let responseEnvelope = try JSONSerialization.data(
            withJSONObject: ["code": "ok", "message": "OK", "data": campaignJSON]
        )
        let transport = FeedbackFixtureTransport { request in
            requests.withLock { $0.append(request) }
            #expect(
                request.url?.path
                    == "/v1/api/client/campaigns/99999999-9999-4999-8999-999999999999"
            )
            return (
                200,
                [:],
                responseEnvelope
            )
        }
        let model = FeedbackCampaignSheetModel(
            campaignID: Self.singleQuestionCampaign.id,
            client: makeClient(transport: transport)
        )

        #expect(model.isLoading)
        await model.load(locale: Locale(identifier: "en"))

        #expect(model.isLoading == false)
        #expect(model.form?.campaignID == Self.singleQuestionCampaign.id)
        #expect(model.questionState(for: Self.singleQuestion) != nil)
        #expect(requests.withLock { $0.count } == 1)
    }

    private func makeClient(
        transport: FeedbackFixtureTransport,
        diagnostics: (any FeedbackDiagnosticsProviding)? = nil,
        observer: FeedbackClientObserver? = nil
    ) -> FeedbackClient {
        FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_campaign_sheet",
                keychainService: "test.campaign.sheet.visitor"
            ),
            diagnostics: diagnostics,
            observer: observer,
            transport: transport,
            credentialStore: CampaignSheetCredential(),
            metadataProvider: FeedbackFixedMetadataProvider(
                context: FeedbackClientContext(
                    appVersion: "2.1.0",
                    buildNumber: "1",
                    osVersion: "26.0",
                    deviceCategory: "phone",
                    locale: "en"
                )
            )
        )
    }

    private static let ratingQuestion = FeedbackCampaignQuestion(
        key: "rating",
        text: "Rating",
        answer: .integer(
            FeedbackCampaignIntegerAnswerSchema(minimum: 1, maximum: 5)
        )
    )

    private static let recommendQuestion = FeedbackCampaignQuestion(
        key: "recommend",
        text: "Recommend",
        answer: .boolean(FeedbackCampaignBooleanAnswerSchema())
    )

    private static let featuresQuestion = FeedbackCampaignQuestion(
        key: "features",
        text: "Features",
        answer: .array(
            FeedbackCampaignArrayAnswerSchema(
                items: .string(
                    FeedbackCampaignStringAnswerSchema(
                        allowedValues: ["Campaigns", "Diagnostics", "Conversations"],
                        maxLength: 40
                    )
                ),
                minItems: 1,
                maxItems: 2,
                uniqueItems: true
            )
        )
    )

    private static let campaign = FeedbackCampaign(
        id: "campaign",
        title: "Campaign",
        description: "Description",
        elements: [
            .question(ratingQuestion),
            .question(recommendQuestion),
            .pageBreak,
            .question(featuresQuestion),
        ],
        publishedAt: .now,
        updatedAt: .now
    )

    private static let singleQuestion = FeedbackCampaignQuestion(
        key: "summary",
        text: "Summary",
        answer: .string(FeedbackCampaignStringAnswerSchema(minLength: 1, maxLength: 200))
    )

    private static let singleQuestionCampaign = FeedbackCampaign(
        id: "99999999-9999-4999-8999-999999999999",
        title: "Campaign",
        description: "",
        elements: [.question(singleQuestion)],
        publishedAt: .now,
        updatedAt: .now
    )

}
