import Foundation
import Testing
@testable import TodayCore

@Suite("Assignment rules (Mail-style)")
struct AssignmentRuleTests {
    func event(_ title: String, calendar: String = "Family", location: String? = nil, notes: String? = nil,
               _ start: String = "18:00", _ end: String = "19:00", on iso: String = "2026-10-21") -> SourceEvent {
        SourceEvent(id: "\(iso)-\(title)-\(calendar)", calendarTitle: calendar, title: title,
                    start: Fixture.at(iso, start), end: Fixture.at(iso, end), location: location, notes: notes)
    }

    func rule(_ id: String, _ conditions: [RuleCondition], _ actions: [RuleAction],
              match: AssignmentRule.Match = .all, enabled: Bool = true, stop: Bool = true) -> AssignmentRule {
        AssignmentRule(id: id, name: id, enabled: enabled, match: match, conditions: conditions, actions: actions, stop: stop)
    }

    func title(_ op: RuleCondition.Op, _ value: String) -> RuleCondition {
        RuleCondition(field: .title, op: op, value: value)
    }

    /// The sample planner with its own rules replaced.
    func planner(_ rules: [AssignmentRule]) -> DayPlanner {
        var household = Fixture.rules
        household.assignmentRules = rules
        return try! DayPlanner(rules: household)
    }

    // MARK: Conditions

    @Test(arguments: [
        (RuleCondition.Op.contains, "SERC", "SERC planning", true),
        (.contains, "serc", "SERC planning", true),
        (.contains, "serc", "SÉRC picnic", true),
        (.contains, "  SERC ", "Board: SERC", true),
        (.contains, "SERC", "Search party", false),
        (.doesNotContain, "SERC", "Dentist", true),
        (.doesNotContain, "SERC", "SERC call", false),
        (.is, "busy", "Busy", true),
        (.is, "busy", "Busy afternoon", false),
        (.startsWith, "serc", "SERC: budget", true),
        (.startsWith, "budget", "SERC: budget", false),
        (.endsWith, "budget", "SERC: Budget", true),
        (.contains, "", "Anything", false),
    ])
    func titleConditions(_ op: RuleCondition.Op, _ value: String, _ eventTitle: String, _ expected: Bool) {
        #expect(RuleEngine.matches(title(op, value), event(eventTitle)) == expected)
    }

    @Test func otherFields() {
        let e = event("Practice", calendar: "Soccer", location: "Field 3", notes: "Bring cleats")
        #expect(RuleEngine.matches(RuleCondition(field: .calendar, op: .is, value: "soccer"), e))
        #expect(RuleEngine.matches(RuleCondition(field: .location, op: .contains, value: "field"), e))
        #expect(RuleEngine.matches(RuleCondition(field: .notes, op: .contains, value: "CLEATS"), e))
        // A missing location doesn't contain anything.
        #expect(RuleEngine.matches(RuleCondition(field: .location, op: .doesNotContain, value: "x"), event("No place")))
        #expect(!RuleEngine.matches(RuleCondition(field: .location, op: .contains, value: "x"), event("No place")))
    }

    @Test func allVersusAny() {
        let conditions = [title(.contains, "SERC"), RuleCondition(field: .calendar, op: .is, value: "Sam")]
        let onFamily = event("SERC planning", calendar: "Family")
        #expect(!RuleEngine.matches(rule("r", conditions, [.hide], match: .all), onFamily))
        #expect(RuleEngine.matches(rule("r", conditions, [.hide], match: .any), onFamily))
        #expect(RuleEngine.matches(rule("r", conditions, [.hide], match: .all), event("SERC call", calendar: "Sam")))
    }

    // MARK: Order, stop, enabled

    @Test func firstMatchWinsWhenStopIsSet() {
        let engine = RuleEngine(rules: [
            rule("a", [title(.contains, "SERC")], [.assignTo(["grandpa"])]),
            rule("b", [title(.contains, "planning")], [.assignTo(["mom"])]),
        ])
        let outcome = engine.evaluate(event("SERC planning"))
        #expect(outcome.assigned == ["grandpa"])
        #expect(outcome.matched == ["a"])
    }

