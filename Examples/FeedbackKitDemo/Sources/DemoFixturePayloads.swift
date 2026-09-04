import Foundation

enum DemoFixturePayloads {
    static let campaignID = "99999999-9999-4999-8999-999999999999"
    static let product = #"{"slug":"feedbackkit-demo","name":"FeedbackKit Demo","defaultLocale":"en","defaultFeedbackVisibility":"private","iconUrl":null,"attachmentLimits":{"count":5,"imageBytes":10485760,"videoBytes":52428800},"diagnostics":{"enabled":true,"maxBytes":262144,"schemaVersions":[1]}}"#

    static let campaign = #"{"id":"99999999-9999-4999-8999-999999999999","title":"Shape FeedbackKit","description":"A two-page fixture campaign covering the packaged form controls.","elements":[{"kind":"notice","text":"Thanks for helping us choose what to build next."},{"kind":"question","key":"satisfaction","text":"How satisfied are you with FeedbackKit?","required":true,"answer":{"type":"integer","title":"Satisfaction","description":"Choose from 1 to 5.","minimum":1,"maximum":5}},{"kind":"question","key":"recommend","text":"Would you recommend FeedbackKit?","required":true,"answer":{"type":"boolean"}},{"kind":"pagebreak"},{"kind":"question","key":"features","text":"Which areas should we improve?","required":true,"answer":{"type":"array","description":"Choose one or two.","items":{"type":"string","enum":["Campaigns","Diagnostics","Conversations"],"maxLength":40},"minItems":1,"maxItems":2,"uniqueItems":true}},{"kind":"question","key":"note","text":"What should we know?","required":false,"answer":{"type":"string","maxLength":400}}],"publishedAt":"2026-09-05T00:00:00.000Z","updatedAt":"2026-09-05T00:00:00.000Z"}"#

    static let campaignResponse = #"{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","type":"survey","title":"Shape FeedbackKit","displayTitle":"Shape FeedbackKit","body":"How satisfied are you with FeedbackKit?\n4/5","status":"open","visibility":"private","publishedAt":null,"pinnedAt":null,"lastActivityAt":"2026-09-05T01:00:00.000Z","createdAt":"2026-09-05T01:00:00.000Z","updatedAt":"2026-09-05T01:00:00.000Z","diagnosticsIncluded":false}"#

    static let activityEntry = #"{"kind":"feedback","id":"11111111-1111-4111-8111-111111111111","pinnedAt":null,"activityAt":"2026-08-23T10:00:00.000Z","data":{"type":"suggestion","status":"open","title":"Fixture feedback","displayTitle":"Fixture feedback","body":"This public suggestion is served by the in-app fixture transport.","authorDisplayCode":"DEMO-01","voteCount":7,"hasVoted":false,"createdAt":"2026-08-23T10:00:00.000Z"}}"#

    static let developerPostEntry = #"{"kind":"developer_post","id":"22222222-2222-4222-8222-222222222222","pinnedAt":null,"activityAt":"2026-08-22T10:00:00.000Z","data":{"title":"Welcome to FeedbackKit","body":"Switch scenarios from the demo launcher to exercise failure and empty states.","locale":"en","action":null,"publishedAt":"2026-08-22T10:00:00.000Z","updatedAt":"2026-08-22T10:00:00.000Z"}}"#

    static let roadmapItem = #"{"id":"33333333-3333-4333-8333-333333333333","type":"feature","roadmapStage":"urgent","rank":1,"archivedAt":null,"title":"Structured developer telemetry","body":"Expose request outcomes without collecting feedback content.","locale":"en","createdAt":"2026-08-20T10:00:00.000Z","updatedAt":"2026-08-23T10:00:00.000Z"}"#

    static let release = #"{"id":"44444444-4444-4444-8444-444444444444","version":"0.2.0","releasedAt":"2026-08-24T10:00:00.000Z","body":"Fixed server configuration, integration verification, developer telemetry, and this runnable demo.","locale":"en","items":[]}"#

