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
        XCTAssertNotNil(model.plan(on: model.today))
    }

    @MainActor
    func testSeededModelPlansTheSampleDay() async throws {
        let model = AppModel(seed: SampleHousehold.tuesday)
        await model.load()
        XCTAssertEqual(model.status, .ready)
        let day = SampleHousehold.tuesday
        let plan = try XCTUnwrap(model.plan(on: day))
        XCTAssertEqual(plan.date, day)
        XCTAssertEqual(model.weatherState(on: day), .ready)
        let brief = try XCTUnwrap(model.briefText(on: day))
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
        let dentist = try XCTUnwrap(model.plan(on: SampleHousehold.tuesday)?.items.first { $0.title == "Dentist" })
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
        let day = SampleHousehold.tuesday
        model.toggleNeed(key, on: day)
        XCTAssertTrue(model.doneNeeds(on: day).contains(key))
        XCTAssertFalse(model.doneNeeds(on: day.adding(days: 2)).contains(key), "each day has its own list")
        model.toggleNeed(key, on: day)
        XCTAssertFalse(model.doneNeeds(on: day).contains(key))
    }

    @MainActor
    func testOtherDaysLoadOnDemand() async throws {
        let model = AppModel(seed: SampleHousehold.tuesday)
        await model.load()
        XCTAssertNil(model.plan(on: SampleHousehold.saturday))
        await model.loadDay(SampleHousehold.saturday)
        let saturday = try XCTUnwrap(model.plan(on: SampleHousehold.saturday))
        XCTAssertNil(saturday.pickupLoop)
        XCTAssertTrue(model.pageDates.contains(SampleHousehold.saturday))
        let brief = try XCTUnwrap(model.briefText(on: SampleHousehold.saturday))
        XCTAssertTrue(brief.hasPrefix("Here's Saturday, October 24."), brief)
    }

    @MainActor
    func testPickingSomeoneForAnEvent() async throws {
        let model = AppModel(seed: SampleHousehold.tuesday)
        await model.load()
        let wednesday = SampleHousehold.wednesday
        await model.loadDay(wednesday)
        let waiting = try XCTUnwrap(model.plan(on: wednesday)?.unassigned.first)
        XCTAssertEqual(waiting.title, "Parent-teacher conference")

        XCTAssertEqual(model.assign(waiting, to: ["mom"], scope: .thisEvent), [])
        let plan = try XCTUnwrap(model.plan(on: wednesday))
        XCTAssertTrue(plan.unassigned.isEmpty)
        let picked = try XCTUnwrap(plan.items.first { $0.id == waiting.id })
        XCTAssertEqual(picked.people, ["mom"])
        XCTAssertNotNil(model.pick(for: picked))
        // Kept on disk beside the rules.
        XCTAssertEqual(model.store.loadAssignments().entries.count, 1)

        model.clearPick(for: picked)
        XCTAssertEqual(model.plan(on: wednesday)?.unassigned.map(\.id), [waiting.id])
    }

    @MainActor
    func testEveryEventWithThisTitleMakesARule() async throws {
        let model = AppModel(seed: SampleHousehold.tuesday)
        await model.load()
        let dentist = try XCTUnwrap(model.plan(on: SampleHousehold.tuesday)?.items.first { $0.title == "Dentist" })
        XCTAssertEqual(model.assign(dentist, to: ["dad"], scope: .everyTitled), [])
        XCTAssertEqual(model.rules?.assignmentRules.first?.name, "Dentist → Sam")
        XCTAssertNil(model.pick(for: dentist))
        XCTAssertEqual(model.plan(on: SampleHousehold.tuesday)?.items.first { $0.title == "Dentist" }?.people, ["dad"])
    }

    @MainActor
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
