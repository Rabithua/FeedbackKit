import FeedbackKitCore

actor DemoFixtureCredentialStore: FeedbackVisitorCredentialProviding {
    func credential(for productKey: String) async throws -> String {
        "demo-visitor-credential"
    }

    func deleteCredential(for productKey: String) async throws {}
}
