import FeedbackKitCore
import SwiftUI

struct FeedbackRoadmapCard: View {
    let item: FeedbackRoadmapItem
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Text(FK.stage(item.roadmapStage))
                .font(stageFont)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: 66)

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
        .padding(.horizontal, 18)
        .frame(width: width, height: height, alignment: .leading)
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
            : .largeTitle.weight(.black)
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
