import FeedbackKitCore
import FeedbackKitDiagnostics
import SwiftUI

public struct FeedbackCenterView: View {
    @State private var model: FeedbackCenterModel
    private let routeHandler: any FeedbackRouteHandler
    private let style: FeedbackStyle
    private let haptics: FeedbackHaptics
    private let initialRoute: String?
    @State private var didOpenInitialRoute = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    public init(
        client: FeedbackClient,
        routeHandler: any FeedbackRouteHandler = IgnoreFeedbackRouteHandler(),
        style: FeedbackStyle = .default,
        haptics: FeedbackHaptics = .none,
        initialRoute: String? = nil
    ) {
        _model = State(initialValue: FeedbackCenterModel(client: client))
        self.routeHandler = routeHandler
        self.style = style
        self.haptics = haptics
        self.initialRoute = initialRoute
    }

    public var body: some View {
        NavigationStack(path: $model.path) {
            Group {
                if let bootstrap = model.bootstrap {
                    FeedbackHubView(
                        bootstrap: bootstrap,
                        style: style,
                        openPage: {
                            haptics.trigger(.navigation)
                            model.path.append($0)
                        },
                        openSheet: {
                            haptics.trigger(.navigation)
                            model.sheet = $0
                        },
                        vote: { id, target in
                            haptics.trigger(.selection)
                            Task {
                                if await model.updateVote(feedbackID: id, target: target) == false {
                                    haptics.trigger(.error)
                                }
                            }
                        },
                        refresh: { await model.load(locale: locale, force: true) },
                        dismiss: { dismiss() },
                        activatePost: activatePost
                    )
                } else if model.isLoading {
                    FeedbackSkeletonView(layout: .hub, style: style)
                } else if let error = model.error {
                    FeedbackErrorView(error: error) { Task { await model.load(locale: locale, force: true) } }
                }
            }
            .background(FeedbackSystemBackground())
            .navigationDestination(for: FeedbackCenterPage.self) { page in
                destination(page)
            }
        }
        .task(id: locale.identifier) {
            await model.load(locale: locale, force: true)
            if didOpenInitialRoute == false, let initialRoute {
                didOpenInitialRoute = true
                _ = openPackageRoute(initialRoute)
            }
        }
        .sheet(item: $model.sheet) { sheet in
            FeedbackSheetHost(
                sheet: sheet,
                model: model,
                routeHandler: routeHandler,
                style: style
            )
        }
        .environment(\.feedbackHaptics, haptics)
        .tint(.accentColor)
    }

    @ViewBuilder
    private func destination(_ page: FeedbackCenterPage) -> some View {
        switch page {
        case .activity:
            FeedbackActivityListView(
                client: model.client,
                style: style,
                open: {
                    haptics.trigger(.navigation)
                    model.sheet = $0
                },
                activatePost: activatePost
            )
        case .mine:
            MyFeedbackView(client: model.client, style: style) {
                haptics.trigger(.navigation)
                model.sheet = .feedback($0)
            }
        case .roadmap:
            FeedbackRoadmapView(items: model.bootstrap?.roadmap ?? [], style: style)
        case .releases:
            FeedbackReleaseView(client: model.client, initial: model.bootstrap?.changelog ?? [], style: style)
        case .diagnostics:
            if let diagnostics = model.client.diagnosticsProvider as? FeedbackDiagnostics {
                FeedbackDiagnosticsView(diagnostics: diagnostics, style: style)
            } else {
                ContentUnavailableView(FK.text("feedbackkit.diagnostics.unavailable"), systemImage: "doc.text.magnifyingglass")
            }
        case .identity:
            FeedbackIdentityView(
                client: model.client,
                visitor: model.bootstrap?.visitor,
                productSlug: model.bootstrap?.product.slug
            ) {
                dismiss()
            }
        }
    }

    private func activatePost(_ action: FeedbackDeveloperPostAction) {
        switch action.type {
        case .externalURL:
            guard let url = URL(string: action.target), url.scheme?.lowercased() == "https" else {
                haptics.trigger(.error)
                return
            }
            haptics.trigger(.action)
            openURL(url)
        case .appRoute:
            if model.openPackageRoute(action.target) || routeHandler.openFeedbackAppRoute(action.target) {
                haptics.trigger(.navigation)
            } else {
                haptics.trigger(.error)
            }
        }
    }

    private func openPackageRoute(_ route: String) -> Bool {
        model.openPackageRoute(route)
    }
}

public struct FeedbackCenterToolbarButton: View {
    private let action: () -> Void
    private let haptics: FeedbackHaptics

    public init(haptics: FeedbackHaptics = .none, action: @escaping () -> Void) {
        self.haptics = haptics
        self.action = action
    }

    public var body: some View {
        Button {
            haptics.trigger(.navigation)
            action()
        } label: {
            Image(systemName: "bubble.left.and.bubble.right")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FK.text("feedbackkit.open"))
        .accessibilityIdentifier("developerCommunity.toolbarButton")
    }
}
