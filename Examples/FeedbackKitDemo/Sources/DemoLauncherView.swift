import SwiftUI

struct DemoLauncherView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        DemoFixtureLauncherView()
                    } label: {
                        Label("Fixture mode", systemImage: "shippingbox")
                    }

                    NavigationLink {
                        DemoLiveLauncherView()
                    } label: {
                        Label("Live mode", systemImage: "network")
                    }
                } header: {
                    Text("Choose a backend")
                } footer: {
                    Text("Fixture mode works immediately. Live mode verifies a real Product before opening FeedbackKit.")
                }
            }
            .navigationTitle("FeedbackKit Demo")
        }
    }
}
