import XCTest

@MainActor
final class DemoHitTargetUITests: XCTestCase {
    func testVisibleOuterCornersOpenFeedbackCenter() {
        for horizontalOffset in [0.02, 0.98] {
            let app = XCUIApplication()
            app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()

            app.buttons["Fixture mode"].tap()
            let openButton = app.buttons["demo.fixture.open"]
            XCTAssertTrue(openButton.waitForExistence(timeout: 3))

            openButton.coordinate(
                withNormalizedOffset: CGVector(dx: horizontalOffset, dy: 0.1)
            ).tap()

            XCTAssertTrue(
                app.buttons["developerCommunity.close"].waitForExistence(timeout: 3),
                "The visible button corner must trigger the full-width action"
            )
            XCTAssertTrue(
                app.scrollViews["developerCommunity.hub"].waitForExistence(timeout: 3),
                "Fixture mode must complete bootstrap without configuration"
            )
            app.terminate()
        }
    }

    func testCampaignSheetValidatesPagesAndSubmitsFixture() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.buttons["Fixture mode"].tap()
        let openCampaign = app.buttons["demo.fixture.campaign.open"]
        XCTAssertTrue(openCampaign.waitForExistence(timeout: 3))
        openCampaign.tap()

        XCTAssertTrue(app.staticTexts["Shape FeedbackKit"].waitForExistence(timeout: 3))
        let primary = app.buttons["developerCommunity.campaign.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 3))
        primary.tap()
        XCTAssertTrue(
            app.staticTexts["Answer this question to continue."]
                .waitForExistence(timeout: 2)
        )

        app.buttons["4"].tap()
        app.buttons["Yes"].tap()
        primary.tap()
        XCTAssertTrue(app.staticTexts["Which areas should we improve?"].waitForExistence(timeout: 2))

        app.buttons["Campaigns"].tap()
        primary.tap()
        XCTAssertTrue(
            openCampaign.waitForExistence(timeout: 3),
            "A successful response should dismiss the host-presented campaign sheet"
        )
    }

    func testCampaignDeveloperPostActionOpensFromVisibleCorners() {
        for horizontalOffset in [0.08, 0.92] {
            let app = XCUIApplication()
            app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()

            app.buttons["Fixture mode"].tap()
            let openButton = app.buttons["demo.fixture.open"]
            XCTAssertTrue(openButton.waitForExistence(timeout: 3))
            openButton.tap()

            let campaignAction = app.buttons["Shape FeedbackKit"]
            XCTAssertTrue(campaignAction.waitForExistence(timeout: 3))
            campaignAction.coordinate(
                withNormalizedOffset: CGVector(dx: horizontalOffset, dy: 0.1)
            ).tap()

            XCTAssertTrue(
                app.buttons["developerCommunity.campaign.primary"].waitForExistence(timeout: 3),
                "The Campaign CTA's visible edge must open the Campaign sheet"
            )
            app.terminate()
        }
    }
}
