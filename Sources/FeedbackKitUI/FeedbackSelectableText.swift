import SwiftUI

struct FeedbackSelectableText: View {
    let text: String
    let style: FeedbackSelectableTextStyle

    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.openURL) private var openURL

    init(_ text: String, style: FeedbackSelectableTextStyle = .body) {
        self.text = text
        self.style = style
    }

    var body: some View {
        #if os(iOS)
        FeedbackSelectableTextView(
            text: text,
            style: style,
            openURL: openLink
        )
        #else
        Text(attributedText)
            .font(style.font)
            .textSelection(.enabled)
        #endif
    }

    private func openLink(_ url: URL) {
        haptics.trigger(.action)
        openURL(url)
    }

    #if os(macOS)
    private var attributedText: AttributedString {
        var attributedText = AttributedString(text)
        attributedText.foregroundColor = style.color

        for link in FeedbackTextLinkDetector.links(in: text) {
            guard let stringRange = Range(link.range, in: text),
                  let attributedRange = Range(stringRange, in: attributedText)
            else {
                continue
            }

            attributedText[attributedRange].link = link.url
            attributedText[attributedRange].foregroundColor = .accentColor
        }

        return attributedText
    }
    #endif
}
