import Foundation

enum DemoScenario: String, CaseIterable, Identifiable {
    case healthy
    case empty
    case offline
    case validation
    case rateLimited
    case unavailable

    var id: Self { self }

    var title: String {
        switch self {
        case .healthy: "Healthy"
        case .empty: "Empty product"
        case .offline: "Offline"
        case .validation: "Submission validation"
        case .rateLimited: "Rate limited"
        case .unavailable: "Service unavailable"
        }
    }

    var explanation: String {
        switch self {
        case .healthy:
            "Preloaded activity, roadmap, changelog, feedback, uploads, votes, and diagnostics."
        case .empty:
            "A configured Product without published hub content."
        case .offline:
            "Every request fails with a not-connected-to-internet error."
        case .validation:
            "Loading succeeds, while feedback submission returns HTTP 422."
        case .rateLimited:
            "Bootstrap returns HTTP 429 with Retry-After and a request ID."
        case .unavailable:
            "Bootstrap returns the temporary service restriction response."
        }
    }
}
