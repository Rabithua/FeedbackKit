import FeedbackKitCore
import FeedbackKitUI
import SwiftUI

/// This compile-only fixture mirrors the minimal host integration in the README.
struct FeedbackKitIntegrationExample: View {
    private static let client = FeedbackClient(
        configuration: .init(
            baseURL: URL(string: "https://feedback.example.com/v1/api")!,
            productKey: "pk_example",
            keychainService: "com.example.MyApp.feedback.visitor"
        )
    )

    var body: some View {
        FeedbackCenterView(client: Self.client)
    }
}
