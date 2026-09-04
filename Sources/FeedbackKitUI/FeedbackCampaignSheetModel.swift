import FeedbackKitCore
import Foundation
import Observation

enum FeedbackCampaignValidationIssue: Error, Equatable {
    case required
    case invalid
    case tooShort
    case tooLong
    case tooSmall
    case tooLarge
    case invalidStep
    case tooFewItems
    case tooManyItems
    case duplicateItems

    var localizationKey: String {
        switch self {
        case .required: "feedbackkit.campaign.validation.required"
        case .invalid: "feedbackkit.campaign.validation.invalid"
        case .tooShort: "feedbackkit.campaign.validation.too.short"
        case .tooLong: "feedbackkit.campaign.validation.too.long"
        case .tooSmall: "feedbackkit.campaign.validation.too.small"
        case .tooLarge: "feedbackkit.campaign.validation.too.large"
        case .invalidStep: "feedbackkit.campaign.validation.step"
        case .tooFewItems: "feedbackkit.campaign.validation.too.few.items"
        case .tooManyItems: "feedbackkit.campaign.validation.too.many.items"
        case .duplicateItems: "feedbackkit.campaign.validation.duplicate.items"
        }
    }
}

struct FeedbackCampaignChoice: Identifiable, Hashable {
    let value: FeedbackCampaignScalarAnswer

    var id: String {
        switch value {
        case let .string(value): "string:\(value)"
        case let .number(value): "number:\(value.bitPattern)"
        case let .boolean(value): "boolean:\(value)"
        }
    }

    func label(locale: Locale, localization: FeedbackLocalization) -> String {
        switch value {
        case let .string(value): value
        case let .number(value): value.formatted(.number.locale(locale))
        case let .boolean(value):
            localization.text(
                value ? "feedbackkit.campaign.answer.yes" : "feedbackkit.campaign.answer.no"
            )
        }
    }
}

struct FeedbackCampaignArrayItem: Identifiable, Equatable {
    let id: UUID
    var value: FeedbackCampaignScalarAnswer

    init(id: UUID = UUID(), value: FeedbackCampaignScalarAnswer = .string("")) {
        self.id = id
        self.value = value
    }

    var text: String {
        get {
            switch value {
            case let .string(value): value
            case let .number(value): String(value)
            case let .boolean(value): String(value)
            }
        }
        set { value = .string(newValue) }
    }
}

@MainActor @Observable
final class FeedbackCampaignQuestionState {
    let question: FeedbackCampaignQuestion
    let scalarChoices: [FeedbackCampaignChoice]?
    let arrayChoices: [FeedbackCampaignChoice]?

    var scalarValue: FeedbackCampaignScalarAnswer?
    var selectedArrayValues: Set<FeedbackCampaignScalarAnswer> = []
    var arrayItems: [FeedbackCampaignArrayItem] = []

    init(question: FeedbackCampaignQuestion) {
        self.question = question
        switch question.answer {
        case let .string(schema):
            scalarChoices = Self.choices(
                for: FeedbackCampaignScalarAnswerSchema.string(schema)
            )
            arrayChoices = nil
        case let .number(schema):
            scalarChoices = Self.choices(
                for: FeedbackCampaignScalarAnswerSchema.number(schema)
            )
            arrayChoices = nil
        case let .integer(schema):
            scalarChoices = Self.choices(
                for: FeedbackCampaignScalarAnswerSchema.integer(schema)
            )
            arrayChoices = nil
        case let .boolean(schema):
            scalarChoices = Self.choices(
                for: FeedbackCampaignScalarAnswerSchema.boolean(schema)
            )
            arrayChoices = nil
        case let .array(schema):
            scalarChoices = nil
            arrayChoices = Self.choices(for: schema.items)
        }
    }

    var text: String {
        get {
            guard let scalarValue else { return "" }
            return switch scalarValue {
            case let .string(value): value
            case let .number(value): String(value)
            case let .boolean(value): String(value)
            }
        }
        set { scalarValue = .string(newValue) }
    }

    var hasInput: Bool {
        scalarValue != nil || selectedArrayValues.isEmpty == false || arrayItems.isEmpty == false
    }

    var canAddArrayItem: Bool {
        guard case let .array(schema) = question.answer else { return false }
        return arrayChoices == nil && arrayItems.count < schema.maxItems
    }

    func isScalarChoiceSelected(_ choice: FeedbackCampaignChoice) -> Bool {
        scalarValue == choice.value
    }

