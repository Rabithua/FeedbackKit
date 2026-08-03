import FeedbackKitCore
import FeedbackKitDiagnostics
import SwiftUI

public struct FeedbackCenterView: View {
    @State private var model: FeedbackCenterModel
    private let routeHandler: any FeedbackRouteHandler
    private let style: FeedbackStyle
    private let initialRoute: String?
    @State private var didOpenInitialRoute = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    public init(
        client: FeedbackClient,
        routeHandler: any FeedbackRouteHandler = IgnoreFeedbackRouteHandler(),
        style: FeedbackStyle = .default,
        initialRoute: String? = nil
    ) {
        _model = State(initialValue: FeedbackCenterModel(client: client))
        self.routeHandler = routeHandler
        self.style = style
        self.initialRoute = initialRoute
    }

    public var body: some View {
        NavigationStack(path: $model.path) {
            Group {
                if let bootstrap = model.bootstrap {
                    FeedbackHubView(
                        bootstrap: bootstrap,
                        style: style,
                        openPage: { model.path.append($0) },
                        openSheet: { model.sheet = $0 },
                        vote: { id, target in Task { await model.updateVote(feedbackID: id, target: target) } },
                        refresh: { await model.load(locale: locale, force: true) },
                        dismiss: { dismiss() },
                        activatePost: activatePost
                    )
                } else if model.isLoading {
                    ProgressView(FK.text("feedbackkit.loading"))
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
        .tint(.accentColor)
    }

    @ViewBuilder
    private func destination(_ page: FeedbackCenterPage) -> some View {
        switch page {
        case .activity:
            FeedbackActivityListView(
                client: model.client,
                style: style,
                open: { model.sheet = $0 },
                activatePost: activatePost
            )
        case .mine:
            MyFeedbackView(client: model.client, style: style) { model.sheet = .feedback($0) }
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
            guard let url = URL(string: action.target), url.scheme?.lowercased() == "https" else { return }
            openURL(url)
        case .appRoute:
            _ = model.openPackageRoute(action.target) || routeHandler.openFeedbackAppRoute(action.target)
        }
    }

    private func openPackageRoute(_ route: String) -> Bool {
        model.openPackageRoute(route)
    }
}

public struct FeedbackCenterToolbarButton: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "bubble.left.and.bubble.right")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FK.text("feedbackkit.open"))
        .accessibilityIdentifier("developerCommunity.toolbarButton")
    }
}
