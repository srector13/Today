import Foundation
import Testing
@testable import TodayCore

@Suite("Loading and validating the rules file")
struct RulesLoadingTests {
    private func load(_ edit: (inout [String: Any]) -> Void) -> Result<LoadedRules, RulesError> {
        Result { () throws(RulesError) in try RulesLoader.load(Fixture.rulesJSON(edit)) }
    }

    private func errors(_ edit: (inout [String: Any]) -> Void) -> [RulesIssue] {
        guard case let .failure(error) = load(edit) else { return [] }
        return error.issues
    }

    @Test func sampleRulesLoadCleanly() throws {
        let loaded = try RulesLoader.load(Data(SampleHousehold.rulesJSON.utf8))
        #expect(loaded.warnings.isEmpty)
        #expect(loaded.rules.people.count == 8)
        #expect(loaded.rules.importance(of: .pickupLoop) == .high)
        #expect(loaded.rules.importance(of: .work) == .background) // default, not in the file
    }

    @Test func misspeltKeyIsAnErrorWithASuggestion() {
        let issues = errors { rules in
            var loop = rules["pickupLoop"] as! [String: Any]
            loop["fallbakStart"] = loop.removeValue(forKey: "fallbackStart")
            rules["pickupLoop"] = loop
        }
        #expect(issues.count == 1)
        #expect(issues.first?.path == "pickupLoop.fallbakStart")
        #expect(issues.first?.message.contains("Did you mean \"fallbackStart\"?") == true)
    }

    @Test func badTimeNamesTheField() {
        let issues = errors { rules in
            var blocks = rules["blocks"] as! [[String: Any]]
            blocks[1]["start"] = "8.15"
            rules["blocks"] = blocks
        }
        #expect(issues.first?.path == "blocks[1].start")
        #expect(issues.first?.message.contains("not a time") == true)
    }

    @Test func unquotedTimeIsATypeError() {
        let issues = errors { rules in
            var blocks = rules["blocks"] as! [[String: Any]]
            blocks[0]["end"] = 1700
            rules["blocks"] = blocks
        }
        #expect(issues.first?.path == "blocks[0].end")
        #expect(issues.first?.message == "Expected text in quotes.")
    }

    @Test func missingRequiredKey() {
        let issues = errors { rules in
            var people = rules["people"] as! [[String: Any]]
            people[2].removeValue(forKey: "group")
            rules["people"] = people
        }
        #expect(issues.first?.path == "people[2]")
        #expect(issues.first?.message == "Missing \"group\".")
    }

    @Test func unknownPersonSuggestsTheNearestId() {
        let issues = errors { rules in
            var care = rules["care"] as! [[String: Any]]
            care[0]["kids"] = ["pre", "twinA", "twinC"]
            rules["care"] = care
        }
        #expect(issues.contains { $0.path == "care[0].kids[2]" && $0.message.contains("Did you mean \"twinA\"?") })
    }

    @Test func blockMustRunForward() {
        let issues = errors { rules in
            var blocks = rules["blocks"] as! [[String: Any]]
            blocks[0]["start"] = "17:00"
            blocks[0]["end"] = "08:30"
            rules["blocks"] = blocks
        }
        #expect(issues.contains { $0.path == "blocks[0]" && $0.message.contains("must be before") })
    }

    @Test func careUntilLoopNeedsTheLoopOnThoseDays() {
        let issues = errors { rules in
            var care = rules["care"] as! [[String: Any]]
            care[0]["days"] = "daily"
            rules["care"] = care
        }
        #expect(issues.contains { $0.path == "care[0].until" && $0.message.contains("sat, sun") })
    }

    @Test func everyKidInCareMustBeCollected() {
        let issues = errors { rules in
            var loop = rules["pickupLoop"] as! [String: Any]
            var stops = loop["stops"] as! [[String: Any]]
            stops[1]["collect"] = ["pre", "twinA"]
            loop["stops"] = stops
            rules["pickupLoop"] = loop
        }
        #expect(issues.contains { $0.message.contains("\"twinB\" is in care until the pickup loop") })
    }

    @Test func sharedCalendarNeedsADefaultOwner() {
        let issues = errors { rules in
            rules["calendars"] = [["title": "Family", "role": "shared"]]
        }
        #expect(issues.contains { $0.path == "calendars[0]" && $0.message.contains("defaultOwner") })
    }

    @Test func wrongSchemaVersion() {
        let issues = errors { $0["schemaVersion"] = 2 }
        #expect(issues.contains { $0.path == "schemaVersion" })
    }

    @Test func unknownTimeZone() {
        let issues = errors { $0["timeZone"] = "Central" }
        #expect(issues.contains { $0.path == "timeZone" })
    }

    @Test func placeholdersAndTodosAreWarningsNotErrors() throws {
        let data = Fixture.rulesJSON { rules in
            var people = rules["people"] as! [[String: Any]]
            people[2]["name"] = "<Eldest>"
            rules["people"] = people
            rules["todo"] = ["Confirm preschool hours"]
        }
        let loaded = try RulesLoader.load(data)
        #expect(loaded.warnings.map(\.path).sorted() == ["people[2].name", "todo[0]"])
        #expect(loaded.warnings.allSatisfy { $0.severity == .warning })
    }

    @Test func schemaPointerIsAllowed() throws {
        let data = Fixture.rulesJSON { $0["$schema"] = "./household.schema.json" }
        #expect(throws: Never.self) { try RulesLoader.load(data) }
    }

    @Test func noSchoolAcceptsDatesObjectsAndRanges() throws {
        let json = """
        { "noSchool": ["2026-10-23",
                       { "date": "2026-11-11", "label": "Veterans Day" },
                       { "from": "2026-11-25", "to": "2026-11-27", "label": "Thanksgiving" }] }
        """
        let calendar = try JSONDecoder().decode(SchoolCalendar.self, from: Data(json.utf8))
        #expect(calendar.noSchool(on: LocalDate(iso: "2026-10-23")!) != nil)
        #expect(calendar.noSchool(on: LocalDate(iso: "2026-11-11")!)?.label == "Veterans Day")
        #expect(calendar.noSchool(on: LocalDate(iso: "2026-11-26")!)?.label == "Thanksgiving")
        #expect(calendar.noSchool(on: LocalDate(iso: "2026-11-24")!) == nil)
        #expect(calendar.noSchool(on: LocalDate(iso: "2026-11-28")!) == nil)
    }

    @Test func malformedJSONIsReported() {
        let result = Result { () throws(RulesError) in try RulesLoader.load(Data("{ \"people\": [ }".utf8)) }
        guard case let .failure(error) = result else {
            Issue.record("Expected a failure")
            return
        }
        #expect(error.issues.count == 1)
        #expect(error.issues[0].severity == .error)
    }
}
