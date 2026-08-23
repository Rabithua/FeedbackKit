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
}
