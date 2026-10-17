import XCTest

/// Launches the app on each seeded sample day and on the bundled rules, and
/// keeps a screenshot of each as a named attachment in the result bundle.
/// CI exports those attachments to the ci-screenshots branch.
final class SeededDayTests: XCTestCase {
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
            if day == "2026-10-24" {
                XCTAssertTrue(plan.label.contains("weekend: no school, no pickup loop"), day)
            } else {
                XCTAssertTrue(plan.label.contains("Pickup loop"), day)
            }
            if day == "2026-10-20" {
                // The wife's calendar is missing on this seed: no data, never free.
                XCTAssertTrue(plan.label.contains("NO DATA"), day)
            }
            keepScreenshot(of: app, named: "M1-seed-\(day)")
            app.terminate()
        }
    }

    @MainActor
    func testBundledRulesLoad() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["plan.text"].waitForExistence(timeout: 60))
        XCTAssertFalse(app.staticTexts["rules.error"].exists)
        keepScreenshot(of: app, named: "M1-bundled-rules")
    }

    @MainActor
    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
