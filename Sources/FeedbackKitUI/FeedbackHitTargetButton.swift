import SwiftUI

struct FeedbackHitTargetButton<Label: View>: View {
    let action: () -> Void
    let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }
}
