import XCTest
@testable import Today

/// App-side checks. The rules engine itself is tested in
/// Packages/TodayKit (TodayCoreTests), which this scheme also runs.
final class AppRulesTests: XCTestCase {
    func testRulesFileShipsInTheAppBundle() throws {
        let url = try XCTUnwrap(AppRules.bundledURL, "Rules/household.json must be a resource of the app target")
        XCTAssertEqual(url.lastPathComponent, "household.json")
    }

    func testBundledRulesLoad() {
        XCTAssertNil(AppRules.loadErrorMessage())
    }

    func testSeedIsOffWithoutTheLaunchKey() {
        XCTAssertNil(AppLaunch.seedDate)
    }
}
