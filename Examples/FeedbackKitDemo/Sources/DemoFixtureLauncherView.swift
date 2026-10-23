import FeedbackKitCore
import FeedbackKitUI
import SwiftUI

struct DemoFixtureLauncherView: View {
    @State private var selectedScenario = DemoScenario.healthy
    @State private var presentation: DemoClientPresentation?
    @State private var campaignPresentation: DemoClientPresentation?

    var body: some View {
        Form {
            Section("Scenario") {
                Picker("Server behavior", selection: $selectedScenario) {
                    ForEach(DemoScenario.allCases) { scenario in
                        Text(scenario.title).tag(scenario)
                    }
                }

                Text(selectedScenario.explanation)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(action: openFeedbackCenter) {
                    DemoFullWidthButtonLabel(
                        title: "Open FeedbackKit",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("demo.fixture.open")

                Button(action: openCampaign) {
                    DemoFullWidthButtonLabel(
                        title: "Open campaign sheet",
                        systemImage: "list.clipboard"
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("demo.fixture.campaign.open")
            }
        }
        .navigationTitle("Fixture mode")
        .fullScreenCover(item: $presentation) { presentation in
            FeedbackCenterView(
                client: presentation.client,
                updateChecker: showsUpdateReminder ? DemoFixtureUpdateChecker() : nil,
                updateSheetLayout: usesCompactUpdateLayout ? FeedbackAppUpdateSheetLayout { content in
                    DemoCompactUpdateLayout(content: content)
                } : nil
            )
        }
        .sheet(item: $campaignPresentation) { presentation in
            FeedbackCampaignSheet(
                campaignID: DemoFixturePayloads.campaignID,
                client: presentation.client
            )
        }
    }

    private func openFeedbackCenter() {
        presentation = DemoClientPresentation(
            client: DemoClientFactory.fixture(scenario: selectedScenario)
        )
    }

    private func openCampaign() {
        campaignPresentation = DemoClientPresentation(
            client: DemoClientFactory.fixture(scenario: selectedScenario)
        )
    }

    private var showsUpdateReminder: Bool {
        ProcessInfo.processInfo.arguments.contains("-DemoUpdateReminder")
    }

    private var usesCompactUpdateLayout: Bool {
        ProcessInfo.processInfo.arguments.contains("-DemoCompactUpdateLayout")
    }
}

private struct DemoFixtureUpdateChecker: FeedbackAppUpdateChecking {
    func availableUpdate() async throws -> FeedbackAppUpdate? {
        FeedbackAppUpdate(
            currentVersion: "2.3.8",
            latestVersion: "2.3.9",
            url: URL(string: "https://apps.apple.com/app/id6755513897")!
        )
    }
}

private struct DemoCompactUpdateLayout: View {
    let content: FeedbackAppUpdateSheetLayout.Content
    @State private var contentHeight: CGFloat = 1

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(content.title)
                    .font(.headline)
                Text(content.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                content.details
                content.actions
            }
            .padding(16)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                contentHeight = height
            }
            // Measure before filling, so tests compare the presentation's actual
            // frame with the content height requested by the host layout.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .contain)
                .accessibilityValue(String(Int(contentHeight.rounded())))
        }
        .presentationDetents([.height(contentHeight)])
        .accessibilityElement(children: .contain)
    }
}
