@testable import FeedbackKitUI
import Foundation
import Testing

struct FeedbackLocalizationTests {
    @Test(
        arguments: [
            ("en", "Build Together"),
            ("zh-Hans", "与开发者共建"),
            ("zh_CN", "与开发者共建"),
            ("zh-Hant", "與開發者共建"),
            ("ja", "開発者と一緒につくる"),
            ("ko", "개발자와 함께 만들기"),
        ]
    )
    func explicitLocaleSelectsMatchingPackageResources(
        identifier: String,
        expectedTitle: String
    ) {
        let localization = FeedbackLocalization(
            locale: Locale(identifier: identifier)
        )

        #expect(localization.text("feedbackkit.center.title") == expectedTitle)
    }

    @Test func languagePolicyCanFollowOrOverrideHostLocale() {
        let host = Locale(identifier: "en_US")
        let fixed = Locale(identifier: "zh-Hans")

        #expect(
            FeedbackLanguagePolicy.followHost.resolve(hostLocale: host)
                == host
        )
        #expect(
            FeedbackLanguagePolicy.fixed(fixed).resolve(hostLocale: host)
                == fixed
        )
    }
}
