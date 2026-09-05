import FeedbackKitCore
import SwiftUI

struct FeedbackSheetHost: View {
    let sheet: FeedbackCenterSheet
    @Bindable var model: FeedbackCenterModel
    let style: FeedbackStyle
    let activatePost: (FeedbackDeveloperPostAction) -> Void
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            switch sheet {
            case .kinds:
                FeedbackKindPicker(style: style) {
                    model.sheet = .composer($0)
                } close: {
                    model.sheet = nil
                }
            case let .composer(kind):
                if let product = model.bootstrap?.product {
                    FeedbackComposer(
                        kind: kind,
                        product: product,
                        client: model.client,
                        draftStore: FeedbackDraftStore(),
                        style: style,
                        submitted: {
                            model.sheet = nil
                            Task { await model.load(locale: locale, force: true) }
                        },
                        close: { model.sheet = nil }
                    )
                }
            case let .feedback(id):
                FeedbackDetailSheet(
                    id: id,
                    client: model.client,
                    style: style,
                    voteChanged: model.synchronizeVote,
                    viewed: { await model.markFeedbackRead(feedbackID: id) }
                ) {
                    model.sheet = nil
                }
            case let .developerPost(id):
                FeedbackDeveloperPostSheet(
                    id: id,
                    client: model.client,
                    style: style,
                    activate: activatePost
                ) {
                    model.sheet = nil
                }
            case let .campaign(id):
                FeedbackCampaignSheet(
                    campaignID: id,
                    client: model.client,
                    style: style,
                    haptics: haptics
                )
            }
        }
        .presentationDragIndicator(.hidden)
    }

}
