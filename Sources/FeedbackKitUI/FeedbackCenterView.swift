import FeedbackKitCore
import FeedbackKitDiagnostics
import SwiftUI

public struct FeedbackCenterView: View {
    @State private var model: FeedbackCenterModel
    private let routeHandler: any FeedbackRouteHandler
    private let style: FeedbackStyle
    private let haptics: FeedbackHaptics
    private let initialRoute: String?
    private let languagePolicy: FeedbackLanguagePolicy
    @State private var didOpenInitialRoute = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var hostLocale
    @Environment(\.openURL) private var openURL

    public init(
        client: FeedbackClient,
        routeHandler: any FeedbackRouteHandler = IgnoreFeedbackRouteHandler(),
        style: FeedbackStyle = .default,
        haptics: FeedbackHaptics = .none,
        initialRoute: String? = nil,
        languagePolicy: FeedbackLanguagePolicy = .followHost
    ) {
        _model = State(initialValue: FeedbackCenterModel(client: client))
        self.routeHandler = routeHandler
        self.style = style
        self.haptics = haptics
        self.initialRoute = initialRoute
        self.languagePolicy = languagePolicy
    }

    public var body: some View {
        NavigationStack(path: $model.path) {
            VStack(spacing: 0) {
                FeedbackCenterHeader(
                    showsMenu: model.bootstrap != nil,
                    style: style,
                    openPage: openPage,
                    dismiss: dismissCenter
                )

                Group {
                    if let bootstrap = model.bootstrap {
                        FeedbackHubView(
                            bootstrap: bootstrap,
                            style: style,
                            openPage: openPage,
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
                            activatePost: activatePost
                        )
                    } else if model.isLoading {
                        FeedbackSkeletonView(layout: .hub, style: style)
                    } else if let error = model.error {
                        FeedbackErrorView(error: error) { Task { await model.load(locale: locale, force: true) } }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .environment(\.locale, locale)
        .environment(\.feedbackLocalization, FeedbackLocalization(locale: locale))
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
                ContentUnavailableView(feedbackLocalization.text("feedbackkit.diagnostics.unavailable"), systemImage: "doc.text.magnifyingglass")
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

    private func openPage(_ page: FeedbackCenterPage) {
        haptics.trigger(.navigation)
        model.path.append(page)
    }

    private func dismissCenter() {
        dismiss()
    }

    private var locale: Locale {
        languagePolicy.resolve(hostLocale: hostLocale)
    }

    private var feedbackLocalization: FeedbackLocalization {
        FeedbackLocalization(locale: locale)
    }
}

public struct FeedbackCenterToolbarButton: View {
    private let action: () -> Void
    private let haptics: FeedbackHaptics
    private let languagePolicy: FeedbackLanguagePolicy
    @Environment(\.locale) private var locale

    public init(
        haptics: FeedbackHaptics = .none,
        languagePolicy: FeedbackLanguagePolicy = .followHost,
        action: @escaping () -> Void
    ) {
        self.haptics = haptics
        self.languagePolicy = languagePolicy
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
        .accessibilityLabel(
            FeedbackLocalization(
                locale: languagePolicy.resolve(hostLocale: locale)
            ).text("feedbackkit.open")
        )
        .accessibilityIdentifier("developerCommunity.toolbarButton")
    }
}