    @Test func withoutStopLaterRulesApplyInTurn() {
        let engine = RuleEngine(rules: [
            rule("a", [title(.contains, "SERC")], [.assignTo(["grandpa"]), .alsoInclude(["dad"])], stop: false),
            rule("b", [title(.contains, "planning")], [.assignTo(["mom"]), .alsoInclude(["kinder"])]),
        ])
        let outcome = engine.evaluate(event("SERC planning"))
        #expect(outcome.assigned == ["mom"])
        #expect(outcome.assigningRule == "b")
        #expect(outcome.included == ["dad", "kinder"])
        #expect(outcome.matched == ["a", "b"])
    }

    @Test func disabledRulesDoNothing() {
        let engine = RuleEngine(rules: [rule("a", [title(.contains, "SERC")], [.hide], enabled: false)])
        #expect(engine.evaluate(event("SERC planning")) == RuleOutcome())
    }

    // MARK: Precedence over the built-in attribution

    @Test func ruleBeatsANameInTheTitle() throws {
        let p = planner([rule("dentist", [title(.contains, "dentist")], [.assignTo(["grandpa"])])])
        let assignment = try #require(p.assignment(of: event("Dentist - Emma")))
        #expect(assignment.people == ["grandpa"])
        #expect(assignment.attribution == .rule("dentist"))
    }

    @Test func ruleBeatsAPersonalCalendarOwner() {
        let plan = Fixture.planner.plan(for: SampleHousehold.wednesday, input: SampleHousehold.input(on: SampleHousehold.wednesday))
        let serc = plan.items.first { $0.title == "SERC board call" }
        #expect(serc?.people == ["grandpa"])
        #expect(plan.lane("Sam")?.items.contains { $0.title == "SERC board call" } == false)
        #expect(plan.lane("Jess")?.items.contains { $0.title == "SERC board call" } == true)
    }

    @Test func alsoIncludeAddsToTheBuiltInOwner() throws {
        let p = planner([rule("swim", [title(.contains, "swim")], [.alsoInclude(["dad"])])])
        let assignment = try #require(p.assignment(of: event("Swim lesson (Emma)")))
        #expect(assignment.people == ["kinder", "dad"])
        #expect(assignment.attribution == .namedInTitle)
        #expect(assignment.rules == ["swim"])
    }

    @Test func noMatchingRuleLeavesTheBuiltInsAlone() throws {
        let p = planner([rule("serc", [title(.contains, "SERC")], [.assignTo(["grandpa"])])])
        let assignment = try #require(p.assignment(of: event("Haircut - Nora")))
        #expect(assignment.people == ["pre"])
        #expect(assignment.rules.isEmpty)
    }

    // MARK: Hide, importance, unlisted calendars

    @Test func hiddenEventsLeaveTheLanesAndRaiseNoAlerts() {
        let p = planner([rule("busy", [title(.is, "Busy")], [.hide])])
        let plan = p.plan(for: Fixture.date("2026-10-21"),
                          events: [event("Busy", calendar: "Sam", "15:15", "15:45")],
                          calendarsOnDevice: Fixture.allCalendars)
        #expect(plan.items.allSatisfy { $0.title != "Busy" })
        #expect(plan.hiddenItems.map(\.title) == ["Busy"])
        #expect(plan.alerts(.loopConflict).isEmpty)
    }

    @Test func importanceOverride() {
        let p = planner([rule("golf", [title(.contains, "tee time")], [.importance(.background)])])
        let plan = p.plan(for: Fixture.date("2026-10-21"), events: [event("Tee time - Papa")], calendarsOnDevice: Fixture.allCalendars)
        #expect(plan.items.first { $0.title == "Tee time - Papa" }?.importance == .background)
    }

    @Test func aRuleCanClaimACalendarTheRulesDontList() {
        let p = planner([rule("soccer", [RuleCondition(field: .calendar, op: .is, value: "Soccer")], [.assignTo(["kinder"])])])
        let plan = p.plan(for: Fixture.date("2026-10-24"),
                          events: [event("Practice", calendar: "Soccer", "09:00", "10:00", on: "2026-10-24")],
                          calendarsOnDevice: Fixture.allCalendars.union(["Soccer"]))
        #expect(plan.items(for: "kinder").map(\.title) == ["Practice"])
        #expect(plan.unlistedCalendars.isEmpty)
    }

