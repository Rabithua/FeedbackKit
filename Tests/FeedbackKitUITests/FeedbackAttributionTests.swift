@testable import FeedbackKitUI
import Foundation
import Testing

struct FeedbackAttributionTests {
    @MainActor
    @Test func destinationUsesTheCanonicalWebsite() {
        #expect(FeedbackAttributionLink.destination.absoluteString == "https://feedkit.cn/")
    }

    @Test(
        arguments: [
            ("en", "Powered by FeedKit.cn", "Opens the FeedKit website"),
            ("zh-Hans", "由 FeedKit.cn 提供支持", "打开 FeedKit 网站"),
            ("zh-Hant", "由 FeedKit.cn 提供支援", "開啟 FeedKit 網站"),
            ("ja", "FeedKit.cn により提供", "FeedKit のウェブサイトを開きます"),
            ("ko", "FeedKit.cn 제공", "FeedKit 웹사이트 열기"),
        ]
    )
    func accessibilityCopyIsLocalized(
        identifier: String,
        expectedLabel: String,
        expectedHint: String
    ) {
        let localization = FeedbackLocalization(locale: Locale(identifier: identifier))

        #expect(localization.text("feedbackkit.attribution.label") == expectedLabel)
        #expect(localization.text("feedbackkit.attribution.hint") == expectedHint)
    }
}