    func selectScalarChoice(_ choice: FeedbackCampaignChoice) {
        if question.required == false, scalarValue == choice.value {
            scalarValue = nil
        } else {
            scalarValue = choice.value
        }
    }

    func isArrayChoiceSelected(_ choice: FeedbackCampaignChoice) -> Bool {
        selectedArrayValues.contains(choice.value)
    }

    func isArrayChoiceDisabled(_ choice: FeedbackCampaignChoice) -> Bool {
        guard case let .array(schema) = question.answer else { return true }
        return isArrayChoiceSelected(choice) == false
            && selectedArrayValues.count >= schema.maxItems
    }

    func toggleArrayChoice(_ choice: FeedbackCampaignChoice) {
        if selectedArrayValues.remove(choice.value) == nil,
           isArrayChoiceDisabled(choice) == false {
            selectedArrayValues.insert(choice.value)
        }
    }

    func addArrayItem() {
        guard canAddArrayItem else { return }
        arrayItems.append(FeedbackCampaignArrayItem())
    }

    func removeArrayItem(id: UUID) {
        arrayItems.removeAll { $0.id == id }
    }

    func resolvedAnswer(locale: Locale) -> Result<FeedbackCampaignAnswer?, FeedbackCampaignValidationIssue> {
        switch question.answer {
        case let .string(schema):
            return scalarAnswer(
                schema: .string(schema),
                locale: locale
            )
        case let .number(schema):
            return scalarAnswer(
                schema: .number(schema),
                locale: locale
            )
        case let .integer(schema):
            return scalarAnswer(
                schema: .integer(schema),
                locale: locale
            )
        case let .boolean(schema):
            return scalarAnswer(
                schema: .boolean(schema),
                locale: locale
            )
        case let .array(schema):
            return arrayAnswer(schema: schema, locale: locale)
        }
    }

    private func scalarAnswer(
        schema: FeedbackCampaignScalarAnswerSchema,
        locale: Locale
    ) -> Result<FeedbackCampaignAnswer?, FeedbackCampaignValidationIssue> {
        guard let scalarValue else {
            return question.required ? .failure(.required) : .success(nil)
        }

        switch Self.validate(scalarValue, against: schema, locale: locale) {
        case let .success(answer):
            switch answer {
            case let .string(value): return .success(.string(value))
            case let .number(value): return .success(.number(value))
            case let .boolean(value): return .success(.boolean(value))
            }
        case let .failure(issue):
            return .failure(issue)
        }
    }

    private func arrayAnswer(
        schema: FeedbackCampaignArrayAnswerSchema,
        locale: Locale
    ) -> Result<FeedbackCampaignAnswer?, FeedbackCampaignValidationIssue> {
        let drafts: [FeedbackCampaignScalarAnswer]
        if let arrayChoices {
            drafts = arrayChoices.compactMap { choice in
                selectedArrayValues.contains(choice.value) ? choice.value : nil
            }
        } else {
            drafts = arrayItems.map(\.value)
        }

        if drafts.isEmpty {
            return question.required ? .failure(.required) : .success(nil)
        }
        if drafts.count < (schema.minItems ?? 0) {
            return .failure(drafts.isEmpty ? .required : .tooFewItems)
        }
        guard drafts.count <= schema.maxItems else {
            return .failure(.tooManyItems)
        }

        var answers: [FeedbackCampaignScalarAnswer] = []
        for draft in drafts {
            switch Self.validate(draft, against: schema.items, locale: locale) {
            case let .success(answer): answers.append(answer)
            case let .failure(issue): return .failure(issue)
            }
        }
        if schema.uniqueItems == true, Set(answers).count != answers.count {
            return .failure(.duplicateItems)
        }
        return .success(.array(answers))
    }

