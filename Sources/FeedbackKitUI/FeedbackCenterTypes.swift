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
    static let skeletonForeground = Color.secondary.opacity(0.28)
    static let headerTransitionDuration = 0.28
}

public enum FeedbackHapticEvent: Sendable {
    case navigation
    case selection
    case action
    case success
    case warning
    case error
}

public struct FeedbackHaptics: Sendable {
    private let handler: @MainActor @Sendable (FeedbackHapticEvent) -> Void

    public init(_ handler: @escaping @MainActor @Sendable (FeedbackHapticEvent) -> Void) {
        self.handler = handler
    }

    @MainActor
    public func trigger(_ event: FeedbackHapticEvent) {
        handler(event)
    }

    public static let none = FeedbackHaptics { _ in }
}

private struct FeedbackHapticsKey: EnvironmentKey {
    static let defaultValue = FeedbackHaptics.none
}

extension EnvironmentValues {
    var feedbackHaptics: FeedbackHaptics {
        get { self[FeedbackHapticsKey.self] }
        set { self[FeedbackHapticsKey.self] = newValue }
    }
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
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        Button(action: close) {
            Label(localization.text("feedbackkit.close"), systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.system(size: 18, weight: .bold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("developerCommunity.close")
    }

    private func close() {
        haptics.trigger(.navigation)
        action()
    }
}

struct FeedbackErrorView: View {
    let error: Error
    let retry: () -> Void
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    var body: some View {
        ContentUnavailableView {
            Label(localization.text("feedbackkit.error.title"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button(localization.text("feedbackkit.retry")) {
                haptics.trigger(.action)
                retry()
            }
        }
    }
}

extension Date {
    func feedbackRelativeText(locale: Locale) -> String {
        formatted(
            .relative(presentation: .named, unitsStyle: .wide)
                .locale(locale)
        )
    }
}