    // MARK: Preview

    @Test func previewShowsBeforeAndAfter() throws {
        let serc = rule("serc", [title(.contains, "SERC")], [.assignTo(["grandpa"])], enabled: false)
        let p = planner([serc])
        let events = [
            event("SERC board call", calendar: "Sam"),
            event("Dentist"),
            event("SERC planning", calendar: "Family", "17:00", "18:00"),
        ]
        let matches = p.preview(of: serc, events: events)
        #expect(matches.map(\.event.title) == ["SERC planning", "SERC board call"])
        let call = try #require(matches.last)
        #expect(call.before?.people == ["dad"])
        #expect(call.after?.people == ["grandpa"])
        #expect(call.after?.attribution == .rule("serc"))
    }

    // MARK: The sample file

    @Test func sampleRulesDecode() {
        let rules = Fixture.rules.assignmentRules
        #expect(rules.map(\.id) == ["serc", "busy", "swim", "golf"])
        #expect(rules[0].conditions == [RuleCondition(field: .title, op: .contains, value: "SERC")])
        #expect(rules[0].actions == [.assignTo(["grandpa"])])
        #expect(rules[0].enabled && rules[0].stop && rules[0].match == .all)
        #expect(rules[1].conditions.count == 2)
        #expect(rules[3].enabled == false)
    }
}

@Suite("Rules file v2: validation, colors, round trip")
struct RulesV2Tests {
    private func errors(_ edit: (inout [String: Any]) -> Void) -> [RulesIssue] {
        let result = Result { () throws(RulesError) in try RulesLoader.load(Fixture.rulesJSON(edit)) }
        guard case let .failure(error) = result else { return [] }
        return error.issues
    }

    private func editRule(_ index: Int, _ change: @escaping (inout [String: Any]) -> Void) -> (inout [String: Any]) -> Void {
        { rules in
            var list = rules["assignmentRules"] as! [[String: Any]]
            change(&list[index])
            rules["assignmentRules"] = list
        }
    }

    @Test func ruleWithoutConditionsOrActions() {
        #expect(errors(editRule(0) { $0["conditions"] = [] }).contains { $0.path == "assignmentRules[0].conditions" })
        #expect(errors(editRule(0) { $0["actions"] = [] }).contains { $0.path == "assignmentRules[0].actions" })
    }

    @Test func emptyMatchText() {
        let issues = errors(editRule(0) { $0["conditions"] = [["field": "title", "op": "contains", "value": " "]] })
        #expect(issues.contains { $0.path == "assignmentRules[0].conditions[0].value" })
    }

    @Test func unknownPersonInAnAction() {
        let issues = errors(editRule(0) { $0["actions"] = [["assignTo": ["grampa"]]] })
        #expect(issues.contains { $0.path == "assignmentRules[0].actions[0][0]" && $0.message.contains("Did you mean \"grandpa\"?") })
    }

    @Test func actionWithTwoKeys() {
        let issues = errors(editRule(0) { $0["actions"] = [["assignTo": ["grandpa"], "hide": true]] })
        #expect(issues.first?.message.contains("exactly one of") == true)
    }

    @Test func hideFalseIsRejected() {
        let issues = errors(editRule(1) { $0["actions"] = [["hide": false]] })
        #expect(issues.first?.message.contains("remove the action") == true)
    }

    @Test func unknownOperator() {
        let issues = errors(editRule(0) { $0["conditions"] = [["field": "title", "op": "has", "value": "SERC"]] })
        #expect(issues.first?.path == "assignmentRules[0].conditions[0].op")
    }

    @Test func duplicateRuleIDs() {
        let issues = errors(editRule(1) { $0["id"] = "serc" })
        #expect(issues.contains { $0.path == "assignmentRules[1].id" })
    }

