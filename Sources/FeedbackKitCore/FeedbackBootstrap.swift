public struct FeedbackBootstrap: Codable, Sendable {
    public let product: FeedbackProduct
    public let activity: FeedbackActivityPage
    public let roadmap: [FeedbackRoadmapItem]
    public let changelog: [FeedbackRelease]
    public let visitor: FeedbackVisitor
    public let inbox: FeedbackInboxPage

    public init(
        product: FeedbackProduct,
        activity: FeedbackActivityPage,
        roadmap: [FeedbackRoadmapItem],
        changelog: [FeedbackRelease],
        visitor: FeedbackVisitor,
        inbox: FeedbackInboxPage
    ) {
        self.product = product
        self.activity = activity
        self.roadmap = roadmap
        self.changelog = changelog
        self.visitor = visitor
        self.inbox = inbox
    }
}
