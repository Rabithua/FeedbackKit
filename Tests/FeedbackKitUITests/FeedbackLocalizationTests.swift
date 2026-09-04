@testable import FeedbackKitUI
import FeedbackKitCore
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

    @Test(
        arguments: [
            ("en", "Feedback is temporarily unavailable. Please try again later."),
            ("zh-Hans", "反馈服务暂时不可用，请稍后再试"),
            ("zh-Hant", "回饋服務暫時無法使用，請稍後再試"),
            ("ja", "フィードバックサービスは一時的に利用できません。しばらくしてからもう一度お試しください。"),
            ("ko", "피드백 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요."),
        ]
    )
    func temporaryServiceMessageIsLocalized(
        identifier: String,
        expectedMessage: String
    ) {
        let localization = FeedbackLocalization(
            locale: Locale(identifier: identifier)
        )

        #expect(
            localization.text("feedbackkit.error.service.temporarily.unavailable")
                == expectedMessage
        )
    }

    @Test(
        arguments: [
            ("en", "Survey Response"),
            ("zh-Hans", "问卷回复"),
            ("zh-Hant", "問卷回覆"),
            ("ja", "アンケート回答"),
            ("ko", "설문 응답"),
        ]
    )
    func surveyResponseKindIsLocalized(identifier: String, expected: String) {
        let localization = FeedbackLocalization(locale: Locale(identifier: identifier))

        #expect(localization.kind(.survey) == expected)
    }

    @Test(
        arguments: [
            "feedback_feature_unavailable",
            "feedback_service_read_only",
            "feedback_storage_unavailable",
        ]
    )
    func serviceRestrictionCodesUseGenericMessage(_ code: String) {
        let localization = FeedbackLocalization(
            locale: Locale(identifier: "zh-Hans")
        )

        #expect(
            localization.errorMessage(
                for: FeedbackClientError(
                    kind: .server,
                    context: FeedbackFailureContext(
                        statusCode: 503,
                        serverCode: code
                    )
                )
            ) == "反馈服务暂时不可用，请稍后再试"
        )
        #expect(
            localization.errorMessage(
                for: FeedbackClientError(
                    kind: .server,
                    context: FeedbackFailureContext(
                        statusCode: 503,
                        serverCode: "maintenance"
                    )
                )
            ) == "FeedbackServer returned HTTP 503."
        )
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
