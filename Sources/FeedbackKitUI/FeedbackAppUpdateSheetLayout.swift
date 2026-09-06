import SwiftUI

/// Uses the host app's existing sheet template while retaining the SDK's update actions.
@MainActor
public struct FeedbackAppUpdateSheetLayout {
    public struct Content {
        public let title: String
        public let message: String
        public let details: AnyView
        public let actions: AnyView
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
