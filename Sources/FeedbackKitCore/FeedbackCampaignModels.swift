import Foundation

/// A campaign that is currently collecting responses for the configured Product.
public struct FeedbackCampaign: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let elements: [FeedbackCampaignElement]
    public let publishedAt: Date?
    public let updatedAt: Date
    /// When this visitor first answered, or nil if they have not. Always nil on
    /// the Product-keyed public routes, which have no visitor to speak for, and
    /// on servers older than the field.
    public let respondedAt: Date?

    public init(
        id: String,
        title: String,
        description: String,
        elements: [FeedbackCampaignElement],
        publishedAt: Date?,
        updatedAt: Date,
        respondedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.elements = elements
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.respondedAt = respondedAt
    }

    /// Whether this visitor has already answered — the reason to stop offering
    /// the campaign rather than collect a second response.
    public var hasResponded: Bool { respondedAt != nil }

    /// The campaign converted into stable, display-ready pages.
    public var form: FeedbackCampaignForm {
        FeedbackCampaignForm(campaign: self)
    }
}

public struct FeedbackCampaignList: Codable, Hashable, Sendable {
    public let campaigns: [FeedbackCampaign]

    public init(campaigns: [FeedbackCampaign]) {
        self.campaigns = campaigns
    }
}

/// An element in the flat campaign wire format.
public enum FeedbackCampaignElement: Codable, Hashable, Sendable {
    case notice(text: String)
    case question(FeedbackCampaignQuestion)
    case pageBreak

    private enum Kind: String, Codable {
        case notice
        case question
        case pageBreak = "pagebreak"
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case key
        case required
        case answer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .notice:
            self = .notice(text: try container.decode(String.self, forKey: .text))
        case .question:
            self = .question(
                FeedbackCampaignQuestion(
                    key: try container.decode(String.self, forKey: .key),
                    text: try container.decode(String.self, forKey: .text),
                    required: try container.decode(Bool.self, forKey: .required),
                    answer: try container.decode(FeedbackCampaignAnswerSchema.self, forKey: .answer)
                )
            )
        case .pageBreak:
            self = .pageBreak
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .notice(text):
            try container.encode(Kind.notice, forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .question(question):
            try container.encode(Kind.question, forKey: .kind)
            try container.encode(question.key, forKey: .key)
            try container.encode(question.text, forKey: .text)
            try container.encode(question.required, forKey: .required)
            try container.encode(question.answer, forKey: .answer)
        case .pageBreak:
            try container.encode(Kind.pageBreak, forKey: .kind)
        }
    }
}

public struct FeedbackCampaignQuestion: Codable, Hashable, Identifiable, Sendable {
    public var id: String { key }

    public let key: String
    public let text: String
    public let required: Bool
    public let answer: FeedbackCampaignAnswerSchema

    public init(
        key: String,
        text: String,
        required: Bool = true,
        answer: FeedbackCampaignAnswerSchema
    ) {
        self.key = key
        self.text = text
        self.required = required
        self.answer = answer
    }
}

// MARK: - Display-ready form pages

/// A campaign split into pages with page-break markers removed.
public struct FeedbackCampaignForm: Hashable, Sendable {
    public let campaignID: String
    public let title: String
    public let description: String
    public let pages: [FeedbackCampaignFormPage]

    public init(
        campaignID: String,
        title: String,
        description: String,
        pages: [FeedbackCampaignFormPage]
    ) {
        self.campaignID = campaignID
        self.title = title
        self.description = description
        self.pages = pages
    }

    /// Creates display pages while preserving every page boundary from the campaign.
    public init(campaign: FeedbackCampaign) {
        var pages: [FeedbackCampaignFormPage] = []
        var pageElements: [FeedbackCampaignFormElement] = []
        var pageID = 0

        for (position, element) in campaign.elements.enumerated() {
            switch element {
            case let .notice(text):
                pageElements.append(
                    FeedbackCampaignFormElement(id: position, content: .notice(text: text))
                )
            case let .question(question):
                pageElements.append(
                    FeedbackCampaignFormElement(id: position, content: .question(question))
                )
            case .pageBreak:
                pages.append(FeedbackCampaignFormPage(id: pageID, elements: pageElements))
                pageID += 1
                pageElements = []
            }
        }
        pages.append(FeedbackCampaignFormPage(id: pageID, elements: pageElements))

        self.init(
            campaignID: campaign.id,
            title: campaign.title,
            description: campaign.description,
            pages: pages
        )
    }
}

public struct FeedbackCampaignFormPage: Hashable, Identifiable, Sendable {
    public let id: Int
    public let elements: [FeedbackCampaignFormElement]

    public init(id: Int, elements: [FeedbackCampaignFormElement]) {
        self.id = id
        self.elements = elements
    }
}

public struct FeedbackCampaignFormElement: Hashable, Identifiable, Sendable {
    public enum Content: Hashable, Sendable {
        case notice(text: String)
        case question(FeedbackCampaignQuestion)
    }

    /// The element's position in the campaign, stable across the derived pages.
    public let id: Int
    public let content: Content

    public init(id: Int, content: Content) {
        self.id = id
        self.content = content
    }
}

