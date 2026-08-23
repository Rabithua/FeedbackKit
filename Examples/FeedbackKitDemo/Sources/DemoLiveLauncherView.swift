import FeedbackKitCore
import FeedbackKitUI
import SwiftUI

struct DemoLiveLauncherView: View {
    @State private var model = DemoLiveModel()
    @State private var verificationRequest: UUID?
    @State private var presentation: DemoClientPresentation?

    var body: some View {
        Form {
            DemoLiveConfigurationSection(error: model.configurationError)
            DemoLiveVerificationSection(
                clientAvailable: model.client != nil,
                isVerifying: model.isVerifying,
                error: model.verificationError,
                action: requestVerification
            )
            if let integration = model.integration {
                DemoLiveIntegrationSection(
                    integration: integration,
                    action: openFeedbackCenter
                )
            }
        }
        .navigationTitle("Live mode")
        .task(id: verificationRequest) {
            guard verificationRequest != nil else { return }
            await model.verifyIntegration()
        }
        .fullScreenCover(item: $presentation) { presentation in
            FeedbackCenterView(client: presentation.client)
        }
    }

    private func requestVerification() {
        verificationRequest = UUID()
    }

    private func openFeedbackCenter() {
        guard let client = model.client else { return }
        presentation = DemoClientPresentation(client: client)
    }

}
