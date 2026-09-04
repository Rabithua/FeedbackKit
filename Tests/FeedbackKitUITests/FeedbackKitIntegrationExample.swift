import FeedbackKitCore
import FeedbackKitUI
import SwiftUI

/// This compile-only fixture mirrors the minimal host integration in the README.
@MainActor
struct FeedbackKitIntegrationExample: View {
    private static let client = FeedbackClient(
        configuration: try! FeedbackConfiguration(
            productKey: "pk_example",
            keychainService: "com.example.MyApp.feedback.visitor"
        )
    )
    @Environment(\.scenePhase) private var scenePhase
    @State private var replyInbox = FeedbackReplyInboxController(client: Self.client)
    @State private var selectedCampaign: FeedbackCampaign?

    var body: some View {
        FeedbackCenterView(client: Self.client)
            .task(id: scenePhase) {
                if scenePhase == .active {
                    await replyInbox.beginForegroundCycle()
                } else if scenePhase == .background {
                    replyInbox.endForegroundCycle()
                }
            }
            .sheet(item: $replyInbox.pendingPresentation) { presentation in
                FeedbackConversationSheet(
                    presentation: presentation,
                    controller: replyInbox
                )
            }
            .sheet(item: $selectedCampaign) { campaign in
                FeedbackCampaignSheet(campaign: campaign, client: Self.client)
            }
    }
}

/// This compile-only fixture covers the convenience initializer that loads a selected campaign.
@MainActor
struct FeedbackCampaignIDIntegrationExample: View {
    let client: FeedbackClient

    var body: some View {
        FeedbackCampaignSheet(campaignID: "campaign-id", client: client)
    }
}
