import FeedbackKitCore
import FeedbackKitUI
import SwiftUI

struct DemoFixtureLauncherView: View {
    @State private var selectedScenario = DemoScenario.healthy
    @State private var presentation: DemoClientPresentation?

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
            }
        }
        .navigationTitle("Fixture mode")
        .fullScreenCover(item: $presentation) { presentation in
            FeedbackCenterView(client: presentation.client)
        }
    }

    private func openFeedbackCenter() {
        presentation = DemoClientPresentation(
            client: DemoClientFactory.fixture(scenario: selectedScenario)
        )
    }
}
