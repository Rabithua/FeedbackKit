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

    func testComposerShowsCenteredSubmissionStatesAndDismissesAfterSuccess() {
        let app = openComposer()
        defer { app.terminate() }
        let form = app.scrollViews["developerCommunity.composer.form"]
        let header = app.staticTexts["Report a Bug"].firstMatch
        let body = app.textViews["developerCommunity.composer.body"]

        XCTAssertTrue(form.waitForExistence(timeout: 3))
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(
            header.frame.minY,
            app.frame.minY + app.frame.height * 0.3,
            "The composer should initially preserve its half-height presentation"
        )
        let contentFrame = form.frame
        attachScreenshot("Composer — half-height form", in: app)

        enterFeedback("Checking centered submission feedback in the composer.", in: body)
        let submit = revealComposerSubmit(in: app)
        submit.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.92)).tap()

        let sending = app.staticTexts["developerCommunity.composer.submitting"]
        XCTAssertTrue(sending.waitForExistence(timeout: 3))
        let sendingFrame = sending.frame
        XCTAssertFalse(form.exists, "The form must leave the accessibility tree while sending")
        XCTAssertFalse(submit.isHittable, "The hidden sending button must not accept another tap")
        assertCenteredStatus(sendingFrame, in: contentFrame)
        attachScreenshot("Composer — centered sending state", in: app)

        let sent = app.staticTexts["developerCommunity.composer.sent"]
        XCTAssertTrue(sent.waitForExistence(timeout: 3))
        assertCenteredStatus(sent.frame, in: contentFrame)
        attachScreenshot("Composer — centered sent state", in: app)
        XCTAssertTrue(
            header.waitForNonExistence(timeout: 3),
            "The composer should dismiss after displaying its successful result"
        )
        XCTAssertTrue(app.buttons["developerCommunity.newFeedback"].isHittable)
    }

    func testComposerButtonCornersAndEdgesRestoreFormAfterFailure() {
        let app = openComposer(scenario: "Submission validation")
        defer { app.terminate() }
        let form = app.scrollViews["developerCommunity.composer.form"]
        let body = app.textViews["developerCommunity.composer.body"]
        let feedback = "Keep this feedback after every failed submission."
        enterFeedback(feedback, in: body)

        let sending = app.staticTexts["developerCommunity.composer.submitting"]
        let error = app.staticTexts["developerCommunity.composer.error"]
        let visibleOffsets = [
            CGVector(dx: 0.02, dy: 0.08),
            CGVector(dx: 0.98, dy: 0.08),
            CGVector(dx: 0.02, dy: 0.92),
            CGVector(dx: 0.98, dy: 0.92),
            CGVector(dx: 0.5, dy: 0.04),
            CGVector(dx: 0.5, dy: 0.96),
            CGVector(dx: 0.01, dy: 0.5),
            CGVector(dx: 0.99, dy: 0.5),
        ]

        for offset in visibleOffsets {
            let submit = revealComposerSubmit(in: app)
            submit.coordinate(withNormalizedOffset: offset).tap()

            XCTAssertTrue(
                sending.waitForExistence(timeout: 3),
                "Each visible corner or edge must start a new submission: \(offset)"
            )
            XCTAssertFalse(error.exists, "A retry must clear the previous failure while sending")
            XCTAssertFalse(form.exists, "Pending submissions must hide the original form")
            XCTAssertFalse(submit.isHittable)
            XCTAssertTrue(error.waitForExistence(timeout: 3))
            XCTAssertTrue(form.exists, "A failed submission must restore the original form")
            XCTAssertTrue(submit.isEnabled, "A failed submission must allow another attempt")
            XCTAssertEqual(body.value as? String, feedback)
        }

        _ = revealComposerSubmit(in: app)
        XCTAssertTrue(form.frame.contains(error.frame))
        attachScreenshot("Composer — restored form and retry", in: app)
    }

    func testDefaultUpdateReminderKeepsSDKHeightAndContinuesAtComposerHeight() {
        let app = openUpdateReminder()
        defer { app.terminate() }
        let title = app.staticTexts["Try updating first"]
        waitForTopEdge(of: title, within: (app.frame.height * 0.45)...(app.frame.height * 0.7))
        attachScreenshot("Update — default detents", in: app)
        continueFromUpdateReminder(in: app)
    }

    func testDefaultAccessibilityUpdateReminderUsesLargeHeight() {
        let app = openUpdateReminder(accessibilitySize: true)
        defer { app.terminate() }
        let title = app.staticTexts["Try updating first"]
        waitForTopEdge(of: title, within: 0...(app.frame.height * 0.2))
        attachScreenshot("Update — default accessibility detent", in: app)
        continueFromUpdateReminder(in: app)
    }

    func testCustomUpdateReminderUsesContentHeightAndContinuesAtComposerHeight() {
        assertCustomUpdateReminder(accessibilitySize: false)
    }

    func testCustomAccessibilityUpdateReminderRetainsHostHeight() {
        assertCustomUpdateReminder(accessibilitySize: true)
    }

    private func assertCustomUpdateReminder(accessibilitySize: Bool) {
        let app = openUpdateReminder(compact: true, accessibilitySize: accessibilitySize)
        defer { app.terminate() }
        let layout = app.otherElements["developerCommunity.update.sheet"]
        XCTAssertTrue(layout.waitForExistence(timeout: 3))
        let contentSized = NSPredicate { object, _ in
            guard let layout = object as? XCUIElement,
                  let value = layout.value as? String,
                  let measuredHeight = Double(value), measuredHeight > 1 else {
                return false
            }
            // SwiftUI may include the bottom safe area in the presented frame.
            return abs(layout.frame.height - measuredHeight) <= 40
        }
        expectation(for: contentSized, evaluatedWith: layout)
        waitForExpectations(timeout: 3)
        XCTAssertLessThan(layout.frame.height, app.frame.height * 0.8)
        // A custom layout has one host-owned detent. An upward sheet drag must
        // return to that height rather than reveal additional SDK detents.
        layout.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            )
        expectation(for: contentSized, evaluatedWith: layout)
        waitForExpectations(timeout: 3)
        attachScreenshot(
            accessibilitySize ? "Update — custom accessibility height after drag" : "Update — custom content height after drag",
            in: app
        )
        continueFromUpdateReminder(in: app)
    }

    private func openUpdateReminder(
        compact: Bool = false,
        accessibilitySize: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-DemoUpdateReminder",
            "-UIPreferredContentSizeCategoryName",
            accessibilitySize ? "UICTContentSizeCategoryAccessibilityM" : "UICTContentSizeCategoryL",
        ]
        if compact { app.launchArguments.append("-DemoCompactUpdateLayout") }
        app.launch()
        app.buttons["Fixture mode"].tap()
        let openButton = app.buttons["demo.fixture.open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 3))
        openButton.tap()
        let newFeedback = app.buttons["Say Something"]
        XCTAssertTrue(newFeedback.waitForExistence(timeout: 3))
        newFeedback.tap()
        app.buttons["Report a Bug"].tap()
        XCTAssertTrue(app.staticTexts["Try updating first"].waitForExistence(timeout: 3))
        return app
    }

    private func continueFromUpdateReminder(in app: XCUIApplication) {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Continue")).firstMatch.tap()
        let composer = app.scrollViews["developerCommunity.composer.form"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Try updating first"].exists)
        let header = app.staticTexts["Report a Bug"].firstMatch
        waitForTopEdge(of: header, within: (app.frame.height * 0.3)...(app.frame.height * 0.65))
        attachScreenshot("Update — continued in medium composer", in: app)
    }

    private func waitForTopEdge(of element: XCUIElement, within range: ClosedRange<CGFloat>) {
        let positioned = NSPredicate { object, _ in
            guard let element = object as? XCUIElement, element.exists else { return false }
            return range.contains(element.frame.minY)
        }
        expectation(for: positioned, evaluatedWith: element)
        waitForExpectations(timeout: 3)
    }

    private func openComposer(scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-DemoSlowFeedbackSubmission",
        ]
        app.launch()
        app.buttons["Fixture mode"].tap()

        if let scenario {
            let picker = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Server behavior")
            ).firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 3))
            picker.tap()
            app.buttons[scenario].tap()
        }

        let openButton = app.buttons["demo.fixture.open"]
        for _ in 0 ..< 5 where openButton.isHittable == false {
            app.swipeUp()
        }
        XCTAssertTrue(openButton.waitForExistence(timeout: 3))
        openButton.tap()

        let newFeedback = app.buttons["developerCommunity.newFeedback"]
        XCTAssertTrue(newFeedback.waitForExistence(timeout: 3))
        newFeedback.tap()
        let bug = app.buttons["Report a Bug"]
        XCTAssertTrue(bug.waitForExistence(timeout: 3))
        bug.tap()
        XCTAssertTrue(app.textViews["developerCommunity.composer.body"].waitForExistence(timeout: 3))
        return app
    }

    private func enterFeedback(_ feedback: String, in body: XCUIElement) {
        body.tap()
        if let existing = body.value as? String, existing.isEmpty == false {
            body.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        body.typeText(feedback)
    }

    private func revealComposerSubmit(in app: XCUIApplication) -> XCUIElement {
        let form = app.scrollViews["developerCommunity.composer.form"]
        let submit = app.buttons["developerCommunity.composer.submit"]
        XCTAssertTrue(form.waitForExistence(timeout: 3))

        for _ in 0 ..< 8 {
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.85))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.15))
            start.press(forDuration: 0.01, thenDragTo: end)
            if submit.isHittable, form.frame.contains(submit.frame) {
                break
            }
        }

        XCTAssertTrue(submit.isHittable, "The form must scroll to its sending action")
        XCTAssertTrue(form.frame.contains(submit.frame), "Every button edge must be visible before tapping")
        return submit
    }

    private func assertCenteredStatus(
        _ statusFrame: CGRect,
        in contentFrame: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(statusFrame.midX, contentFrame.midX, accuracy: 20, file: file, line: line)
        XCTAssertEqual(
            statusFrame.midY,
            contentFrame.midY,
            accuracy: contentFrame.height * 0.2,
            "Submission feedback must appear in the center of the content area",
            file: file,
            line: line
        )
    }

    private func attachScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
