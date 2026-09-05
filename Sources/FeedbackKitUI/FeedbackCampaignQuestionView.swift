import FeedbackKitCore
import SwiftUI

struct FeedbackCampaignNoticeView: View {
    let text: String
    let style: FeedbackStyle

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .feedbackBorder(style)
        .accessibilityElement(children: .combine)
    }
}

struct FeedbackCampaignQuestionView: View {
    @Bindable var state: FeedbackCampaignQuestionState
    let issue: FeedbackCampaignValidationIssue?
    let style: FeedbackStyle

    @Environment(\.locale) private var locale
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(state.question.text)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if state.question.required == false {
                        Text(localization.text("feedbackkit.campaign.optional"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let title = state.question.answer.title,
                   title != state.question.text {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let description = state.question.answer.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            answerControl

            if let issue {
                Text(localization.text(issue.localizationKey))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(
                        "developerCommunity.campaign.validation.\(state.question.key)"
                    )
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.035))
        .feedbackBorder(style)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var answerControl: some View {
        if let choices = state.scalarChoices {
            VStack(spacing: 8) {
                ForEach(choices) { choice in
                    FeedbackCampaignChoiceRow(
                        label: choice.label(locale: locale, localization: localization),
                        selected: state.isScalarChoiceSelected(choice),
                        disabled: false,
                        style: style
                    ) {
                        haptics.trigger(.selection)
                        state.selectScalarChoice(choice)
                    }
                }
            }
        } else {
            switch state.question.answer {
            case .string:
                answerTextField(keyboard: .text)
            case .number:
                answerTextField(keyboard: .decimal)
            case .integer:
                answerTextField(keyboard: .integer)
            case .boolean:
                EmptyView()
            case let .array(schema):
                arrayControl(schema: schema)
            }
        }
    }

    private func answerTextField(keyboard: FeedbackCampaignKeyboard) -> some View {
        TextField(
            "",
            text: $state.text,
            prompt: Text(localization.text("feedbackkit.campaign.answer.placeholder"))
                .foregroundStyle(.secondary),
            axis: .vertical
        )
        .lineLimit(1...5)
        .feedbackCampaignKeyboard(keyboard)
        .padding(14)
        .feedbackBorder(style)
        .accessibilityLabel(state.question.text)
        .accessibilityIdentifier("developerCommunity.campaign.answer.\(state.question.key)")
    }

    @ViewBuilder
    private func arrayControl(schema: FeedbackCampaignArrayAnswerSchema) -> some View {
        if let choices = state.arrayChoices {
            VStack(spacing: 8) {
                if schema.uniqueItems == true {
                    ForEach(choices) { choice in
                        FeedbackCampaignChoiceRow(
                            label: choice.label(locale: locale, localization: localization),
                            selected: state.isArrayChoiceSelected(choice),
                            disabled: state.isArrayChoiceDisabled(choice),
                            style: style
                        ) {
                            haptics.trigger(.selection)
                            state.toggleArrayChoice(choice)
                        }
                    }
                } else {
                    ForEach(choices) { choice in
                        FeedbackCampaignRepeatableChoiceRow(
                            label: choice.label(locale: locale, localization: localization),
                            count: state.arrayChoiceCount(choice),
                            canAdd: state.selectedArrayValues.count < schema.maxItems,
                            style: style,
                            add: {
                                haptics.trigger(.selection)
                                state.addArrayChoice(choice)
                            },
                            remove: {
                                haptics.trigger(.selection)
                                state.removeArrayChoice(choice)
                            }
                        )
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach($state.arrayItems) { $item in
                    FeedbackCampaignArrayItemView(
                        item: $item,
                        schema: schema.items,
                        questionText: state.question.text,
                        style: style,
                        remove: {
                            haptics.trigger(.selection)
                            state.removeArrayItem(id: item.id)
                        }
                    )
                }

                Button {
                    haptics.trigger(.selection)
                    state.addArrayItem()
                } label: {
                    Label(
                        localization.text("feedbackkit.campaign.answer.add"),
                        systemImage: "plus"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(
                        .interaction,
                        FeedbackComponentShape(cornerRadius: style.cardCornerRadius)
                    )
                    .feedbackBorder(style)
                }
                .buttonStyle(.plain)
                .disabled(state.canAddArrayItem == false)
                .accessibilityIdentifier(
                    "developerCommunity.campaign.answer.add.\(state.question.key)"
                )
            }
        }
    }
}

private struct FeedbackCampaignRepeatableChoiceRow: View {
    let label: String
    let count: Int
    let canAdd: Bool
    let style: FeedbackStyle
    let add: () -> Void
    let remove: () -> Void

    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(count.formatted())
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    localization.formattedText("feedbackkit.campaign.answer.quantity", count)
                )
            FeedbackHitTargetButton(action: remove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
            FeedbackHitTargetButton(action: add) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(canAdd == false)
        }
        .padding(.leading, 14)
        .padding(.vertical, 4)
        .feedbackBorder(style)
    }
}

private struct FeedbackCampaignChoiceRow: View {
    let label: String
    let selected: Bool
    let disabled: Bool
    let style: FeedbackStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(selected ? Color.accentColor.opacity(0.12) : .clear)
            .contentShape(
                .interaction,
                FeedbackComponentShape(cornerRadius: style.cardCornerRadius)
            )
            .feedbackBorder(style)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct FeedbackCampaignArrayItemView: View {
    @Binding var item: FeedbackCampaignArrayItem
    let schema: FeedbackCampaignScalarAnswerSchema
    let questionText: String
    let style: FeedbackStyle
    let remove: () -> Void

    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        HStack(spacing: 6) {
            TextField(
                "",
                text: $item.text,
                prompt: Text(localization.text("feedbackkit.campaign.answer.placeholder"))
                    .foregroundStyle(.secondary)
            )
            .feedbackCampaignKeyboard(keyboard)
            .padding(.leading, 14)
            .padding(.vertical, 12)
            .accessibilityLabel(questionText)

            FeedbackHitTargetButton(action: remove) {
                Label(
                    localization.text("feedbackkit.campaign.answer.remove"),
                    systemImage: "minus.circle.fill"
                )
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .feedbackBorder(style)
    }

    private var keyboard: FeedbackCampaignKeyboard {
        switch schema {
        case .string, .boolean: .text
        case .number: .decimal
        case .integer: .integer
        }
    }
}

private enum FeedbackCampaignKeyboard {
    case text
    case decimal
    case integer
}

private extension View {
    @ViewBuilder
    func feedbackCampaignKeyboard(_ keyboard: FeedbackCampaignKeyboard) -> some View {
        #if os(iOS)
        switch keyboard {
        case .text: self
        case .decimal, .integer: keyboardType(.numbersAndPunctuation)
        }
        #else
        self
        #endif
    }
}
