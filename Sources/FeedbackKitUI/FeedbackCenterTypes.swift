import FeedbackKitCore
import Foundation
import SwiftUI

public protocol FeedbackRouteHandler: Sendable {
    @MainActor func openFeedbackAppRoute(_ route: String) -> Bool
}

public struct IgnoreFeedbackRouteHandler: FeedbackRouteHandler {
    public init() {}
    @MainActor public func openFeedbackAppRoute(_ route: String) -> Bool { false }
}

public struct FeedbackStyle: Sendable {
    public let pagePadding: CGFloat
    public let sectionSpacing: CGFloat
    public let cardCornerRadius: CGFloat
    public let borderWidth: CGFloat

    public init(
        pagePadding: CGFloat = 20,
        sectionSpacing: CGFloat = 24,
        cardCornerRadius: CGFloat = 0,
        borderWidth: CGFloat = 1
    ) {
        self.pagePadding = pagePadding
        self.sectionSpacing = sectionSpacing
        self.cardCornerRadius = cardCornerRadius
        self.borderWidth = borderWidth
    }

    public static let `default` = FeedbackStyle()
}

enum FeedbackCenterPage: Hashable {
    case activity
    case mine
    case roadmap
    case releases
    case diagnostics
    case identity
}

enum FeedbackCenterSheet: Identifiable {
    case kinds
    case composer(FeedbackKind)
    case feedback(String)
    case developerPost(String)

    var id: String {
        switch self {
        case .kinds: "kinds"
        case let .composer(kind): "composer-\(kind.rawValue)"
        case let .feedback(id): "feedback-\(id)"
        case let .developerPost(id): "post-\(id)"
        }
    }
}

enum FK {
    static func text(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .module)
    }

    static func kind(_ kind: FeedbackKind) -> String {
        switch kind {
        case .bug: text("feedbackkit.kind.bug")
        case .suggestion: text("feedbackkit.kind.suggestion")
        case .praise: text("feedbackkit.kind.praise")
        case .conversation: text("feedbackkit.kind.conversation")
        }
    }

    static func status(_ status: FeedbackStatus) -> String {
        switch status {
        case .open: text("feedbackkit.status.open")
        case .resolved: text("feedbackkit.status.resolved")
        case .closed: text("feedbackkit.status.closed")
        }
    }

    static func stage(_ stage: RoadmapStage) -> String {
        switch stage {
        case .urgent: text("feedbackkit.stage.urgent")
        case .later: text("feedbackkit.stage.later")
        case .undecided: text("feedbackkit.stage.undecided")
        }
    }
}

struct FeedbackBorder: ViewModifier {
    let style: FeedbackStyle

    func body(content: Content) -> some View {
        content.overlay {
            FeedbackComponentShape(cornerRadius: style.cardCornerRadius)
                .stroke(Color.secondary.opacity(0.22), style: StrokeStyle(lineWidth: style.borderWidth, dash: [12, 9]))
        }
    }
}

struct FeedbackComponentShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        if cornerRadius > 0 {
            RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)
        } else {
            Rectangle().path(in: rect)
        }
    }
}

extension View {
    func feedbackBorder(_ style: FeedbackStyle) -> some View { modifier(FeedbackBorder(style: style)) }

    @ViewBuilder
    func feedbackInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

struct FeedbackCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(FK.text("feedbackkit.close"))
    }
}

struct FeedbackErrorView: View {
    let error: Error
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(FK.text("feedbackkit.error.title"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button(FK.text("feedbackkit.retry"), action: retry)
        }
    }
}

extension Date {
    var feedbackRelativeText: String {
        formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}
