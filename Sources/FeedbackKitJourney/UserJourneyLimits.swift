import Foundation

/// Client-side mirrors of the server's journey validation bounds; events that
/// violate them are dropped at record time instead of failing at submit time.
public enum UserJourneyLimits {
    /// The server rejects sessions spanning more than seven days.
    public static let maxSessionDuration: TimeInterval = 7 * 24 * 60 * 60
    public static let maxEventsPerSession = 500
    public static let maxPayloadBytes = 4096
    public static let maxPayloadDepth = 4
    public static let maxKeysPerObject = 40
    public static let maxKeyLength = 60
    public static let maxStringLength = 500
    public static let maxEventNameLength = 120
    public static let maxKindLength = 80
}

enum UserJourneyTaxonomy {
    static let defaultKindKey = "__default__"

    /// Session kinds stay a controlled vocabulary: the server normalises them
    /// into its kind table and hands each one a kind id.
    static func isValidKey(_ value: String, maxLength: Int) -> Bool {
        guard value.isEmpty == false, value.count <= maxLength else { return false }
        return value.wholeMatch(of: #/[a-z0-9]+(?:[._-][a-z0-9]+)*/#) != nil
    }

    /// Event names are free-form labels, stored verbatim in a column of their
    /// own. They are held only to the server's trim-and-length rule, so a name
    /// can be neither blank nor wider than the column.
    static func isValidEventName(_ value: String, maxLength: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false && trimmed.count <= maxLength
    }
}

enum UserJourneyEventValidation {
    static func isSubmittable(_ event: UserJourneyEvent) -> Bool {
        guard UserJourneyTaxonomy.isValidEventName(
            event.name,
            maxLength: UserJourneyLimits.maxEventNameLength
        ) else { return false }
        let root = UserJourneyPayloadValue.dictionary(event.payload)
        guard depth(of: root) <= UserJourneyLimits.maxPayloadDepth,
              structureIsWithinBounds(root),
              let encoded = try? JSONEncoder().encode(root),
              encoded.count <= UserJourneyLimits.maxPayloadBytes
        else { return false }
        return true
    }

    private static func depth(of value: UserJourneyPayloadValue) -> Int {
        switch value {
        case .string, .int, .double, .bool:
            return 0
        case .array(let items):
            return 1 + (items.map(depth(of:)).max() ?? 0)
        case .dictionary(let entries):
            return 1 + (entries.values.map(depth(of:)).max() ?? 0)
        }
    }

    private static func structureIsWithinBounds(_ value: UserJourneyPayloadValue) -> Bool {
        switch value {
        case .string(let string):
            return string.count <= UserJourneyLimits.maxStringLength
        case .int, .double, .bool:
            return true
        case .array(let items):
            return items.count <= UserJourneyLimits.maxKeysPerObject
                && items.allSatisfy(structureIsWithinBounds)
        case .dictionary(let entries):
            guard entries.count <= UserJourneyLimits.maxKeysPerObject else { return false }
            return entries.allSatisfy { key, item in
                key.isEmpty == false
                    && key.count <= UserJourneyLimits.maxKeyLength
                    && structureIsWithinBounds(item)
            }
        }
    }
}
