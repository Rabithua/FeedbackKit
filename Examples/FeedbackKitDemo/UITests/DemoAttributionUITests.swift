import XCTest

@MainActor
final class DemoAttributionUITests: XCTestCase {
    func testAttributionIsHorizontallyCentered() {
        let app = launchFixture()
        defer { app.terminate() }

        let attribution = revealAttribution(in: app)

        XCTAssertEqual(attribution.label, "Powered by FeedKit.cn")
        XCTAssertEqual(
            attribution.frame.midX,
            app.frame.midX,
            accuracy: 1,
            "The attribution must stay centered in the FeedbackKit page."
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Centered FeedbackKit attribution"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testVisibleOuterCornersOpenFeedKitWebsite() {
        for offset in [
            CGVector(dx: 0.02, dy: 0.1),
            CGVector(dx: 0.98, dy: 0.9),
        ] {
            let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
            safari.terminate()

            let app = launchFixture()
            let attribution = revealAttribution(in: app)
            attribution.coordinate(withNormalizedOffset: offset).tap()

            XCTAssertEqual(
                safari.wait(for: .runningForeground, timeout: 5),
                true,
                "The visible attribution corner must open the FeedKit website."
            )
            app.terminate()
            safari.terminate()
        }
    }

    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Fixture mode"].tap()

        let openButton = app.buttons["demo.fixture.open"]
        for _ in 0 ..< 5 where openButton.exists == false {
            app.swipeUp()
        }
        XCTAssertTrue(openButton.waitForExistence(timeout: 3))
        openButton.tap()
        return app
    }

    private func revealAttribution(in app: XCUIApplication) -> XCUIElement {
        let hub = app.scrollViews["developerCommunity.hub"]
        XCTAssertTrue(hub.waitForExistence(timeout: 3))

        let attribution = app.buttons["developerCommunity.attribution"]
        for _ in 0 ..< 8 where attribution.isHittable == false {
            hub.swipeUp()
        }
        XCTAssertTrue(attribution.isHittable)
        return attribution
    }
}
