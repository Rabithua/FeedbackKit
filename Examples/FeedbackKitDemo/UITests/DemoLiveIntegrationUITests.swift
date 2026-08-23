import XCTest

@MainActor
final class DemoLiveIntegrationUITests: XCTestCase {
    func testConfiguredProductVerifies() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        app.buttons["Live mode"].tap()
        guard app.staticTexts["Product Key loaded"].waitForExistence(timeout: 3) else {
            throw XCTSkip("Set FEEDBACK_PRODUCT_KEY in Config.local.xcconfig to exercise Live mode.")
        }

        let verifyButton = app.buttons["demo.live.verify"]
        XCTAssertTrue(verifyButton.waitForExistence(timeout: 3))
        verifyButton.tap()

        let openButton = app.buttons["demo.live.open"]
        guard openButton.waitForExistence(timeout: 15) else {
            let error = app.staticTexts["demo.live.verification.error"]
            XCTFail(
                error.exists
                    ? "Live verification failed: \(error.label)"
                    : "Live verification did not finish within 15 seconds."
            )
            return
        }

        XCTAssertTrue(openButton.isHittable)
    }
}