// MARK: - Typed answer schemas

public enum FeedbackCampaignAnswerType: String, Codable, Hashable, Sendable {
    case string
    case number
    case integer
    case boolean
    case array
}

/// The bounded JSON-Schema subset accepted by FeedbackServer, represented without raw JSON.
public enum FeedbackCampaignAnswerSchema: Codable, Hashable, Sendable {
    case string(FeedbackCampaignStringAnswerSchema)
    case number(FeedbackCampaignNumberAnswerSchema)
    case integer(FeedbackCampaignIntegerAnswerSchema)
    case boolean(FeedbackCampaignBooleanAnswerSchema)
    case array(FeedbackCampaignArrayAnswerSchema)

    public var type: FeedbackCampaignAnswerType {
        switch self {
        case .string: .string
        case .number: .number
        case .integer: .integer
        case .boolean: .boolean
        case .array: .array
        }
    }

    public var title: String? {
        switch self {
        case let .string(schema): schema.title
        case let .number(schema): schema.title
        case let .integer(schema): schema.title
        case let .boolean(schema): schema.title
        case let .array(schema): schema.title
        }
    }

    public var description: String? {
        switch self {
        case let .string(schema): schema.description
        case let .number(schema): schema.description
        case let .integer(schema): schema.description
        case let .boolean(schema): schema.description
        case let .array(schema): schema.description
        }
    }

    private enum CodingKeys: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(FeedbackCampaignAnswerType.self, forKey: .type) {
        case .string: self = .string(try FeedbackCampaignStringAnswerSchema(from: decoder))
        case .number: self = .number(try FeedbackCampaignNumberAnswerSchema(from: decoder))
        case .integer: self = .integer(try FeedbackCampaignIntegerAnswerSchema(from: decoder))
        case .boolean: self = .boolean(try FeedbackCampaignBooleanAnswerSchema(from: decoder))
        case .array: self = .array(try FeedbackCampaignArrayAnswerSchema(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .string(schema): try schema.encode(to: encoder)
        case let .number(schema): try schema.encode(to: encoder)
        case let .integer(schema): try schema.encode(to: encoder)
        case let .boolean(schema): try schema.encode(to: encoder)
        case let .array(schema): try schema.encode(to: encoder)
        }
    }
}

public enum FeedbackCampaignScalarAnswerSchema: Codable, Hashable, Sendable {
    case string(FeedbackCampaignStringAnswerSchema)
    case number(FeedbackCampaignNumberAnswerSchema)
    case integer(FeedbackCampaignIntegerAnswerSchema)
    case boolean(FeedbackCampaignBooleanAnswerSchema)

    private enum CodingKeys: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(FeedbackCampaignAnswerType.self, forKey: .type) {
        case .string: self = .string(try FeedbackCampaignStringAnswerSchema(from: decoder))
        case .number: self = .number(try FeedbackCampaignNumberAnswerSchema(from: decoder))
        case .integer: self = .integer(try FeedbackCampaignIntegerAnswerSchema(from: decoder))
        case .boolean: self = .boolean(try FeedbackCampaignBooleanAnswerSchema(from: decoder))
        case .array:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Campaign array items must use a scalar answer schema."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .string(schema): try schema.encode(to: encoder)
        case let .number(schema): try schema.encode(to: encoder)
        case let .integer(schema): try schema.encode(to: encoder)
        case let .boolean(schema): try schema.encode(to: encoder)
        }
    }
}

public struct FeedbackCampaignStringAnswerSchema: Codable, Hashable, Sendable {
    public let type: FeedbackCampaignAnswerType
    public let title: String?
    public let description: String?
    public let allowedValues: [String]?
    public let constant: String?
    public let minLength: Int?
    public let maxLength: Int
    /// A legacy constraint that can still appear on campaigns published by older servers.
    /// New FeedbackServer campaign definitions no longer accept regular-expression patterns.
    public let pattern: String?

    public init(
        title: String? = nil,
        description: String? = nil,
        allowedValues: [String]? = nil,
        constant: String? = nil,
        minLength: Int? = nil,
        maxLength: Int
    ) {
        type = .string
        self.title = title
        self.description = description
        self.allowedValues = allowedValues
        self.constant = constant
        self.minLength = minLength
        self.maxLength = maxLength
        pattern = nil
    }

    @available(
        *,
        deprecated,
        message: "FeedbackServer no longer accepts pattern constraints on new campaigns."
    )
    public init(
        title: String? = nil,
        description: String? = nil,
        allowedValues: [String]? = nil,
        constant: String? = nil,
        minLength: Int? = nil,
        maxLength: Int,
        pattern: String? = nil
    ) {
        type = .string
        self.title = title
        self.description = description
        self.allowedValues = allowedValues
        self.constant = constant
        self.minLength = minLength
        self.maxLength = maxLength
        self.pattern = pattern
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case description
        case allowedValues = "enum"
        case constant = "const"
        case minLength
        case maxLength
        case pattern
    }
}

