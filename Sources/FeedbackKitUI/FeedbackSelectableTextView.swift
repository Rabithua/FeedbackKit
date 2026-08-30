#if os(iOS)
import SwiftUI

@MainActor
struct FeedbackSelectableTextView: UIViewRepresentable {
    let text: String
    let style: FeedbackSelectableTextStyle
    let openURL: (URL) -> Void

    func makeCoordinator() -> FeedbackSelectableTextCoordinator {
        FeedbackSelectableTextCoordinator(openURL: openURL)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textAlignment = .natural
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.openURL = openURL
        textView.linkTextAttributes = [
            .foregroundColor: textView.tintColor ?? UIColor.link,
        ]

        let attributedText = makeAttributedText()
        guard textView.attributedText.isEqual(to: attributedText) == false else {
            return
        }

        let selectedRange = textView.selectedRange
        textView.attributedText = attributedText
        if NSMaxRange(selectedRange) <= attributedText.length {
            textView.selectedRange = selectedRange
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else {
            return nil
        }

        let fittedSize = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(fittedSize.height))
    }

    private func makeAttributedText() -> NSAttributedString {
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: style.uiFont,
                .foregroundColor: style.uiColor,
            ]
        )

        for link in FeedbackTextLinkDetector.links(in: text) {
            attributedText.addAttribute(.link, value: link.url, range: link.range)
        }

        return attributedText
    }
}
#endif
