#if os(iOS)
import UIKit

@MainActor
final class FeedbackSelectableTextCoordinator: NSObject, UITextViewDelegate {
    var openURL: (URL) -> Void

    init(openURL: @escaping (URL) -> Void) {
        self.openURL = openURL
    }

    func textView(
        _ textView: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction: UIAction
    ) -> UIAction? {
        guard case let .link(url) = textItem.content else {
            return defaultAction
        }

        return UIAction { [weak self] _ in
            self?.openURL(url)
        }
    }
}
#endif
