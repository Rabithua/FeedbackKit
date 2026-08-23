import SwiftUI

struct DemoLiveVerificationSection: View {
    let clientAvailable: Bool
    let isVerifying: Bool
    let error: String?
    let action: () -> Void

    var body: some View {
        Section {
            Button(action: action) {
                DemoFullWidthButtonLabel(
                    title: "Verify integration",
                    systemImage: "checkmark.shield",
                    showsProgress: isVerifying
                )
            }
            .disabled(clientAvailable == false || isVerifying)
            .accessibilityIdentifier("demo.live.verify")

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("demo.live.verification.error")
            }
        } footer: {
            Text("Verification creates or reuses the anonymous visitor identity used by FeedbackKit.")
        }
    }
}
