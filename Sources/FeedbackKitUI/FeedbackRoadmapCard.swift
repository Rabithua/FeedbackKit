import FeedbackKitCore
import SwiftUI

struct FeedbackRoadmapCard: View {
    let item: FeedbackRoadmapItem
    let minimumHeight: CGFloat

    @ScaledMetric(relativeTo: .largeTitle) private var prominentStageSize: CGFloat = 40
    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        HStack(spacing: 8) {
            Text(localization.stage(item.roadmapStage))
                .font(stageFont)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.title3.bold())
                    .lineLimit(1)

                if item.body.isEmpty == false {
                    Text(item.body)
                        .font(.body)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
        .background {
            LinearGradient(
                stops: [
                    .init(color: item.roadmapStage.feedbackColor, location: 0),
                    .init(color: item.roadmapStage.feedbackColor, location: 0.16),
                    .init(color: item.roadmapStage.feedbackColor.opacity(0.58), location: 0.48),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .accessibilityElement(children: .combine)
    }

    private var stageFont: Font {
        item.roadmapStage == .undecided
            ? .title3.weight(.black)
            : .system(size: prominentStageSize, weight: .black)
    }
}

private extension RoadmapStage {
    var feedbackColor: Color {
        switch self {
        case .urgent: .red
        case .later: .accentColor
        case .undecided: Color(white: 0.8)
        }
    }
}