    @Test func badColorAndPhoto() {
        let color = errors { rules in
            var people = rules["people"] as! [[String: Any]]
            people[0]["color"] = "blue"
            rules["people"] = people
        }
        #expect(color.first?.path == "people[0].color")
        let photo = errors { rules in
            var people = rules["people"] as! [[String: Any]]
            people[0]["photo"] = "../secrets.jpg"
            rules["people"] = people
        }
        #expect(photo.contains { $0.path == "people[0].photo" })
    }

    @Test func version1FilesStillLoad() throws {
        let v1 = Fixture.rulesJSON { rules in
            rules["schemaVersion"] = 1
            for key in ["assignmentRules", "reminderLists", "birthdays"] { rules.removeValue(forKey: key) }
            var people = rules["people"] as! [[String: Any]]
            for i in people.indices { people[i].removeValue(forKey: "color") }
            rules["people"] = people
        }
        let rules = try RulesLoader.load(v1).rules
        #expect(rules.assignmentRules.isEmpty)
        #expect(rules.birthdays.lookaheadDays == 30)
        // Without colors, people get palette colors by position.
        #expect(rules.laneColor(of: "dad") == LaneColor.palette[0])
        #expect(rules.laneColor(of: "kinder") == LaneColor.palette[2])
    }

    @Test func laneColors() {
        let plan = Fixture.plan("2026-10-21")
        #expect(plan.lane("Emma")?.color.hex == "#FF9F45")
        #expect(plan.lane("Twins")?.color.hex == "#3FD4C2")
        #expect(plan.lane("Twins")?.initials == "T")
        #expect(LaneColor(hex: "5e9eff")?.hex == "#5E9EFF")
        #expect(LaneColor(hex: "#12345") == nil)
        let rgb = LaneColor(hex: "#5E9EFF")!.rgb
        #expect(rgb.red == 94 && rgb.green == 158 && rgb.blue == 255)
        #expect(LaneColor.palette.count == LaneColor.paletteNames.count)
    }

    @Test(arguments: ["sample", "bundled"])
    func writerRoundTrips(_ which: String) throws {
        let rules = which == "sample"
            ? Fixture.rules
            : try RulesLoader.load(contentsOf: BundledRulesTests.url).rules
        let written = RulesWriter.data(rules)
        let reread = try RulesLoader.load(written).rules
        var expected = rules
        expected.schemaVersion = HouseholdRules.currentSchemaVersion
        #expect(reread == expected)
        // Writing again changes nothing: saves are stable.
        #expect(RulesWriter.data(reread) == written)
    }

    @Test func writerKeepsTheHandWrittenOrder() {
        let text = RulesWriter.text(Fixture.rules)
        let lines = text.components(separatedBy: "\n")
        #expect(lines[1] == "  \"$schema\": \"./household.schema.json\",")
        #expect(lines[2] == "  \"schemaVersion\": 2,")
        #expect(text.contains("{ \"id\": \"dad\", \"name\": \"Sam\", \"group\": \"parents\", \"aliases\": [\"Dad\"], \"color\": \"#5E9EFF\" }"))
        #expect(text.contains("\"name\": \"SERC → Jess\""))
        #expect(text.contains("{ \"date\": \"2026-10-23\", \"label\": \"Teacher in-service\" }"))
    }

    @Test func writerEscapesStrings() {
        #expect(JSONPrinter.quote("a \"b\" \\ c\nd") == "\"a \\\"b\\\" \\\\ c\\nd\"")
    }
}

@Suite("Needs from reminders, and birthdays")
struct RemindersAndBirthdaysTests {
    let planner = Fixture.planner

    func plan(_ iso: String, reminders: [SourceReminder] = [], birthdays: [SourceBirthday] = [], rules: HouseholdRules? = nil) -> DayPlan {
        let p = rules.map { try! DayPlanner(rules: $0) } ?? planner
        return p.plan(for: Fixture.date(iso), input: DayInput(calendarsOnDevice: Fixture.allCalendars, reminders: reminders, birthdays: birthdays))
    }

