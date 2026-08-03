import Foundation

public struct FeedbackRedactor: Sendable {
    public init() {}

    public func redact(_ value: String) -> String {
        var result = value
        let replacements: [(String, String)] = [
            (#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer [REDACTED]"),
            (#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#, "[REDACTED_JWT]"),
            (#"\b(?:pk_|fspat_|sk_)[A-Za-z0-9_-]{8,}\b"#, "[REDACTED_TOKEN]"),
            (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[REDACTED_EMAIL]"),
            (#"(?<!\d)(?:\+?\d[\d ()-]{7,}\d)(?!\d)"#, "[REDACTED_PHONE]"),
            (#"([?&][^=\s&#]+)=([^&#\s]+)"#, "$1=[REDACTED]"),
            (#"(?i)\b(authorization|cookie|password|token|api[-_ ]?key|credential)\s*[:=]\s*[^,;\s]+"#, "$1=[REDACTED]"),
        ]
        for (pattern, template) in replacements {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return String(result.prefix(8_192))
    }

    public func redact(metadata: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: metadata.prefix(64).map { key, value in
            let lowered = key.lowercased()
            let sensitive = ["authorization", "cookie", "password", "token", "api_key", "apikey", "credential"].contains { lowered.contains($0) }
            return (String(key.prefix(128)), sensitive ? "[REDACTED]" : String(redact(value).prefix(2_048)))
        })
    }

    func event(_ event: FeedbackDiagnosticEvent) -> FeedbackDiagnosticEvent {
        FeedbackDiagnosticEvent(
            id: event.id,
            timestamp: event.timestamp,
            level: event.level,
            category: String(redact(event.category).prefix(128)),
            message: redact(event.message),
            metadata: redact(metadata: event.metadata),
            file: event.file.map { URL(fileURLWithPath: $0).lastPathComponent },
            function: event.function.map { String(redact($0).prefix(256)) },
            line: event.line
        )
    }

    func breadcrumb(_ breadcrumb: FeedbackBreadcrumb) -> FeedbackBreadcrumb {
        FeedbackBreadcrumb(
            id: breadcrumb.id,
            timestamp: breadcrumb.timestamp,
            kind: breadcrumb.kind,
            name: String(redact(breadcrumb.name).prefix(256)),
            metadata: redact(metadata: breadcrumb.metadata)
        )
    }
}
