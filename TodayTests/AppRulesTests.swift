import TodayCore
import UIKit
import XCTest
@testable import Today

/// App-side checks. The rules engine itself is tested in
/// Packages/TodayKit (TodayCoreTests), which the iOS Gate runs with `swift test`.
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

    func testStoreDirectoryIsUsable() throws {
        let directory = AppRules.storeDirectory
        XCTAssertEqual(directory.lastPathComponent, "Household")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.isWritableFile(atPath: directory.path))
    }

    @MainActor
    func testModelLoadsTheBundledRules() async {
        let model = AppModel()
        await model.load()
        XCTAssertEqual(model.status, .ready)
        XCTAssertNotNil(model.plan)
    }

    @MainActor
    func testSeededModelPlansTheSampleDay() async throws {
        let model = AppModel(seed: SampleHousehold.tuesday)
        await model.load()
        XCTAssertEqual(model.status, .ready)
        let plan = try XCTUnwrap(model.plan)
        XCTAssertEqual(plan.date, SampleHousehold.tuesday)
        XCTAssertEqual(model.weatherState, .ready)
        let brief = try XCTUnwrap(model.briefText())
        XCTAssertTrue(brief.contains("Sam drives the pickup loop at 3:30"), brief)
        XCTAssertFalse(brief.lowercased().contains("free"), brief)
    }

    @MainActor
    func testSavingAnEditReplansTheDay() async throws {
        let model = AppModel(seed: SampleHousehold.tuesday)
        await model.load()
        var rules = try XCTUnwrap(model.rules)
        rules.moveEvents(titled: "Dentist", to: ["dad"])
        XCTAssertEqual(model.save(rules), [])
        let dentist = try XCTUnwrap(model.plan?.items.first { $0.title == "Dentist" })
        XCTAssertEqual(dentist.people, ["dad"])

        // Invalid rules are refused and nothing changes.
        var broken = try XCTUnwrap(model.rules)
        broken.people[0].name = ""
        XCTAssertFalse(model.save(broken).isEmpty)
        XCTAssertEqual(model.rules?.people[0].name, "Sam")
    }

    @MainActor
    func testNeedsCheckOff() async throws {
        let model = AppModel(seed: SampleHousehold.tuesday)
        await model.load()
        let key = KidNeed.key(people: ["pre"], item: "Backpack")
        model.toggleNeed(key)
        XCTAssertTrue(model.doneNeeds.contains(key))
        model.toggleNeed(key)
        XCTAssertFalse(model.doneNeeds.contains(key))
    }

    func testPhotosAreCroppedSquare() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200))
        let image = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        }
        let jpeg = try XCTUnwrap(PersonEditor.squareJPEG(try XCTUnwrap(image.pngData())))
        let decoded = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(decoded.size.width, 512)
        XCTAssertEqual(decoded.size.height, 512)
    }
}
