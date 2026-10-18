import Foundation
import Testing
@testable import TodayCore

/// Calendars with several members, "ask" calendars, and picks made by hand.
@Suite("Calendar members and manual picks")
struct MembersAndManualTests {
    let planner = Fixture.planner
    let wednesday = SampleHousehold.wednesday

    func event(_ title: String, on calendar: String = "Us", _ start: String = "17:15", _ end: String = "17:45",
               iso: String = "2026-10-21", repeating: Bool = false) -> SourceEvent {
        var e = Fixture.event(title, on: calendar, iso, start, end)
        e.isRecurring = repeating
        return e
    }

    func plan(_ events: [SourceEvent], manual: ManualAssignments = ManualAssignments(),
              calendars: Set<String> = ["Family", "Sam", "Kate", "Us"], planner: DayPlanner? = nil) -> DayPlan {
        (planner ?? self.planner).plan(for: wednesday, input: DayInput(events: events, calendarsOnDevice: calendars, manual: manual))
    }

    // MARK: Calendars

    @Test func olderFilesStillLoad() throws {
        let rules = try RulesLoader.load(Fixture.rulesJSON { json in
            json["schemaVersion"] = 2
            json["calendars"] = [
                ["title": "Family", "role": "shared", "defaultOwner": "grandpa"],
                ["title": "Sam", "role": "personal", "owner": "dad"],
                ["title": "Old shared", "role": "shared"],
            ]
        }).rules
        #expect(rules.calendars == [
            CalendarRule(title: "Family", members: .everyone, ifNobodyNamed: .people(["grandpa"])),
            CalendarRule(title: "Sam", members: .people(["dad"])),
            CalendarRule(title: "Old shared", members: .everyone, ifNobodyNamed: .ask),
        ])
        // Saved again, they're written in the new form.
        let text = RulesWriter.text(rules)
        #expect(text.contains(#"{ "title": "Family", "members": "everyone", "ifNobodyNamed": ["grandpa"] }"#))
        #expect(!text.contains("\"role\""))
    }

    @Test func anAskCalendarHoldsUnnamedEventsForAPick() throws {
        let plan = plan([event("Parent-teacher conference")])
        let waiting = try #require(plan.unassigned.first)
        #expect(waiting.title == "Parent-teacher conference")
        #expect(waiting.people.isEmpty)
        #expect(waiting.origin == .calendar(title: "Us", attribution: .unassigned))
        #expect(!plan.items.contains { $0.title == "Parent-teacher conference" })
        #expect(plan.lanes.allSatisfy { !$0.items.contains { $0.title == "Parent-teacher conference" } })
        #expect(planner.explain(waiting).headline == "Needs a person")
    }

    @Test func aNameInTheTitleStillWins() throws {
        let plan = plan([event("Dinner with Kate's sister"), event("Dentist - Sam", "08:00", "08:30")])
        let dinner = try #require(plan.items.first { $0.title.hasPrefix("Dinner") })
        #expect(dinner.people == ["mom"])
        #expect(dinner.origin == .calendar(title: "Us", attribution: .namedInTitle))
        #expect(plan.unassigned.isEmpty)
    }

    @Test func unnamedEventsCanGoToEveryMember() throws {
        let planner = try Fixture.planner { json in
            var calendars = json["calendars"] as! [[String: Any]]
            calendars[3]["ifNobodyNamed"] = "members"
            json["calendars"] = calendars
        }
        let plan = plan([event("Date night", "19:00", "21:00")], planner: planner)
        let date = try #require(plan.items.first { $0.title == "Date night" })
        #expect(date.people == ["dad", "mom"])
        #expect(date.origin == .calendar(title: "Us", attribution: .calendarMembers))
        #expect(planner.explain(date).reasons == ["It's on the Us calendar, which Sam & Kate share, and the title names nobody."])
        #expect(plan.lane("Sam")?.items.contains(date) == true && plan.lane("Kate")?.items.contains(date) == true)
    }

    @Test func aRuleCanClaimAnAskEvent() throws {
        var rules = Fixture.rules
        rules.assignmentRules.insert(AssignmentRule(
            id: "pt", name: "Conferences → Kate",
            conditions: [RuleCondition(field: .title, op: .contains, value: "conference")],
            actions: [.assignTo(["mom"])]), at: 0)
        let plan = plan([event("Parent-teacher conference")], planner: try DayPlanner(rules: rules))
        #expect(plan.unassigned.isEmpty)
        #expect(plan.items.first { $0.title == "Parent-teacher conference" }?.people == ["mom"])
    }

    @Test func aMissingSharedCalendarBlanksItsMembersOnly() {
        let plan = plan([], calendars: ["Family", "Sam", "Kate"])
        #expect(plan.lane("Sam")?.data == .noData(reason: "the \"Us\" calendar isn't on this device"))
        #expect(plan.lane("Kate")?.data.isKnown == false)
        #expect(plan.lane("Emma")?.data == .known)
        #expect(!plan.alerts.contains { $0.kind == .missingCalendar })
        // Someone's own missing calendar is named in their reason, not the shared one.
        let kateMissing = self.plan([], calendars: ["Family", "Sam"])
        #expect(kateMissing.lane("Kate")?.data == .noData(reason: "the \"Kate\" calendar isn't on this device"))
    }

    @Test func theBriefMentionsEventsWaitingForAPerson() {
        let text = BriefComposer(planner: planner).brief(
            plan([event("Parent-teacher conference")]), now: Fixture.at("2026-10-21", "06:30"), weather: nil)
        #expect(text.contains("One event needs a person: Parent-teacher conference at 5:15."))
        #expect(!text.lowercased().contains("free"))
    }

    // MARK: Manual picks

    @Test func aPickBeatsRulesNamesAndHiding() throws {
        let serc = event("SERC board call", on: "Sam", "18:30", "19:30")
        let busy = event("Busy", on: "Sam", "13:00", "14:00")
        var manual = ManualAssignments()
        manual.set(["dad"], for: serc, on: wednesday)
        manual.set(["dad", "mom"], for: busy, on: wednesday)
        let plan = plan([serc, busy], manual: manual)
        let call = try #require(plan.items.first { $0.title == "SERC board call" })
        #expect(call.people == ["dad"])
        #expect(call.origin == .calendar(title: "Sam", attribution: .manual))
        #expect(call.rules == ["SERC → Jess"], "the rule still shows as matched")
        #expect(plan.items.contains { $0.title == "Busy" }, "a pick un-hides")
        #expect(planner.explain(call).reasons.first == "Picked by hand for this event.")
    }

    @Test func aPickForOneDayLeavesOtherRepeatsAlone() {
        let monday = event("Swim", on: "Family", "17:30", "18:00", iso: "2026-10-19", repeating: true)
        var wednesdayRepeat = monday
        wednesdayRepeat.start = Fixture.at("2026-10-21", "17:30")
        wednesdayRepeat.end = Fixture.at("2026-10-21", "18:00")
        var manual = ManualAssignments()
        manual.set(["kinder"], for: wednesdayRepeat, on: wednesday)
        #expect(manual.entry(for: wednesdayRepeat, on: wednesday)?.people == ["kinder"])
        #expect(manual.entry(for: monday, on: Fixture.date("2026-10-19")) == nil)

        // A series pick applies to every repeat and replaces the one-offs.
        manual.set(["pre"], for: monday, on: nil)
        #expect(manual.entries.count == 1)
        #expect(manual.entry(for: wednesdayRepeat, on: wednesday)?.people == ["pre"])
        #expect(manual.entry(for: monday, on: Fixture.date("2026-10-19"))?.people == ["pre"])

        // A one-off pick on top of a series pick wins for that day.
        manual.set(["dad"], for: wednesdayRepeat, on: wednesday)
        #expect(manual.entry(for: wednesdayRepeat, on: wednesday)?.people == ["dad"])
        #expect(manual.entry(for: monday, on: Fixture.date("2026-10-19"))?.people == ["pre"])

        manual.clear(for: wednesdayRepeat, on: wednesday)
        #expect(manual.entries.isEmpty)
    }

    @Test func pruningAndRemovingPeople() {
        var manual = ManualAssignments()
        let old = event("Old", iso: "2026-09-01")
        let series = event("Series", repeating: true)
        let today = event("Today")
        manual.set(["dad"], for: old, on: Fixture.date("2026-09-01"))
        manual.set(["mom"], for: series, on: nil)
        manual.set(["dad", "mom"], for: today, on: wednesday)
        manual.prune(before: Fixture.date("2026-10-01"))
        #expect(manual.entries.map(\.title) == ["Series", "Today"])
        manual.remove("mom")
        #expect(manual.entries.map(\.title) == ["Today"])
        #expect(manual.entries.first?.people == ["dad"])
    }

    @Test func picksAreSavedBesideTheRules() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HouseholdStore(directory: directory)
        #expect(store.loadAssignments().entries.isEmpty)
        var manual = ManualAssignments()
        manual.set(["mom"], for: event("Parent-teacher conference"), on: wednesday)
        try store.saveAssignments(manual)
        #expect(store.loadAssignments() == manual)
    }

    @Test func removingAPersonCleansSharedCalendars() {
        var rules = Fixture.rules
        rules.removePerson("mom")
        #expect(rules.calendarRule(titled: "Us")?.members == .people(["dad"]))
        #expect(rules.calendarRule(titled: "Kate") == nil)
        rules.removePerson("dad")
        #expect(rules.calendarRule(titled: "Us") == nil)
    }
}