    private static func validate(
        _ draft: FeedbackCampaignScalarAnswer,
        against schema: FeedbackCampaignScalarAnswerSchema,
        locale: Locale
    ) -> Result<FeedbackCampaignScalarAnswer, FeedbackCampaignValidationIssue> {
        switch schema {
        case let .string(schema):
            guard case let .string(value) = draft else { return .failure(.invalid) }
            let length = value.unicodeScalars.count
            if length < (schema.minLength ?? 0) { return .failure(.tooShort) }
            if length > schema.maxLength { return .failure(.tooLong) }
            if let allowedValues = schema.allowedValues, allowedValues.contains(value) == false {
                return .failure(.invalid)
            }
            if let constant = schema.constant, value != constant { return .failure(.invalid) }
            return .success(.string(value))

        case let .number(schema):
            return validateNumber(
                draft,
                allowedValues: schema.allowedValues,
                constant: schema.constant,
                minimum: schema.minimum,
                maximum: schema.maximum,
                multipleOf: schema.multipleOf,
                requiresInteger: false,
                locale: locale
            )

        case let .integer(schema):
            return validateNumber(
                draft,
                allowedValues: schema.allowedValues,
                constant: schema.constant,
                minimum: schema.minimum,
                maximum: schema.maximum,
                multipleOf: schema.multipleOf,
                requiresInteger: true,
                locale: locale
            )

        case let .boolean(schema):
            guard case let .boolean(value) = draft else { return .failure(.invalid) }
            if let constant = schema.constant, value != constant { return .failure(.invalid) }
            return .success(.boolean(value))
        }
    }

    private static func validateNumber(
        _ draft: FeedbackCampaignScalarAnswer,
        allowedValues: [Double]?,
        constant: Double?,
        minimum: Double?,
        maximum: Double?,
        multipleOf: Double?,
        requiresInteger: Bool,
        locale: Locale
    ) -> Result<FeedbackCampaignScalarAnswer, FeedbackCampaignValidationIssue> {
        let value: Double
        switch draft {
        case let .number(number): value = number
        case let .string(text):
            guard let parsed = parseNumber(text, locale: locale) else { return .failure(.invalid) }
            value = parsed
        case .boolean:
            return .failure(.invalid)
        }

        guard value.isFinite else { return .failure(.invalid) }
        if requiresInteger, value.rounded() != value { return .failure(.invalid) }
        if let minimum, value < minimum { return .failure(.tooSmall) }
        if let maximum, value > maximum { return .failure(.tooLarge) }
        if let multipleOf, isMultiple(value, of: multipleOf) == false {
            return .failure(.invalidStep)
        }
        if let allowedValues, allowedValues.contains(value) == false { return .failure(.invalid) }
        if let constant, value != constant { return .failure(.invalid) }
        return .success(.number(value))
    }

    private static func parseNumber(_ text: String, locale: Locale) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        return formatter.number(from: trimmed)?.doubleValue
    }

    private static func isMultiple(_ value: Double, of divisor: Double) -> Bool {
        guard divisor.isFinite, divisor > 0 else { return false }
        let quotient = value / divisor
        let tolerance = max(1, abs(quotient)) * 1e-9
        return abs(quotient - quotient.rounded()) <= tolerance
    }

    private static func choices(
        for schema: FeedbackCampaignScalarAnswerSchema
    ) -> [FeedbackCampaignChoice]? {
        let values: [FeedbackCampaignScalarAnswer]?
        switch schema {
        case let .string(schema):
            if let constant = schema.constant {
                values = [.string(constant)]
            } else {
                values = schema.allowedValues?.map(FeedbackCampaignScalarAnswer.string)
            }
        case let .number(schema):
            if let constant = schema.constant {
                values = [.number(constant)]
            } else if let allowedValues = schema.allowedValues {
                values = allowedValues.map(FeedbackCampaignScalarAnswer.number)
            } else {
                values = boundedNumberChoices(
                    minimum: schema.minimum,
                    maximum: schema.maximum,
                    multipleOf: schema.multipleOf
                )
            }
        case let .integer(schema):
            if let constant = schema.constant {
                values = [.number(constant)]
            } else if let allowedValues = schema.allowedValues {
                values = allowedValues.map(FeedbackCampaignScalarAnswer.number)
            } else {
                values = boundedIntegerChoices(
                    minimum: schema.minimum,
                    maximum: schema.maximum,
                    multipleOf: schema.multipleOf
                )
            }
        case let .boolean(schema):
            values = schema.constant.map { [.boolean($0)] } ?? [.boolean(true), .boolean(false)]
        }
        guard let values else { return nil }
        var seen = Set<FeedbackCampaignScalarAnswer>()
        return values.compactMap { value in
            seen.insert(value).inserted ? FeedbackCampaignChoice(value: value) : nil
        }
    }

    private static func boundedIntegerChoices(
        minimum: Double?,
        maximum: Double?,
        multipleOf: Double?
    ) -> [FeedbackCampaignScalarAnswer]? {
        guard let minimum, let maximum,
              minimum.isFinite, maximum.isFinite,
              maximum >= minimum,
              maximum - minimum <= 20
        else { return nil }
        let lower = Int(ceil(minimum))
        let upper = Int(floor(maximum))
        guard lower <= upper else { return nil }
        let values = (lower...upper).compactMap { value -> FeedbackCampaignScalarAnswer? in
            let number = Double(value)
            guard multipleOf.map({ isMultiple(number, of: $0) }) ?? true else { return nil }
            return .number(number)
        }
        return values.isEmpty || values.count > 11 ? nil : values
    }

    private static func boundedNumberChoices(
        minimum: Double?,
        maximum: Double?,
        multipleOf: Double?
    ) -> [FeedbackCampaignScalarAnswer]? {
        guard let minimum, let maximum, let multipleOf,
              minimum.isFinite, maximum.isFinite,
              multipleOf.isFinite, multipleOf > 0,
              maximum >= minimum
        else { return nil }
        let first = ceil(minimum / multipleOf)
        let last = floor(maximum / multipleOf)
        guard first <= last, last - first <= 10 else { return nil }
        return stride(from: first, through: last, by: 1).map {
            .number($0 * multipleOf)
        }
    }
}

