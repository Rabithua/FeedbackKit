import Foundation

public struct FeedbackRedactor: Sendable {
    private static let sensitiveKeyFragments = [
        "authorization", "cookie", "password", "token", "apikey", "credential",
        "secret", "sessionid", "sessiontoken",
    ]

    public init() {}

    public func redact(_ value: String) -> String {
        if let json = redactJSON(value) {
            return String(json.prefix(8_192))
        }
        return String(redactText(value).prefix(8_192))
    }

    private func redactText(_ value: String) -> String {
        var result = value
        let replacements: [(String, String)] = [
            (#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer [REDACTED]"),
            (#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#, "[REDACTED_JWT]"),
            (#"\b(?:pk_|fspat_|sk_)[A-Za-z0-9_-]{8,}\b"#, "[REDACTED_TOKEN]"),
            (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[REDACTED_EMAIL]"),
            (#"(?<!\d)(?:\+?\d[\d ()-]{7,}\d)(?!\d)"#, "[REDACTED_PHONE]"),
            (#"([?&][^=\s&#]+)=([^&#\s]+)"#, "$1=[REDACTED]"),
            (
                #"(?i)([\"']?(?:authorization|cookie|password|token|api[-_ ]?key|credential|secret|client[-_ ]?secret|session(?:[-_ ]?(?:id|token))?)[\"']?\s*[:=]\s*)(?:\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|[^,;\s}\]]+)"#,
                "$1[REDACTED]"
            ),
        ]
        for (pattern, template) in replacements {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }

    public func redact(metadata: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: metadata.prefix(64).map { key, value in
            let sensitive = isSensitiveKey(key)
            return (String(key.prefix(128)), sensitive ? "[REDACTED]" : String(redact(value).prefix(2_048)))
        })
    }

    private func redactJSON(_ value: String) -> String? {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        let redacted = redactJSONValue(object)
        guard JSONSerialization.isValidJSONObject(redacted),
              let output = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys])
        else { return nil }
        return String(data: output, encoding: .utf8)
    }

    private func redactJSONValue(_ value: Any, key: String? = nil) -> Any {
        if let key, isSensitiveKey(key) { return "[REDACTED]" }
        if let object = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: object.map { key, value in
                (key, redactJSONValue(value, key: key))
            })
        }
        if let array = value as? [Any] {
            return array.map { redactJSONValue($0) }
        }
        if let string = value as? String { return redactText(string) }
        return value
    }

    private func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter(\.isLetter)
        return Self.sensitiveKeyFragments.contains { normalized.contains($0) }
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
