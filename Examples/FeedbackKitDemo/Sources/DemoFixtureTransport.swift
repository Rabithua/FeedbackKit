import FeedbackKitCore
import Foundation

actor DemoFixtureTransport: FeedbackTransport {
    private let scenario: DemoScenario

    init(scenario: DemoScenario) {
        self.scenario = scenario
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        if scenario == .offline {
            throw URLError(.notConnectedToInternet)
        }

        let result = try route(request)
        return (
            result.data,
            try response(
                for: request,
                statusCode: result.statusCode,
                headers: result.headers
            )
        )
    }

    func upload(
        for request: URLRequest,
        data: Data
    ) async throws -> HTTPURLResponse {
        try await uploadResponse(for: request)
    }

    func upload(
        for request: URLRequest,
        fromFile fileURL: URL
    ) async throws -> HTTPURLResponse {
        try await uploadResponse(for: request)
    }

    private func uploadResponse(for request: URLRequest) async throws -> HTTPURLResponse {
        try Task.checkCancellation()
        if scenario == .offline {
            throw URLError(.notConnectedToInternet)
        }
        return try response(for: request, statusCode: 200)
    }

    private func route(
        _ request: URLRequest
    ) throws -> (statusCode: Int, headers: [String: String], data: Data) {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let requestHeaders = ["X-Request-ID": "fixture-\(UUID().uuidString)"]

        if path == "/v1/api/client/bootstrap" {
            switch scenario {
            case .rateLimited:
                return (
                    429,
                    requestHeaders.merging(["Retry-After": "10"]) { _, new in new },
                    DemoFixturePayloads.error(code: "rate_limited", message: "Try again later")
                )
            case .unavailable:
                return (
                    503,
                    requestHeaders,
                    DemoFixturePayloads.error(
                        code: "feedback_feature_unavailable",
                        message: "Temporarily unavailable"
                    )
                )
            default:
                return (
                    200,
                    requestHeaders,
                    DemoFixturePayloads.bootstrap(empty: scenario == .empty)
                )
            }
        }

        switch (method, path) {
        case ("GET", "/v1/api/client/activity"):
            return (200, requestHeaders, DemoFixturePayloads.activity(empty: scenario == .empty))
        case ("GET", "/v1/api/client/feedback"):
            return (200, requestHeaders, DemoFixturePayloads.ownedFeedbackPage(empty: scenario == .empty))
        case ("POST", "/v1/api/client/feedback"):
            if scenario == .validation {
                return (
                    422,
                    requestHeaders,
                    DemoFixturePayloads.error(code: "validation_failed", message: "Fixture validation failure")
                )
            }
            return (201, requestHeaders, DemoFixturePayloads.envelope(DemoFixturePayloads.ownedFeedback))
        case ("GET", let route) where route.hasPrefix("/v1/api/client/feedback/") && route.hasSuffix("/vote") == false:
            return (200, requestHeaders, DemoFixturePayloads.envelope(DemoFixturePayloads.feedbackDetail))
        case ("POST", let route) where route.hasSuffix("/messages"):
            return (
                201,
                requestHeaders,
                DemoFixturePayloads.envelope(
                    #"{"id":"77777777-7777-4777-8777-777777777777","actor":"visitor","body":"Fixture reply","createdAt":"2026-08-24T10:00:00.000Z"}"#
                )
            )
        case ("PUT", let route) where route.hasSuffix("/vote"):
            return (
                200,
                requestHeaders,
                DemoFixturePayloads.envelope(
                    #"{"feedbackId":"11111111-1111-4111-8111-111111111111","hasVoted":true,"voteCount":8}"#
                )
            )
        case ("DELETE", let route) where route.hasSuffix("/vote"):
            return (
                200,
                requestHeaders,
                DemoFixturePayloads.envelope(
                    #"{"feedbackId":"11111111-1111-4111-8111-111111111111","hasVoted":false,"voteCount":7}"#
                )
            )
        case ("GET", "/v1/api/public/releases"):
            let releases = scenario == .empty ? "[]" : "[\(DemoFixturePayloads.release)]"
            return (200, requestHeaders, DemoFixturePayloads.envelope(releases))
        case ("GET", let route) where route.hasPrefix("/v1/api/client/developer-posts/"):
            return (
                200,
                requestHeaders,
                DemoFixturePayloads.envelope(
                    #"{"id":"22222222-2222-4222-8222-222222222222","title":"Welcome to FeedbackKit","body":"This detail is also served by the fixture transport.","locale":"en","action":null,"publishedAt":"2026-08-22T10:00:00.000Z","pinnedAt":null,"updatedAt":"2026-08-22T10:00:00.000Z"}"#
                )
            )
        case ("POST", "/v1/api/client/uploads/presign"):
            return (200, requestHeaders, try DemoFixturePayloads.attachmentPresign(requestBody: request.httpBody))
        case ("POST", "/v1/api/client/uploads/finalize"):
            return (200, requestHeaders, try DemoFixturePayloads.attachmentFinalize(requestBody: request.httpBody))
        case ("GET", let route) where route.hasSuffix("/url"):
            return (
                200,
                requestHeaders,
                DemoFixturePayloads.envelope(
                    #"{"url":"https://uploads.feedkit.demo/attachment","expiresIn":900,"posterUrl":null}"#
                )
            )
        case ("POST", "/v1/api/client/diagnostics/presign"):
            return (
                200,
                requestHeaders,
                DemoFixturePayloads.envelope(
                    #"{"diagnosticArtifactId":"88888888-8888-4888-8888-888888888888","uploadUrl":"https://uploads.feedkit.demo/diagnostics","headers":{"Content-Type":"application/json","Content-Length":"262144"},"expiresIn":900}"#
                )
            )
        case ("POST", "/v1/api/client/diagnostics/finalize"):
            return (
                200,
                requestHeaders,
                DemoFixturePayloads.envelope(
                    #"{"id":"88888888-8888-4888-8888-888888888888"}"#
                )
            )
        case ("POST", "/v1/api/client/inbox/ack"):
            return (200, requestHeaders, DemoFixturePayloads.envelope(#"{"cursor":0}"#))
        case ("DELETE", "/v1/api/client/me"):
            return (200, requestHeaders, DemoFixturePayloads.envelope("null"))
        default:
            return (
                404,
                requestHeaders,
                DemoFixturePayloads.error(code: "not_found", message: "Unknown fixture route")
            )
        }
    }

    private func response(
        for request: URLRequest,
        statusCode: Int,
        headers: [String: String] = [:]
    ) throws -> HTTPURLResponse {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
              )
        else {
            throw URLError(.badServerResponse)
        }
        return response
    }
}
