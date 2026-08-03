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
                    HStack(alignment: .top, spacing: columnSpacing) {
                        ForEach(0 ..< columnCount, id: \.self) { column in
                            LazyVStack(spacing: itemSpacing) {
                                ForEach(items(in: column)) { item in
                                    let length = cardLength(for: item)
                                    FeedbackRoadmapCard(
                                        item: item,
                                        width: length,
                                        height: cardThickness
                                    )
                                    .rotationEffect(.degrees(90))
                                    .frame(width: cardThickness, height: length)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, topPadding)
                    .padding(.bottom, style.pagePadding)
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

    private let columnCount = 4

    private func items(in column: Int) -> [FeedbackRoadmapItem] {
        activeItems.enumerated().compactMap { index, item in
            index % columnCount == column ? item : nil
        }
    }

    private func cardLength(for item: FeedbackRoadmapItem) -> CGFloat {
        let titleLength = min(item.title.count, 24)
        let bodyLength = min(item.body.count, 48)
        let contentLength = titleLength + bodyLength
        let base = min(350, max(224, 205 + CGFloat(contentLength) * 3.2))
        return dynamicTypeSize.isAccessibilitySize ? base + 100 : base
    }

    private var cardThickness: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 104 : 68
    }

    private var columnSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 28 : 23
    }

    private var itemSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 36 : 26
    }

    private var horizontalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? style.pagePadding : 20
    }

    private var topPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? style.pagePadding : 28
    }
}
