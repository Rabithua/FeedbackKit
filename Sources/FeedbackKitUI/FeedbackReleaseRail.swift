import SwiftUI

struct FeedbackReleaseRail: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let center = proxy.size.width / 2
                path.move(to: CGPoint(x: center - 10, y: 17))
                path.addLine(to: CGPoint(x: center, y: 5))
                path.addLine(to: CGPoint(x: center + 10, y: 17))
                path.move(to: CGPoint(x: center, y: 5))

                var y: CGFloat = 5
                var direction: CGFloat = 1
                while y < proxy.size.height {
                    y += 15
                    path.addLine(to: CGPoint(x: center + direction * 3, y: min(y, proxy.size.height)))
                    direction *= -1
                }
            }
            .stroke(
                Color.primary.opacity(0.08),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
