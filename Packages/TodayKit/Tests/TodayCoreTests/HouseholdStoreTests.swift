import Foundation
import Testing
@testable import TodayCore

@Suite("Household store")
struct HouseholdStoreTests {
    let store: HouseholdStore
    let bundled = Data(SampleHousehold.rulesJSON.utf8)

    init() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("today-store-\(UUID().uuidString)", isDirectory: true)
        store = HouseholdStore(directory: directory)
    }

    private func bundledVariant(_ edit: (inout [String: Any]) -> Void) -> Data {
        Fixture.rulesJSON(edit)
    }

    @Test func firstLoadSeedsFromTheBundle() throws {
        let loaded = try store.load(bundled: bundled)
        #expect(loaded.rules == Fixture.rules)
        #expect(loaded.recoveredFrom == nil)
        #expect(try Data(contentsOf: store.rulesURL) == bundled)
    }

    @Test func savedEditsSurviveAReload() throws {
        var rules = try store.load(bundled: bundled).rules
        rules.people[0].color = LaneColor(hex: "#FF6B5E")
        try store.save(rules)
        let reloaded = try store.load(bundled: bundled)
        #expect(reloaded.rules.people[0].color?.hex == "#FF6B5E")
    }

    @Test func savingInvalidRulesIsRefusedAndChangesNothing() throws {
        var rules = try store.load(bundled: bundled).rules
        let before = try store.exportData()
        rules.assignmentRules[0].actions = [.assignTo(["nobody"])]
        #expect(throws: RulesError.self) { try store.save(rules) }
        #expect(try store.exportData() == before)
    }

    @Test func aNewBundledFileIsAdoptedWhenNothingWasEditedInTheApp() throws {
        _ = try store.load(bundled: bundled)
        let newer = bundledVariant { $0["todo"] = ["New question"] }
        let loaded = try store.load(bundled: newer)
        #expect(loaded.rules.todo == ["New question"])
    }

    @Test func aNewBundledFileDoesNotOverwriteInAppEdits() throws {
        var rules = try store.load(bundled: bundled).rules
        rules.people[0].name = "Samuel"
        try store.save(rules)
        let newer = bundledVariant { $0["todo"] = ["New question"] }
        let loaded = try store.load(bundled: newer)
        #expect(loaded.rules.people[0].name == "Samuel")
        #expect(loaded.rules.todo.isEmpty)
    }

    @Test func placeholderCalendarsAreDroppedAndTheFileSaved() throws {
        var rules = try store.load(bundled: bundled).rules
        rules.calendars.insert(CalendarRule(title: "<Family calendar>", members: .everyone, ifNobodyNamed: .people(["grandpa"])), at: 0)
        rules.calendars.append(CalendarRule(title: " <Wife's calendar> ", members: .people(["mom"])))
        try store.save(rules)
        let loaded = try store.load(bundled: bundled)
        #expect(loaded.rules.calendars == Fixture.rules.calendars)
        #expect(!loaded.warnings.contains { $0.path.hasPrefix("calendars") })
        let saved = try #require(String(data: store.exportData(), encoding: .utf8))
        #expect(!saved.contains("<Family calendar>") && !saved.contains("<Wife's calendar>"))
        #expect(try store.load(bundled: bundled).rules == loaded.rules)
    }

    @Test func importedPlaceholderCalendarsAreDroppedToo() throws {
        _ = try store.load(bundled: bundled)
        let file = bundledVariant { json in
            var calendars = json["calendars"] as! [[String: Any]]
            calendars.append(["title": "<Your calendar>", "members": ["dad"]])
            json["calendars"] = calendars
        }
        let imported = try store.importRules(file)
        #expect(imported.rules.calendars == Fixture.rules.calendars)
        #expect(try store.load(bundled: bundled).rules.calendars == Fixture.rules.calendars)
    }

    @Test func importReplacesOnlyWhenValid() throws {
        _ = try store.load(bundled: bundled)
        let good = bundledVariant { $0["todo"] = ["Imported"] }
        try store.importRules(good)
        #expect(try store.load(bundled: bundled).rules.todo == ["Imported"])

        let bad = Data("{ \"schemaVersion\": 2 }".utf8)
        #expect(throws: RulesError.self) { try store.importRules(bad) }
        #expect(try store.exportData() == good)
    }

    @Test func aCorruptedFileFallsBackToTheLastGoodCopy() throws {
        _ = try store.load(bundled: bundled)
        try Data("{ not json".utf8).write(to: store.rulesURL)
        let loaded = try store.load(bundled: bundled)
        #expect(loaded.rules == Fixture.rules)
        #expect(loaded.recoveredFrom != nil)
    }

    @Test func photosAreSavedByPersonID() throws {
        let name = try store.savePhoto(Data([0xFF, 0xD8, 0xFF]), for: "twin/A")
        #expect(name == "twin_A.jpg")
        #expect(try Data(contentsOf: store.photoURL(named: name)) == Data([0xFF, 0xD8, 0xFF]))
        store.deletePhoto(named: name)
        #expect(!FileManager.default.fileExists(atPath: store.photoURL(named: name).path))
    }
}