public struct FeedbackCampaignNumberAnswerSchema: Codable, Hashable, Sendable {
    public let type: FeedbackCampaignAnswerType
    public let title: String?
    public let description: String?
    public let allowedValues: [Double]?
    public let constant: Double?
    public let minimum: Double?
    public let maximum: Double?
    public let multipleOf: Double?

    public init(
        title: String? = nil,
        description: String? = nil,
        allowedValues: [Double]? = nil,
        constant: Double? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        multipleOf: Double? = nil
    ) {
        type = .number
        self.title = title
        self.description = description
        self.allowedValues = allowedValues
        self.constant = constant
        self.minimum = minimum
        self.maximum = maximum
        self.multipleOf = multipleOf
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case description
        case allowedValues = "enum"
        case constant = "const"
        case minimum
        case maximum
        case multipleOf
    }
}

public struct FeedbackCampaignIntegerAnswerSchema: Codable, Hashable, Sendable {
    public let type: FeedbackCampaignAnswerType
    public let title: String?
    public let description: String?
    public let allowedValues: [Double]?
    public let constant: Double?
    public let minimum: Double?
    public let maximum: Double?
    public let multipleOf: Double?

    public init(
        title: String? = nil,
        description: String? = nil,
        allowedValues: [Double]? = nil,
        constant: Double? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        multipleOf: Double? = nil
    ) {
        type = .integer
        self.title = title
        self.description = description
        self.allowedValues = allowedValues
        self.constant = constant
        self.minimum = minimum
        self.maximum = maximum
        self.multipleOf = multipleOf
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case description
        case allowedValues = "enum"
        case constant = "const"
        case minimum
        case maximum
        case multipleOf
    }
}

public struct FeedbackCampaignBooleanAnswerSchema: Codable, Hashable, Sendable {
    public let type: FeedbackCampaignAnswerType
    public let title: String?
    public let description: String?
    public let constant: Bool?

    public init(
        title: String? = nil,
        description: String? = nil,
        constant: Bool? = nil
    ) {
        type = .boolean
        self.title = title
        self.description = description
        self.constant = constant
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case description
        case constant = "const"
    }
}

public struct FeedbackCampaignArrayAnswerSchema: Codable, Hashable, Sendable {
    public let type: FeedbackCampaignAnswerType
    public let title: String?
    public let description: String?
    public let items: FeedbackCampaignScalarAnswerSchema
    public let minItems: Int?
    public let maxItems: Int
    public let uniqueItems: Bool?

    public init(
        title: String? = nil,
        description: String? = nil,
        items: FeedbackCampaignScalarAnswerSchema,
        minItems: Int? = nil,
        maxItems: Int,
        uniqueItems: Bool? = nil
    ) {
        type = .array
        self.title = title
        self.description = description
        self.items = items
        self.minItems = minItems
        self.maxItems = maxItems
        self.uniqueItems = uniqueItems
    }
}

// MARK: - Response values

public enum FeedbackCampaignScalarAnswer: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)

    public init(_ value: String) { self = .string(value) }
    public init(_ value: Int) { self = .number(Double(value)) }
    public init(_ value: Double) { self = .number(value) }
    public init(_ value: Bool) { self = .boolean(value) }

    var containsOnlyFiniteNumbers: Bool {
        switch self {
        case .string, .boolean: true
        case let .number(value): value.isFinite
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { self = .number(try container.decode(Double.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        }
    }
}

/// A value submitted for one campaign question.
public enum FeedbackCampaignAnswer: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case array([FeedbackCampaignScalarAnswer])

    public init(_ value: String) { self = .string(value) }
    public init(_ value: Int) { self = .number(Double(value)) }
    public init(_ value: Double) { self = .number(value) }
    public init(_ value: Bool) { self = .boolean(value) }
    public init(_ values: [String]) { self = .array(values.map(FeedbackCampaignScalarAnswer.init)) }
    public init(_ values: [Int]) { self = .array(values.map(FeedbackCampaignScalarAnswer.init)) }
    public init(_ values: [Double]) { self = .array(values.map(FeedbackCampaignScalarAnswer.init)) }
    public init(_ values: [Bool]) { self = .array(values.map(FeedbackCampaignScalarAnswer.init)) }

    var containsOnlyFiniteNumbers: Bool {
        switch self {
        case .string, .boolean: true
        case let .number(value): value.isFinite
        case let .array(values): values.allSatisfy(\.containsOnlyFiniteNumbers)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode([FeedbackCampaignScalarAnswer].self) { self = .array(value) }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { self = .number(try container.decode(Double.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        }
    }
}

public struct FeedbackCampaignResponseRequest: Codable, Equatable, Sendable {
    public let answers: [String: FeedbackCampaignAnswer]
    public let comment: String?
    public let clientContext: FeedbackClientContext
    public let attachmentIds: [String]
    public let diagnosticArtifactId: String?

    public init(
        answers: [String: FeedbackCampaignAnswer],
        comment: String? = nil,
        clientContext: FeedbackClientContext,
        attachmentIds: [String] = [],
        diagnosticArtifactId: String? = nil
    ) {
        self.answers = answers
        self.comment = comment
        self.clientContext = clientContext
        self.attachmentIds = attachmentIds
        self.diagnosticArtifactId = diagnosticArtifactId
    }
}
