import FeedbackKitCore
import SwiftUI

struct FeedbackRoadmapView: View {
    let items: [FeedbackRoadmapItem]
    let style: FeedbackStyle

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if activeItems.isEmpty {
                ContentUnavailableView(
                    FK.text("feedbackkit.roadmap.empty.stage"),
                    systemImage: "map"
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyHGrid(rows: rows, alignment: .top, spacing: 42) {
                        ForEach(activeItems) { item in
                            FeedbackRoadmapCard(
                                item: item,
                                width: cardWidth,
                                height: rowHeight
                            )
                        }
                    }
                    .padding(style.pagePadding)
                }
            }
        }
        .background(FeedbackSystemBackground())
        .navigationTitle(FK.text("feedbackkit.roadmap.title"))
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

    private var rows: [GridItem] {
        Array(
            repeating: GridItem(.fixed(rowHeight), spacing: rowSpacing, alignment: .leading),
            count: dynamicTypeSize.isAccessibilitySize ? 2 : 4
        )
    }

    private var rowHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 132 : 86
    }

    private var rowSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 24 : 18
    }

    private var cardWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 480 : 390
    }
}