    @Test func remindersDueTodayOverdueOrUndatedShow() {
        let reminders = [
            SourceReminder(id: "1", listTitle: "Kids", title: "Form - Emma", due: Fixture.date("2026-10-21")),
            SourceReminder(id: "2", listTitle: "Kids", title: "Old form - Emma", due: Fixture.date("2026-10-19")),
            SourceReminder(id: "3", listTitle: "Kids", title: "Next week - Emma", due: Fixture.date("2026-10-28")),
            SourceReminder(id: "4", listTitle: "kids", title: "Sunscreen - Emma", due: nil),
        ]
        let need = plan("2026-10-21", reminders: reminders).needs.first { $0.people == ["kinder"] }
        #expect(need?.items == ["Library book", "Form - Emma", "Old form - Emma", "Sunscreen - Emma"])
    }

    @Test func unlistedListsAndUnnamedRemindersAreSkipped() {
        let reminders = [
            SourceReminder(id: "1", listTitle: "Groceries", title: "Milk for Emma", due: nil),
            SourceReminder(id: "2", listTitle: "Kids", title: "Buy diapers", due: nil),
        ]
        #expect(plan("2026-10-24", reminders: reminders).needs.isEmpty)
    }

    @Test func listDefaultOwnerCatchesUnnamedReminders() {
        var rules = Fixture.rules
        rules.reminderLists = [ReminderListRule(title: "Kids", defaultOwner: "twinA")]
        let needs = plan("2026-10-24", reminders: [SourceReminder(id: "2", listTitle: "Kids", title: "Buy diapers", due: nil)], rules: rules).needs
        #expect(needs == [KidNeed(people: ["twinA"], items: ["Buy diapers"])])
    }

    @Test func birthdaysWithinTheLookahead() {
        let plan = plan("2026-10-20", birthdays: SampleHousehold.contactBirthdays)
        #expect(plan.birthdays.map(\.name) == ["Aunt Jo", "Uncle Ray", "Leo & Max"])
        #expect(plan.birthdays.map(\.daysAway) == [4, 41, 50])
        #expect(plan.birthdays.map(\.turning) == [40, nil, 2])
        #expect(plan.birthdays[2].person == "twinA")
    }

    @Test func birthdayTodayAndLookaheadEdge() {
        var rules = Fixture.rules
        rules.birthdays.lookaheadDays = 4
        let plan = plan("2026-10-20", birthdays: [SourceBirthday(name: "Today", month: 10, day: 20), SourceBirthday(name: "Edge", month: 10, day: 24), SourceBirthday(name: "Past", month: 10, day: 25)], rules: rules)
        #expect(plan.birthdays.map(\.name) == ["Today", "Edge"])
        #expect(plan.birthdays.first?.daysAway == 0)
    }

    @Test func leapDayBirthdays() {
        #expect(PlanBuilderHooks.next(month: 2, day: 29, from: "2027-01-10") == "2027-02-28")
        #expect(PlanBuilderHooks.next(month: 2, day: 29, from: "2027-12-01") == "2028-02-29")
        #expect(PlanBuilderHooks.next(month: 1, day: 5, from: "2026-12-31") == "2027-01-05")
    }

    @Test func aContactWithAMembersNameAndDateIsShownOnce() {
        let plan = plan("2026-11-20", birthdays: [SourceBirthday(name: "Leo & Max", month: 12, day: 9)])
        #expect(plan.birthdays.filter { $0.name == "Leo & Max" }.count == 1)
    }

    @Test func travelAndOtherAllDayEventsAreNeverBirthdays() {
        let trip = SourceEvent(id: "t", calendarTitle: "Family", title: "Trip to Dallas", start: Fixture.clock.startOfDay(Fixture.date("2026-10-24")),
                               end: Fixture.clock.endOfDay(Fixture.date("2026-10-24")), isAllDay: true)
        let plan = planner.plan(for: Fixture.date("2026-10-20"), input: DayInput(events: [trip], calendarsOnDevice: Fixture.allCalendars))
        #expect(plan.birthdays.allSatisfy { !$0.name.contains("Dallas") })
    }
}

/// Reaches the planner's date helper with ISO strings.
enum PlanBuilderHooks {
    static func next(month: Int, day: Int, from iso: String) -> String? {
        DayPlanner.nextBirthday(month: month, day: day, onOrAfter: LocalDate(iso: iso)!)?.iso
    }
}