private struct FeedbackCampaignSubmissionFingerprint: Equatable {
    let answers: [String: FeedbackCampaignAnswer]
    let comment: String?
    let includesDiagnostics: Bool
    let localeIdentifier: String
}

private struct FeedbackCampaignPendingAttempt {
    let fingerprint: FeedbackCampaignSubmissionFingerprint
    let idempotencyKey: String
}

@MainActor @Observable
final class FeedbackCampaignSheetModel {
    let client: FeedbackClient
    let campaignID: String

    private(set) var campaign: FeedbackCampaign?
    private(set) var questionStates: [String: FeedbackCampaignQuestionState] = [:]
    private(set) var isLoading: Bool
    private(set) var isSubmitting = false
    private(set) var diagnosticsAvailable = false
    private(set) var loadError: Error?
    private(set) var submissionErrorMessage: String?
    var currentPageIndex = 0
    var comment = ""
    var includesDiagnostics = false
    var diagnosticFailure = false
    var validatedPageIDs: Set<Int> = []

    @ObservationIgnored private var didLoadDiagnosticsCapability = false
    @ObservationIgnored private var pendingAttempt: FeedbackCampaignPendingAttempt?

    init(campaign: FeedbackCampaign, client: FeedbackClient) {
        self.client = client
        campaignID = campaign.id
        self.campaign = campaign
        isLoading = false
        configureQuestionStates(for: campaign)
    }

    init(campaignID: String, client: FeedbackClient) {
        self.client = client
        self.campaignID = campaignID
        campaign = nil
        isLoading = true
    }

    var form: FeedbackCampaignForm? { campaign?.form }

    var currentPage: FeedbackCampaignFormPage? {
        guard let pages = form?.pages, pages.indices.contains(currentPageIndex) else { return nil }
        return pages[currentPageIndex]
    }

    var isLastPage: Bool {
        guard let pages = form?.pages else { return true }
        return currentPageIndex >= pages.count - 1
    }

    var hasInput: Bool {
        comment.isEmpty == false
            || includesDiagnostics
            || questionStates.values.contains(where: \.hasInput)
    }

    var commentIsTooLong: Bool {
        comment.count > 20_000
    }

    func load(locale: Locale) async {
        if campaign == nil {
            await loadCampaign()
        }
        await loadDiagnosticsCapability(locale: locale)
    }

    func retry(locale: Locale) async {
        loadError = nil
        await load(locale: locale)
    }

    func questionState(
        for question: FeedbackCampaignQuestion
    ) -> FeedbackCampaignQuestionState? {
        questionStates[question.key]
    }

    func validationIssue(
        for question: FeedbackCampaignQuestion,
        on page: FeedbackCampaignFormPage,
        locale: Locale
    ) -> FeedbackCampaignValidationIssue? {
        guard validatedPageIDs.contains(page.id) else { return nil }
        guard let state = questionState(for: question),
              case let .failure(issue) = state.resolvedAnswer(locale: locale) else {
            return nil
        }
        return issue
    }

    func advance(locale: Locale) -> Bool {
        guard let page = currentPage else { return false }
        validatedPageIDs.insert(page.id)
        guard pageIsValid(page, locale: locale) else { return false }
        guard isLastPage == false else { return true }
        currentPageIndex += 1
        return true
    }

