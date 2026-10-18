import XCTest

/// Launches the app on each seeded sample day (pinned to 2:40 PM, as in the
/// approved mockup) and on the bundled rules, walks the main screens, and
/// keeps a named screenshot of each in the result bundle. CI exports them
/// to the ci-screenshots branch.
final class SeededDayTests: XCTestCase {
    static let milestone = "M5"
    static let seededDays = ["2026-10-20", "2026-10-21", "2026-10-24"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TODAY_SEED"] = seed
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 60), "\(seed): the Today screen never appeared")
        return app
    }

    @MainActor
    func testSeededDays() throws {
        for day in Self.seededDays {
            let app = launch(seed: day)
            let upNext = app.staticTexts["upnext.title"]
            XCTAssertTrue(upNext.waitForExistence(timeout: 30), day)
            switch day {
            case "2026-10-20":
                XCTAssertEqual(app.staticTexts["today.title"].label, "Tuesday")
                XCTAssertEqual(upNext.label, "Pickup loop", day)
                // The wife's calendar is missing on this seed: no data, never free.
                XCTAssertTrue(app.staticTexts["lane.nodata.Kate"].exists, day)
                XCTAssertTrue(app.descendants(matching: .any)["block.event:2026-10-20-serc"].exists, day)
            case "2026-10-21":
                XCTAssertEqual(upNext.label, "Pickup loop", day)
                // The vendor call overlaps the loop.
                XCTAssertTrue(app.descendants(matching: .any)["alert.0"].exists, day)
                // The shared "Us" calendar asks who the conference is for.
                XCTAssertTrue(app.descendants(matching: .any)["needs.person"].exists, day)
            default:
                XCTAssertEqual(app.staticTexts["today.title"].label, "Saturday")
                XCTAssertTrue(upNext.label.hasPrefix("Nothing else"), day)
            }
            keepScreenshot(of: app, named: "\(Self.milestone)-\(day)-1-top")
            app.swipeUp()
            keepScreenshot(of: app, named: "\(Self.milestone)-\(day)-2-lanes")
            app.swipeUp()
            app.swipeUp()
            keepScreenshot(of: app, named: "\(Self.milestone)-\(day)-3-cards")
            app.terminate()
        }
    }

    /// Scrolls the Today screen until Jess's SERC planning block can be tapped.
    @MainActor
    private func tapSERC(in app: XCUIApplication) {
        let serc = app.descendants(matching: .any)["block.event:2026-10-20-serc"]
        XCTAssertTrue(serc.waitForExistence(timeout: 20))
        for _ in 0..<3 where !serc.isHittable {
            app.swipeUp()
        }
        serc.tap()
    }

    @MainActor
    func testWhyIsThisHere() throws {
        let app = launch(seed: "2026-10-20")
        tapSERC(in: app)
        let headline = app.staticTexts["why.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 20))
        XCTAssertEqual(headline.label, "On Jess's lane")
        XCTAssertTrue(app.staticTexts["Rule \"SERC → Jess\" · Title contains \"SERC\""].exists)
        keepScreenshot(of: app, named: "\(Self.milestone)-why-serc")
    }

    @MainActor
    func testBrief() throws {
        let app = launch(seed: "2026-10-20")
        app.buttons["brief.play"].tap()
        let text = app.staticTexts["brief.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertTrue(text.label.contains("pickup loop at 3:30"), text.label)
        XCTAssertFalse(text.label.lowercased().contains("free"), text.label)
        keepScreenshot(of: app, named: "\(Self.milestone)-brief")
        app.buttons["brief.play"].tap()
    }

    @MainActor
    func testHousehold() throws {
        let app = launch(seed: "2026-10-20")
        app.buttons["household.open"].tap()
        let tabs = app.segmentedControls["household.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["person.grandpa"].waitForExistence(timeout: 10))
        keepScreenshot(of: app, named: "\(Self.milestone)-household-1-people")

        app.buttons["person.kinder"].tap()
        XCTAssertTrue(app.textFields["person.name"].waitForExistence(timeout: 10))
        keepScreenshot(of: app, named: "\(Self.milestone)-household-2-person")
        app.buttons["editor.cancel"].tap()

        tabs.buttons["Rules"].tap()
        XCTAssertTrue(app.buttons["rule.serc"].waitForExistence(timeout: 10))
        keepScreenshot(of: app, named: "\(Self.milestone)-household-3-rules")

        app.buttons["rule.serc"].tap()
        XCTAssertTrue(app.textFields["rule.name"].waitForExistence(timeout: 10))
        // The preview is near the bottom of the form.
        let count = app.staticTexts["rule.preview.count"]
        XCTAssertTrue(scroll(to: count, in: app))
        XCTAssertEqual(count.label, "Matches 2 events")
        keepScreenshot(of: app, named: "\(Self.milestone)-household-4-rule")
        app.buttons["editor.cancel"].tap()

        tabs.buttons["Schedule"].tap()
        XCTAssertTrue(app.buttons["schedule.block.work"].waitForExistence(timeout: 10))
        keepScreenshot(of: app, named: "\(Self.milestone)-household-5-schedule")

        tabs.buttons["Calendars"].tap()
        XCTAssertTrue(app.buttons["calendar.Us"].waitForExistence(timeout: 10))
        keepScreenshot(of: app, named: "\(Self.milestone)-household-6-calendars")
        app.buttons["calendar.Us"].tap()
        XCTAssertTrue(app.switches["calendar.used"].waitForExistence(timeout: 10))
        keepScreenshot(of: app, named: "\(Self.milestone)-household-7-calendar-editor")
        app.buttons["editor.cancel"].tap()
        XCTAssertTrue(scroll(to: app.descendants(matching: .any)["calendar.missing.Kate"], in: app))
    }

    @MainActor
    func testPickSomeoneForOneEvent() throws {
        let app = launch(seed: "2026-10-20")
        tapSERC(in: app)
        let headline = app.staticTexts["why.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 20))
        app.buttons["why.pick.grandpa"].tap()
        app.buttons["why.pick.dad"].tap()
        app.buttons["why.assign"].tap()
        let moved = expectation(for: NSPredicate(format: "label == %@", "On Sam's lane"), evaluatedWith: headline)
        wait(for: [moved], timeout: 10)
        XCTAssertTrue(app.staticTexts["Picked by hand for this event."].exists)
        keepScreenshot(of: app, named: "\(Self.milestone)-why-picked")
    }

    @MainActor
    func testNeedsAPerson() throws {
        let app = launch(seed: "2026-10-21")
        let card = app.descendants(matching: .any)["needs.person"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        keepScreenshot(of: app, named: "\(Self.milestone)-needs-person")
        app.buttons["needs.assign.mom"].tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: card)
        wait(for: [gone], timeout: 10)
        XCTAssertTrue(app.descendants(matching: .any)["block.event:2026-10-21-conference"].exists)
    }

    @MainActor
    func testSwipeBetweenDays() throws {
        let app = launch(seed: "2026-10-20")
        let title = app.staticTexts["today.title"]
        XCTAssertEqual(title.label, "Tuesday")
        app.swipeLeft()
        let wednesday = expectation(for: NSPredicate(format: "label == %@", "Wednesday"), evaluatedWith: title)
        wait(for: [wednesday], timeout: 10)
        XCTAssertTrue(app.staticTexts["upnext.title"].waitForExistence(timeout: 10))
        keepScreenshot(of: app, named: "\(Self.milestone)-swiped-to-wednesday")
        app.swipeLeft()
        app.swipeLeft()
        app.swipeLeft()
        let saturday = expectation(for: NSPredicate(format: "label == %@", "Saturday"), evaluatedWith: title)
        wait(for: [saturday], timeout: 10)
        app.buttons["today.jump"].tap()
        let back = expectation(for: NSPredicate(format: "label == %@", "Tuesday"), evaluatedWith: title)
        wait(for: [back], timeout: 10)
        XCTAssertFalse(app.buttons["today.jump"].exists)
    }

    @MainActor
    func testBundledRulesLoad() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 60))
        // A fresh install asks nothing until the button is tapped.
        XCTAssertTrue(app.buttons["connect.calendars"].waitForExistence(timeout: 30))
        // The real rules still have placeholders to fill in.
        XCTAssertTrue(app.buttons["rules.warnings"].exists)
        XCTAssertFalse(app.staticTexts["rules.error"].exists)
        keepScreenshot(of: app, named: "\(Self.milestone)-bundled-rules")
    }

    /// Swipes up until `element` exists: lists and forms only load the rows
    /// that have scrolled into view.
    @MainActor
    private func scroll(to element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<6 {
            if element.waitForExistence(timeout: 2) { return true }
            app.swipeUp()
        }
        return element.exists
    }

    @MainActor
    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
