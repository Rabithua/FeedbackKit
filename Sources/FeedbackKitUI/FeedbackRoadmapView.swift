import FeedbackKitCore
import SwiftUI

struct FeedbackRoadmapView: View {
    let items: [FeedbackRoadmapItem]
    let style: FeedbackStyle

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        Group {
            if activeItems.isEmpty {
                ContentUnavailableView(
                    localization.text("feedbackkit.roadmap.empty.stage"),
                    systemImage: "map"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: itemSpacing) {
                        ForEach(activeItems) { item in
                            FeedbackRoadmapCard(
                                item: item,
                                minimumHeight: minimumCardHeight
                            )
                        }
                    }
                    .padding(style.pagePadding)
                }
            }
        }
        .background(FeedbackSystemBackground())
        .navigationTitle(localization.text("feedbackkit.roadmap.title"))
        .feedbackInlineNavigationTitle()
    }

    private var activeItems: [FeedbackRoadmapItem] {
        items
            .filter { $0.archivedAt == nil }
            .sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var minimumCardHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 108 : 72
    }

    private var itemSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 24 : 18
    }
}