    func goBack() {
        guard currentPageIndex > 0, isSubmitting == false else { return }
        currentPageIndex -= 1
    }

    func submit(
        locale: Locale,
        localization: FeedbackLocalization,
        diagnosticsOverride: Bool? = nil
    ) async -> OwnedFeedbackSummary? {
        guard isSubmitting == false, let form else { return nil }
        validatedPageIDs.formUnion(form.pages.map(\.id))
        guard validateEntireForm(form, locale: locale) else { return nil }

        let answers = resolvedAnswers(locale: locale)
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let includeDiagnostics = (diagnosticsOverride ?? includesDiagnostics) && diagnosticsAvailable
        let fingerprint = FeedbackCampaignSubmissionFingerprint(
            answers: answers,
            comment: trimmedComment.isEmpty ? nil : trimmedComment,
            includesDiagnostics: includeDiagnostics,
            localeIdentifier: locale.identifier
        )
        let attempt: FeedbackCampaignPendingAttempt
        if let pendingAttempt, pendingAttempt.fingerprint == fingerprint {
            attempt = pendingAttempt
        } else {
            attempt = FeedbackCampaignPendingAttempt(
                fingerprint: fingerprint,
                idempotencyKey: UUID().uuidString
            )
            pendingAttempt = attempt
        }

        isSubmitting = true
        submissionErrorMessage = nil
        diagnosticFailure = false
        defer { isSubmitting = false }
        do {
            let response = try await client.submitCampaignResponse(
                campaignID: campaignID,
                answers: fingerprint.answers,
                comment: fingerprint.comment,
                locale: locale,
                includeDiagnostics: includeDiagnostics,
                idempotencyKey: attempt.idempotencyKey
            )
            pendingAttempt = nil
            return response
        } catch let error as FeedbackClientError where error.kind == .diagnosticUploadFailed {
            diagnosticFailure = true
            submissionErrorMessage = localization.text("feedbackkit.diagnostics.upload.failed")
            return nil
        } catch is CancellationError {
            submissionErrorMessage = nil
            diagnosticFailure = false
            return nil
        } catch {
            submissionErrorMessage = localization.errorMessage(for: error)
            return nil
        }
    }

    private func loadCampaign() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let campaign = try await client.campaign(id: campaignID)
            try Task.checkCancellation()
            self.campaign = campaign
            configureQuestionStates(for: campaign)
        } catch is CancellationError {
            return
        } catch {
            loadError = error
        }
    }

    private func loadDiagnosticsCapability(locale: Locale) async {
        guard didLoadDiagnosticsCapability == false, client.diagnosticsProvider != nil else { return }
        didLoadDiagnosticsCapability = true
        do {
            let bootstrap = try await client.bootstrap(locale: locale)
            try Task.checkCancellation()
            diagnosticsAvailable = bootstrap.product.diagnostics?.supportsSchemaOne == true
        } catch {
            diagnosticsAvailable = false
        }
    }

    private func configureQuestionStates(for campaign: FeedbackCampaign) {
        var states: [String: FeedbackCampaignQuestionState] = [:]
        for element in campaign.form.pages.flatMap(\.elements) {
            guard case let .question(question) = element.content else { continue }
            states[question.key] = FeedbackCampaignQuestionState(question: question)
        }
        questionStates = states
        currentPageIndex = 0
        validatedPageIDs.removeAll()
    }

    private func pageIsValid(_ page: FeedbackCampaignFormPage, locale: Locale) -> Bool {
        page.elements.allSatisfy { element in
            guard case let .question(question) = element.content else { return true }
            guard let state = questionState(for: question),
                  case .success = state.resolvedAnswer(locale: locale) else {
                return false
            }
            return true
        }
    }

    private func validateEntireForm(_ form: FeedbackCampaignForm, locale: Locale) -> Bool {
        guard commentIsTooLong == false else {
            currentPageIndex = max(0, form.pages.count - 1)
            return false
        }
        for (index, page) in form.pages.enumerated() where pageIsValid(page, locale: locale) == false {
            currentPageIndex = index
            return false
        }
        return true
    }

    private func resolvedAnswers(locale: Locale) -> [String: FeedbackCampaignAnswer] {
        questionStates.reduce(into: [:]) { answers, entry in
            guard case let .success(answer?) = entry.value.resolvedAnswer(locale: locale) else { return }
            answers[entry.key] = answer
        }
    }
}
