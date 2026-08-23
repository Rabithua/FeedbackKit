import FeedbackKitCore
import SwiftUI

struct FeedbackIdentityView: View {
    @State private var model: FeedbackIdentityModel
    let visitor: FeedbackVisitor?
    let deleted: () -> Void
    @State private var confirm = false
    @State private var finalConfirm = false
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.feedbackLocalization) private var localization

    init(
        client: FeedbackClient,
        visitor: FeedbackVisitor?,
        productSlug: String?,
        deleted: @escaping () -> Void
    ) {
        _model = State(initialValue: FeedbackIdentityModel(
            client: client,
            productSlug: productSlug
        ))
        self.visitor = visitor
        self.deleted = deleted
    }

    var body: some View {
        Form {
            Section(localization.text("feedbackkit.identity.yours")) {
                LabeledContent(
                    localization.text("feedbackkit.identity.code"),
                    value: visitor?.displayCode ?? "—"
                )
                Text(localization.text("feedbackkit.identity.independent"))
                    .foregroundStyle(.secondary)
            }

            Section(localization.text("feedbackkit.identity.data")) {
                Text(localization.text("feedbackkit.identity.delete.explanation"))
                Button(localization.text("feedbackkit.identity.delete"), role: .destructive) {
                    haptics.trigger(.warning)
                    confirm = true
                }
                .disabled(model.isDeleting)
            }

            if let error = model.error {
                Text(localization.errorMessage(for: error))
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle(localization.text("feedbackkit.identity.title"))
        .feedbackInlineNavigationTitle()
        .alert(localization.text("feedbackkit.identity.delete"), isPresented: $confirm) {
            Button(localization.text("feedbackkit.continue"), role: .destructive) {
                finalConfirm = true
            }
            Button(localization.text("feedbackkit.cancel"), role: .cancel) {}
        }
        .alert(localization.text("feedbackkit.identity.delete.final"), isPresented: $finalConfirm) {
            Button(localization.text("feedbackkit.identity.delete"), role: .destructive) {
                Task { await remove() }
            }
            Button(localization.text("feedbackkit.cancel"), role: .cancel) {}
        }
    }

    private func remove() async {
        if await model.remove() {
            haptics.trigger(.success)
            deleted()
        } else if Task.isCancelled == false {
            haptics.trigger(.error)
        }
    }
}
