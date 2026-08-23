import SwiftUI

struct DemoLiveConfigurationSection: View {
    let error: String?

    var body: some View {
        Section("Configuration") {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text("Copy Configuration/Config.local.example.xcconfig to Config.local.xcconfig and set FEEDBACK_PRODUCT_KEY.")
                    .foregroundStyle(.secondary)
            } else {
                Label("Product Key loaded", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
    }
}
