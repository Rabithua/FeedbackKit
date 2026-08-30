import SwiftUI

enum FeedbackSelectableTextStyle: Hashable {
    case body
    case secondaryBody

    var font: Font {
        .body
    }

    var color: Color {
        switch self {
        case .body: .primary
        case .secondaryBody: .secondary
        }
    }

    #if os(iOS)
    var uiFont: UIFont {
        .preferredFont(forTextStyle: .body)
    }

    var uiColor: UIColor {
        switch self {
        case .body: .label
        case .secondaryBody: .secondaryLabel
        }
    }
    #endif
}
