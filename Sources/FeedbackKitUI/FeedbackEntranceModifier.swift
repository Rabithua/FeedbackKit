import SwiftUI

struct FeedbackEntranceModifier: ViewModifier {
    let isVisible: Bool
    let order: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || isVisible ? 1 : 0)
            .offset(y: reduceMotion || isVisible ? 0 : 8)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.28).delay(Double(order) * 0.045),
                value: isVisible
            )
    }
}

extension View {
    func feedbackEntrance(isVisible: Bool, order: Int, reduceMotion: Bool) -> some View {
        modifier(FeedbackEntranceModifier(isVisible: isVisible, order: order, reduceMotion: reduceMotion))
    }
}
