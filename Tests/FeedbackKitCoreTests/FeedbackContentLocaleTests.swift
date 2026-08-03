@testable import FeedbackKitCore
import Foundation
import Testing

struct FeedbackContentLocaleTests {
    @Test(
        arguments: [
            ("zh_CN", "zh-Hans-CN"),
            ("zh_SG", "zh-Hans-SG"),
            ("zh_TW", "zh-Hant-TW"),
            ("zh_HK", "zh-Hant-HK"),
            ("zh-hans-cn", "zh-Hans-CN"),
            ("zh-Hans-CN-u-ca-chinese-hc-h23-nu-hanidec", "zh-Hans-CN"),
            ("en-US-u-ca-gregory-hc-h23-nu-latn", "en-US"),
        ]
    )
    func canonicalizesContentLocale(_ identifier: String, expected: String) {
        #expect(Locale(identifier: identifier).feedbackContentIdentifier == expected)
    }

    @Test func defaultMetadataUsesContentLocale() async {
        let context = await DefaultFeedbackAppMetadataProvider().clientContext(
            locale: Locale(identifier: "zh_CN")
        )
        #expect(context.locale == "zh-Hans-CN")
    }
}
