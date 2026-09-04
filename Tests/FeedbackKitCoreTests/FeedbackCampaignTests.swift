@testable import FeedbackKitCore
import FeedbackKitTestSupport
import Foundation
import Synchronization
import Testing

private actor CampaignCredential: FeedbackVisitorCredentialProviding {
    func credential(for productKey: String) async throws -> String { "visitor-credential" }
    func deleteCredential(for productKey: String) async throws {}
}

private actor CampaignDiagnosticProvider: FeedbackDiagnosticsProviding {
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

struct FeedbackCampaignTests {
    @Test("Campaign list and detail decode typed schemas into display-ready pages")
    func campaignReadsDecodeTypedFormPages() async throws {
        let requests = Mutex<[URLRequest]>([])
        let transport = FeedbackFixtureTransport { request in
            requests.withLock { $0.append(request) }
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer visitor-credential")

            let campaign = Self.campaignJSONObject
            let data: Any
            switch request.url?.path {
            case "/v1/api/client/campaigns": data = ["campaigns": [campaign]]
            case "/v1/api/client/campaigns/11111111-1111-4111-8111-111111111111": data = campaign
            default:
                Issue.record("Unexpected request: \(request.url?.path ?? "")")
                data = [:]
            }
            return (
                200,
                [:],
                try JSONSerialization.data(
                    withJSONObject: ["code": "ok", "message": "OK", "data": data]
                )
            )
        }
        let client = makeClient(transport: transport)

        let listed = try await client.campaigns()
        let campaign = try await client.campaign(id: "11111111-1111-4111-8111-111111111111")

        #expect(listed == [campaign])
        #expect(requests.withLock { $0.count } == 2)
        #expect(campaign.form.campaignID == campaign.id)
        #expect(campaign.form.title == "Help us plan Q3")
        #expect(campaign.form.pages.map(\.id) == [0, 1])
        #expect(campaign.form.pages.map(\.elements.count) == [3, 3])
        #expect(campaign.form.pages.flatMap(\.elements).map(\.id) == [0, 1, 2, 4, 5, 6])

        guard case let .question(satisfaction) = campaign.elements[1],
              case let .integer(scale) = satisfaction.answer else {
            Issue.record("Expected the satisfaction integer schema")
            return
        }
        #expect(satisfaction.id == "satisfaction")
        #expect(satisfaction.required)
        #expect(scale.minimum == 1)
        #expect(scale.maximum == 5)
        #expect(scale.multipleOf == 0.5)

        guard case let .question(features) = campaign.elements[4],
              case let .array(multipleChoice) = features.answer,
              case let .string(choice) = multipleChoice.items else {
            Issue.record("Expected the features multiple-choice schema")
            return
        }
        #expect(features.required == false)
        #expect(multipleChoice.maxItems == 3)
        #expect(multipleChoice.uniqueItems == true)
        #expect(choice.allowedValues == ["sync", "export", "share"])

        guard case let .question(recommend) = campaign.elements[5],
              case let .boolean(toggle) = recommend.answer else {
            Issue.record("Expected the recommendation boolean schema")
            return
        }
        #expect(toggle.title == "Recommendation")

        guard case let .question(budget) = campaign.elements[6],
              case let .number(amount) = budget.answer else {
            Issue.record("Expected the budget number schema")
            return
        }
        #expect(amount.minimum == 0.5)
        #expect(amount.maximum == 99.5)
    }

    @Test("Campaign form initializers preserve explicit empty page boundaries")
    func formInitializersPreservePageBoundaries() {
        let campaign = FeedbackCampaign(
            id: "campaign",
            title: "Title",
            description: "Description",
            elements: [
                .pageBreak,
                .notice(text: "Notice"),
                .pageBreak,
            ],
            publishedAt: nil,
            updatedAt: .now
        )

        #expect(campaign.form.pages.map(\.elements.count) == [0, 1, 0])
        #expect(campaign.form.pages[1].elements[0].id == 1)

        let customPage = FeedbackCampaignFormPage(
            id: 7,
            elements: [
                FeedbackCampaignFormElement(id: 9, content: .notice(text: "Preview")),
            ]
        )
        let customForm = FeedbackCampaignForm(
            campaignID: "preview",
            title: "Preview",
            description: "",
            pages: [customPage]
        )
        #expect(customForm.pages == [customPage])
    }

    @Test("Public schema initializers round-trip through the campaign wire format")
    func schemaInitializersRoundTrip() throws {
        let campaign = FeedbackCampaign(
            id: "campaign",
            title: "Title",
            description: "Description",
            elements: [
                .question(
                    FeedbackCampaignQuestion(
                        key: "choices",
                        text: "Choose",
                        required: false,
                        answer: .array(
                            FeedbackCampaignArrayAnswerSchema(
                                description: "Pick up to two",
                                items: .string(
                                    FeedbackCampaignStringAnswerSchema(
                                        allowedValues: ["one", "two"],
                                        maxLength: 20
                                    )
                                ),
                                minItems: 1,
                                maxItems: 2,
                                uniqueItems: true
                            )
                        )
                    )
                ),
            ],
            publishedAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let encoded = try FeedbackCoding.encoder().encode(campaign)
        let decoded = try FeedbackCoding.decoder().decode(FeedbackCampaign.self, from: encoded)

        #expect(decoded == campaign)
        guard case let .question(question) = decoded.elements[0],
              case let .array(schema) = question.answer else {
            Issue.record("Expected the initialized array schema")
            return
        }
        #expect(schema.description == "Pick up to two")
        #expect(question.answer.type == .array)
        #expect(question.answer.description == "Pick up to two")
    }

    @Test("Campaign response sends natural JSON values and decodes the survey result")
    func campaignResponseUsesServerWireFormat() async throws {
        let transport = FeedbackFixtureTransport { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/api/client/campaigns/11111111-1111-4111-8111-111111111111/responses")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer visitor-credential")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "campaign-response-1")

            let body = try #require(
                JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            )
            let answers = try #require(body["answers"] as? [String: Any])
            #expect((answers["satisfaction"] as? NSNumber)?.doubleValue == 4)
            #expect(answers["features"] as? [String] == ["sync", "share"])
            #expect(answers["recommend"] as? Bool == true)
            #expect(body["comment"] as? String == "Keep it up!")
            #expect(body["attachmentIds"] as? [String] == ["22222222-2222-4222-8222-222222222222"])
            #expect(body["diagnosticArtifactId"] == nil)
            let context = try #require(body["clientContext"] as? [String: Any])
            #expect(context["locale"] as? String == "zh-Hans-CN")

            let json = #"{"code":"ok","message":"OK","data":{"id":"33333333-3333-4333-8333-333333333333","type":"survey","title":"Help us plan Q3","displayTitle":"Help us plan Q3","body":"How satisfied are you?\n4/5","status":"open","visibility":"private","publishedAt":null,"pinnedAt":null,"lastActivityAt":"2026-09-04T10:00:00.000Z","createdAt":"2026-09-04T10:00:00.000Z","updatedAt":"2026-09-04T10:00:00.000Z","diagnosticsIncluded":false}}"#
            return (201, [:], Data(json.utf8))
        }
        let context = FeedbackClientContext(
            appVersion: "2.0.0",
            buildNumber: "42",
            osVersion: "26.0",
            deviceCategory: "phone",
            locale: "zh-Hans-CN"
        )
        let client = FeedbackClient(
            configuration: try FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor"
            ),
            transport: transport,
            credentialStore: CampaignCredential(),
            metadataProvider: FeedbackFixedMetadataProvider(context: context)
        )

        let response = try await client.submitCampaignResponse(
            campaignID: "11111111-1111-4111-8111-111111111111",
            answers: [
                "satisfaction": FeedbackCampaignAnswer(4),
                "features": FeedbackCampaignAnswer(["sync", "share"]),
                "recommend": FeedbackCampaignAnswer(true),
            ],
            comment: "Keep it up!",
            locale: Locale(identifier: "zh_CN"),
            attachmentIds: ["22222222-2222-4222-8222-222222222222"],
            includeDiagnostics: false,
            idempotencyKey: "campaign-response-1"
        )

        #expect(response.recordKind == .survey)
        #expect(response.type == .conversation)
        #expect(response.visibility == .private)
        #expect(response.diagnosticsIncluded == false)
    }

    @Test("Non-finite campaign answers fail before diagnostics or transport")
    func nonFiniteAnswersFailWithoutSideEffects() async throws {
        let diagnostics = CampaignDiagnosticProvider()
        let transport = FeedbackFixtureTransport { request in
            Issue.record("Unexpected request: \(request.url?.path ?? "")")
            return (500, [:], Data())
        }
        let context = FeedbackClientContext(
            appVersion: "2.0.0",
            buildNumber: "42",
            osVersion: "26.0",
            deviceCategory: "phone",
            locale: "en"
        )
        let client = FeedbackClient(
            configuration: try FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor"
            ),
            diagnostics: diagnostics,
            transport: transport,
            credentialStore: CampaignCredential(),
            metadataProvider: FeedbackFixedMetadataProvider(context: context)
        )

        do {
            _ = try await client.submitCampaignResponse(
                campaignID: "campaign",
                request: FeedbackCampaignResponseRequest(
                    answers: [
                        "scores": .array([
                            FeedbackCampaignScalarAnswer(Double.infinity),
                        ]),
                    ],
                    clientContext: context
                ),
                idempotencyKey: "non-finite-low-level"
            )
            Issue.record("Expected the low-level API to reject infinity")
        } catch let error as FeedbackClientError {
            #expect(error.kind == .validation)
            #expect(error.context.operation == .campaignResponse)
        } catch {
            Issue.record("Expected FeedbackClientError, got \(error)")
        }

        do {
            _ = try await client.submitCampaignResponse(
                campaignID: "campaign",
                answers: ["score": FeedbackCampaignAnswer(Double.nan)],
                locale: Locale(identifier: "en"),
                includeDiagnostics: true,
                idempotencyKey: "non-finite-high-level"
            )
            Issue.record("Expected the high-level API to reject NaN")
        } catch let error as FeedbackClientError {
            #expect(error.kind == .validation)
            #expect(error.context.operation == .campaignResponse)
        } catch {
            Issue.record("Expected FeedbackClientError, got \(error)")
        }

        #expect(await diagnostics.snapshotCount == 0)
        #expect(await transport.requests.isEmpty)
    }

    @Test("Campaign record kinds preserve the ordinary feedback enum")
    func campaignRecordKindsAreSourceCompatible() throws {
        #expect(FeedbackKind.allCases == [.bug, .suggestion, .praise, .conversation])
        #expect(FeedbackKind.submittableCases == FeedbackKind.allCases)
        #expect(FeedbackKind.allCases.allSatisfy { $0.isSubmittable })
        #expect(FeedbackRecordKind.survey.feedbackKind == nil)

        let data = Data(
            #"{"id":"33333333-3333-4333-8333-333333333333","type":"survey","title":"Campaign","displayTitle":"Campaign","body":"Answer","status":"open","visibility":"private","publishedAt":null,"pinnedAt":null,"lastActivityAt":"2026-09-04T10:00:00.000Z","createdAt":"2026-09-04T10:00:00.000Z","updatedAt":"2026-09-04T10:00:00.000Z","authorDisplayCode":"ABC-123","isOwner":true,"voteCount":0,"hasVoted":false,"messages":[],"attachments":[],"diagnosticsIncluded":false}"#.utf8
        )
        let detail = try FeedbackCoding.decoder().decode(FeedbackDetail.self, from: data)

        #expect(detail.recordKind == .survey)
        #expect(detail.type == .conversation)
        #expect(
            String(decoding: try FeedbackCoding.encoder().encode(detail), as: UTF8.self)
                .contains(#""type":"survey""#)
        )
    }

    @Test("Campaign diagnostics failures carry the campaign response operation")
    func campaignDiagnosticsFailureHasCampaignContext() async throws {
        let transport = FeedbackFixtureTransport { request in
            Issue.record("Unexpected request: \(request.url?.path ?? "")")
            return (500, [:], Data())
        }

        do {
            _ = try await makeClient(transport: transport).submitCampaignResponse(
                campaignID: "campaign",
                answers: [:],
                locale: Locale(identifier: "en"),
                includeDiagnostics: true,
                idempotencyKey: "campaign-diagnostics"
            )
            Issue.record("Expected diagnostics to be unavailable")
        } catch let error as FeedbackClientError {
            #expect(error.kind == .diagnosticsUnavailable)
            #expect(error.context.operation == .campaignResponse)
        }
        #expect(await transport.requests.isEmpty)
    }

    private func makeClient(transport: FeedbackFixtureTransport) -> FeedbackClient {
        FeedbackClient(
            configuration: try! FeedbackConfiguration(
                productKey: "pk_test",
                keychainService: "test.feedback.visitor"
            ),
            transport: transport,
            credentialStore: CampaignCredential()
        )
    }

    private static var campaignJSONObject: [String: Any] { [
        "id": "11111111-1111-4111-8111-111111111111",
        "title": "Help us plan Q3",
        "description": "Two quick questions.",
        "elements": [
            ["kind": "notice", "text": "Thanks for helping us."],
            [
                "kind": "question",
                "key": "satisfaction",
                "text": "How satisfied are you?",
                "required": true,
                "answer": [
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 5,
                    "multipleOf": 0.5,
                ],
            ],
            [
                "kind": "question",
                "key": "name",
                "text": "What should we call you?",
                "required": false,
                "answer": [
                    "type": "string",
                    "minLength": 1,
                    "maxLength": 80,
                    "pattern": "^[A-Za-z ]+$",
                ],
            ],
            ["kind": "pagebreak"],
            [
                "kind": "question",
                "key": "features",
                "text": "Which features do you use?",
                "required": false,
                "answer": [
                    "type": "array",
                    "items": [
                        "type": "string",
                        "enum": ["sync", "export", "share"],
                        "maxLength": 20,
                    ],
                    "maxItems": 3,
                    "uniqueItems": true,
                ],
            ],
            [
                "kind": "question",
                "key": "recommend",
                "text": "Would you recommend us?",
                "required": true,
                "answer": [
                    "type": "boolean",
                    "title": "Recommendation",
                ],
            ],
            [
                "kind": "question",
                "key": "budget",
                "text": "What is your monthly budget?",
                "required": false,
                "answer": [
                    "type": "number",
                    "minimum": 0.5,
                    "maximum": 99.5,
                ],
            ],
        ],
        "publishedAt": "2026-09-01T08:00:00.000Z",
        "updatedAt": "2026-09-02T08:00:00.000Z",
    ] }
}
