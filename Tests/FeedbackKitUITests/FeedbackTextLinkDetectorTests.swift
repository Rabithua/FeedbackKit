import Foundation
import Testing
@testable import FeedbackKitUI

struct FeedbackTextLinkDetectorTests {
    @Test func detectsSecureLinksWithoutConsumingChinesePunctuation() throws {
        let text = "详情：https://example.com/path?a=1。继续阅读。"

        let link = try #require(FeedbackTextLinkDetector.links(in: text).first)

        #expect(link.url.absoluteString == "https://example.com/path?a=1")
        #expect((text as NSString).substring(with: link.range) == "https://example.com/path?a=1")
    }

    @Test(
        arguments: [
            "www.example.com/updates",
            "example.com/updates",
        ]
    )
    func normalizesSchemeLessWebLinksToHTTPS(_ source: String) throws {
        let link = try #require(FeedbackTextLinkDetector.links(in: source).first)

        #expect(link.url.absoluteString == "https://\(source)")
    }

    @Test func detectsMultipleLinksInSourceOrder() {
        let text = "先看 https://example.com/one，再看 https://example.org/two。"

        let links = FeedbackTextLinkDetector.links(in: text)

        #expect(links.map(\.url.absoluteString) == [
            "https://example.com/one",
            "https://example.org/two",
        ])
    }

    @Test(
        arguments: [
            "http://example.com/insecure",
            "mailto:hello@example.com",
            "javascript:alert(1)",
            "file:///tmp/private.txt",
            "hello@example.com",
        ]
    )
    func rejectsUnsupportedOrInsecureLinks(_ source: String) {
        #expect(FeedbackTextLinkDetector.links(in: source).isEmpty)
    }
}
