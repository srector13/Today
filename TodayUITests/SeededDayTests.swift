import XCTest

/// Launches the app on each seeded sample day and on the bundled rules, and
/// keeps a screenshot of each as a named attachment in the result bundle.
/// CI exports those attachments to the ci-screenshots branch.
final class SeededDayTests: XCTestCase {
    static let milestone = "M2"
    static let seededDays = ["2026-10-20", "2026-10-21", "2026-10-24"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSeededDays() throws {
        for day in Self.seededDays {
            let app = XCUIApplication()
            app.launchEnvironment["TODAY_SEED"] = day
            app.launch()
            let plan = app.staticTexts["plan.text"]
            XCTAssertTrue(plan.waitForExistence(timeout: 60), "\(day): the plan text never appeared")
            switch day {
            case "2026-10-20":
                XCTAssertTrue(plan.label.contains("Pickup loop"), day)
                // The wife's calendar is missing on this seed: no data, never free.
                XCTAssertTrue(plan.label.contains("NO DATA"), day)
                XCTAssertTrue(plan.label.contains("rule \"SERC → Jess\""), day)
                XCTAssertTrue(plan.label.contains("Hidden by rules"), day)
            case "2026-10-21":
                XCTAssertTrue(plan.label.contains("SERC board call  [Sam: rule \"SERC → Jess\"]"), day)
            default:
                XCTAssertTrue(plan.label.contains("weekend: no school, no pickup loop"), day)
                XCTAssertTrue(plan.label.contains("Aunt Jo"), day)
            }
            keepScreenshot(of: app, named: "\(Self.milestone)-seed-\(day)")
            app.terminate()
        }
    }

    @MainActor
    func testBundledRulesLoad() throws {
        let app = XCUIApplication()
        app.launch()
        let plan = app.staticTexts["plan.text"]
        XCTAssertTrue(plan.waitForExistence(timeout: 60))
        let loaded = expectation(for: NSPredicate(format: "label CONTAINS %@", "Rules incomplete"), evaluatedWith: plan)
        wait(for: [loaded], timeout: 60)
        XCTAssertFalse(app.staticTexts["rules.error"].exists)
        // A fresh install asks nothing until the button is tapped.
        XCTAssertTrue(app.buttons["connect.calendars"].exists)
        XCTAssertTrue(plan.label.contains("Calendars not connected yet"))
        keepScreenshot(of: app, named: "\(Self.milestone)-bundled-rules")
    }

    @MainActor
    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
