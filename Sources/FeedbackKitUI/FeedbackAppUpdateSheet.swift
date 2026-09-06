import SwiftUI

/// A compact update reminder, also available for host previews.
public struct FeedbackAppUpdateSheet: View {
    private let update: FeedbackAppUpdate
    private let haptics: FeedbackHaptics
    private let languagePolicy: FeedbackLanguagePolicy
    private let continueFeedback: () -> Void
    private let close: () -> Void
    @Environment(\.locale) private var hostLocale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @State private var isOpeningUpdate = false
    @State private var openingFailed = false

    public init(
        update: FeedbackAppUpdate,
        haptics: FeedbackHaptics = .none,
        languagePolicy: FeedbackLanguagePolicy = .followHost,
        continueFeedback: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        self.update = update
        self.haptics = haptics
        self.languagePolicy = languagePolicy
        self.continueFeedback = continueFeedback
        self.close = close
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.down.app.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(localization.text("feedbackkit.update.title"))
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        FeedbackCloseButton(action: close)
                            .disabled(isOpeningUpdate)
                    }
                    Text(localization.text("feedbackkit.update.message"))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(update.currentVersion)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.medium))
                        Text(update.latestVersion)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(localization.formattedText(
                        "feedbackkit.update.versions", update.currentVersion, update.latestVersion
                    ))
                    if openingFailed {
                        Text(localization.text("feedbackkit.update.failed"))
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("developerCommunity.update.failed")
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            HStack(spacing: 12) {
                Button {
                    haptics.trigger(.action)
                    continueFeedback()
                } label: {
                    Text(localization.text(dynamicTypeSize.isAccessibilitySize
                        ? "feedbackkit.update.continue.short" : "feedbackkit.update.continue"))
                        .frame(minWidth: 72)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(localization.text("feedbackkit.update.continue"))
                .accessibilityIdentifier("developerCommunity.update.continue")

                Button(action: openUpdate) {
                    Text(localization.text(dynamicTypeSize.isAccessibilitySize
                        ? "feedbackkit.update.open.short" : "feedbackkit.update.open"))
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(localization.text("feedbackkit.update.open"))
                .accessibilityIdentifier("developerCommunity.update.open")
            }
            .controlSize(.large)
            .disabled(isOpeningUpdate)
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(FeedbackSystemBackground())
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.fraction(0.42), .medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isOpeningUpdate)
        .environment(\.feedbackHaptics, haptics)
        .environment(\.feedbackLocalization, localization)
        .accessibilityIdentifier("developerCommunity.update.sheet")
    }

    private var localization: FeedbackLocalization {
        FeedbackLocalization(locale: languagePolicy.resolve(hostLocale: hostLocale))
    }

    private func openUpdate() {
        guard !isOpeningUpdate else { return }
        haptics.trigger(.action)
        isOpeningUpdate = true
        openingFailed = false
        openURL(update.url) { accepted in
            isOpeningUpdate = false
            if accepted {
                close()
            } else {
                openingFailed = true
                haptics.trigger(.error)
            }
        }
    }
}