    static let ownedFeedback = #"{"id":"55555555-5555-4555-8555-555555555555","type":"bug","title":"Example private feedback","displayTitle":"Example private feedback","body":"This conversation belongs to the fixture visitor.","status":"open","visibility":"private","publishedAt":null,"pinnedAt":null,"lastActivityAt":"2026-08-23T12:00:00.000Z","createdAt":"2026-08-23T11:00:00.000Z","updatedAt":"2026-08-23T12:00:00.000Z","diagnosticsIncluded":false}"#

    static let feedbackDetail = #"{"id":"55555555-5555-4555-8555-555555555555","type":"bug","title":"Example private feedback","displayTitle":"Example private feedback","body":"This conversation belongs to the fixture visitor.","status":"open","visibility":"private","publishedAt":null,"pinnedAt":null,"lastActivityAt":"2026-08-23T12:00:00.000Z","createdAt":"2026-08-23T11:00:00.000Z","updatedAt":"2026-08-23T12:00:00.000Z","authorDisplayCode":"DEMO-01","isOwner":true,"voteCount":0,"hasVoted":false,"messages":[{"id":"66666666-6666-4666-8666-666666666666","actor":"admin","body":"Thanks — this fixture reply demonstrates the private conversation.","createdAt":"2026-08-23T12:00:00.000Z"}],"attachments":[],"diagnosticsIncluded":false}"#

    static func bootstrap(empty: Bool) -> Data {
        let activity = empty ? "[]" : "[\(activityEntry),\(developerPostEntry)]"
        let roadmap = empty ? "[]" : "[\(roadmapItem)]"
        let changelog = empty ? "[]" : "[\(release)]"
        return envelope(
            #"{"product":\#(product),"activity":{"entries":\#(activity),"nextCursor":null},"roadmap":\#(roadmap),"changelog":\#(changelog),"visitor":{"displayCode":"DEMO-01","lastReadCursor":0},"inbox":{"events":[],"nextCursor":0,"acknowledgedCursor":0,"unreadCount":0,"hasMore":false}}"#
        )
    }

    static func activity(empty: Bool) -> Data {
        envelope(
            empty
                ? #"{"entries":[],"nextCursor":null}"#
                : #"{"entries":[\#(activityEntry),\#(developerPostEntry)],"nextCursor":null}"#
        )
    }

    static func ownedFeedbackPage(empty: Bool) -> Data {
        envelope(
            empty
                ? #"{"feedback":[],"nextCursor":null}"#
                : #"{"feedback":[\#(ownedFeedback)],"nextCursor":null}"#
        )
    }

    static func envelope(_ dataJSON: String) -> Data {
        Data(#"{"code":"ok","message":"OK","data":\#(dataJSON)}"#.utf8)
    }

    static func error(code: String, message: String) -> Data {
        Data(#"{"code":"\#(code)","message":"\#(message)"}"#.utf8)
    }

    static func attachmentPresign(requestBody: Data?) throws -> Data {
        let files = try requestArray(requestBody, key: "files")
        let uploads = files.enumerated().map { index, file -> [String: Any] in
            let contentType = file["contentType"] as? String ?? "application/octet-stream"
            let size = file["size"] as? Int ?? 0
            return [
                "attachmentId": "demo-attachment-\(index + 1)",
                "uploadUrl": "https://uploads.feedkit.demo/attachment-\(index + 1)",
                "headers": [
                    "Content-Type": contentType,
                    "Content-Length": String(size),
                ],
                "expiresIn": 900,
            ]
        }
        return try jsonEnvelope(uploads)
    }

    static func attachmentFinalize(requestBody: Data?) throws -> Data {
        let attachments = try requestArray(requestBody, key: "attachments")
        let finalized = attachments.compactMap { attachment -> [String: Any]? in
            guard let id = attachment["id"] as? String else { return nil }
            return ["id": id]
        }
        return try jsonEnvelope(finalized)
    }

    private static func requestArray(
        _ data: Data?,
        key: String
    ) throws -> [[String: Any]] {
        guard let data,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = object[key] as? [[String: Any]]
        else {
            return []
        }
        return values
    }

    private static func jsonEnvelope(_ value: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: ["code": "ok", "message": "OK", "data": value],
            options: [.sortedKeys]
        )
    }
}
