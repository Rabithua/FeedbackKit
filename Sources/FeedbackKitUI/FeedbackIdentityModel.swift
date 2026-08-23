import FeedbackKitCore
import Observation

@MainActor
@Observable
final class FeedbackIdentityModel {
    var isDeleting = false
    var error: Error?
    let client: FeedbackClient
    let productSlug: String?

    init(client: FeedbackClient, productSlug: String?) {
        self.client = client
        self.productSlug = productSlug
    }

    func remove() async -> Bool {
        guard isDeleting == false else { return false }
        isDeleting = true
        error = nil
        defer { isDeleting = false }
        do {
            try await client.deleteVisitor()
            if let productSlug {
                try? await FeedbackDraftStore().remove(productSlug: productSlug)
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            self.error = error
            return false
        }
    }
}
