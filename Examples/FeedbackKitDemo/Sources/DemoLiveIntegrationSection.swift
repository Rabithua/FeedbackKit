import FeedbackKitCore
import SwiftUI

struct DemoLiveIntegrationSection: View {
    let integration: FeedbackIntegrationSummary
    let action: () -> Void

    var body: some View {
        Section("Verified Product") {
            LabeledContent("Name", value: integration.product.name)
            LabeledContent("Slug", value: integration.product.slug)
            LabeledContent("Diagnostics", value: diagnosticsLabel)

            Button(action: action) {
                DemoFullWidthButtonLabel(
                    title: "Open FeedbackKit",
                    systemImage: "bubble.left.and.bubble.right"
                )
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var diagnosticsLabel: String {
        switch integration.diagnostics {
        case .disabled:
            "Disabled"
        case let .providerMissing(maxBytes):
            "Provider missing (\(maxBytes) bytes)"
        case let .unsupportedSchema(versions):
            "Unsupported schemas: \(versions.map(String.init).joined(separator: ", "))"
        case let .ready(maxBytes):
            "Ready (\(maxBytes) bytes)"
        }
    }
}
