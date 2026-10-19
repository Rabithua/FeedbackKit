import SwiftUI

/// Uses the host app's existing sheet template while retaining the SDK's update actions.
@MainActor
public struct FeedbackAppUpdateSheetLayout {
    public struct Content {
        public let title: String
        public let message: String
        public let details: AnyView
        /// The SDK's ready-made buttons, retained for layouts that use native controls.
        public let actions: AnyView
        /// Display titles follow the current Dynamic Type size; accessibility labels stay complete.
        public let continueTitle: String
        public let updateTitle: String
        public let continueAccessibilityLabel: String
        public let updateAccessibilityLabel: String
        /// Hosts can use these actions with their own button styles without reimplementing behavior.
        public let continueFeedback: () -> Void
        public let openUpdate: () -> Void
        public let isBusy: Bool
        public let close: () -> Void
    }

    private let makeBody: (Content) -> AnyView

    public init<Body: View>(@ViewBuilder content: @escaping (Content) -> Body) {
        makeBody = { AnyView(content($0)) }
    }

    func body(for content: Content) -> some View {
        makeBody(content)
    }
}
