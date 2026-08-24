import Foundation
import SwiftUI

struct FeedbackAttributionLink: View {
    static let destination = URL(string: "https://feedkit.cn/")!

    @Environment(\.feedbackLocalization) private var localization
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(action: openWebsite) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Text(verbatim: "Powered by")
                            .foregroundStyle(.secondary)
                        Text(verbatim: "FeedKit.cn")
                            .bold()
                            .foregroundStyle(brandColor)
                    }
                    VStack(spacing: 0) {
                        Text(verbatim: "Powered by")
                            .foregroundStyle(.secondary)
                        Text(verbatim: "FeedKit.cn")
                            .bold()
                            .foregroundStyle(brandColor)
                    }
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localization.text("feedbackkit.attribution.label"))
            .accessibilityHint(localization.text("feedbackkit.attribution.hint"))
            .accessibilityIdentifier("developerCommunity.attribution")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func openWebsite() {
        openURL(Self.destination)
    }

    private var brandColor: Color {
        Color("FeedbackKitBrandBlue", bundle: .module)
    }
}
