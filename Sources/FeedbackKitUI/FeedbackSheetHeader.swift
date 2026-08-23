import SwiftUI

struct FeedbackSheetHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing
    let close: () -> Void

    init(title: String, @ViewBuilder trailing: () -> Trailing, close: @escaping () -> Void) {
        self.title = title
        self.trailing = trailing()
        self.close = close
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.title3.bold())
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing
            FeedbackCloseButton(action: close)
        }
        .frame(minHeight: 36)
    }
}

extension FeedbackSheetHeader where Trailing == EmptyView {
    init(title: String, close: @escaping () -> Void) {
        self.init(title: title, trailing: { EmptyView() }, close: close)
    }
}
