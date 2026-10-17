import Foundation
import Testing
@testable import TodayCore

@Suite("Spoken brief")
struct BriefTests {
    let composer = BriefComposer(planner: Fixture.planner)

    func brief(_ date: LocalDate, _ hhmm: String, done: Set<String> = []) -> String {
        composer.brief(SampleHousehold.plan(for: date), now: Fixture.clock.instant(date, Fixture.time(hhmm)),
                       weather: SampleHousehold.weather(on: date), doneNeeds: done)
    }

    @Test(arguments: [("05:00", CheckInKind.morning), ("06:30", .morning), ("11:59", .morning),
                      ("12:00", .midday), ("15:14", .midday), ("15:15", .afternoon), ("22:00", .afternoon)])
    func theCheckInTimesPickTheBrief(_ hhmm: String, _ kind: CheckInKind) {
        #expect(composer.kind(at: Fixture.time(hhmm)) == kind)
    }

    @Test func morningCoversTheWholeDay() {
        let text = brief(SampleHousehold.tuesday, "06:30")
        #expect(text.hasPrefix("Good morning. It's Tuesday, October 20."))
        #expect(text.contains("Emma has school from 8:15 to 3:30 and Nora has preschool from 9 to 11:30."))
        #expect(text.contains("Jess & Grandma have Nora & Twins until pickup."))
        #expect(text.contains("Sam drives the pickup loop at 3:30: Emma at School, then Nora & Twins at Grandparents' at 3:45. Home around 4."))
        #expect(text.contains("Coming up: Team standup at 9 for Sam; Dentist at 10 for Jess;"))
        #expect(text.contains("All day: Picture day - Emma for Emma."))
        #expect(text.contains("Kate's calendar isn't on this iPhone, so I can't see Kate's day."))
        #expect(text.contains("Nora needs Backpack and Water bottle."))
        #expect(text.contains("It's 64 degrees and partly cloudy, with a high of 68."))
        #expect(text.contains("Rain likely around 4."))
        #expect(!text.contains("Busy"), "hidden by a rule")
    }

    @Test func middayIsAboutPickup() {
        let text = brief(SampleHousehold.tuesday, "14:40")
        #expect(text.hasPrefix("Here's the rest of Tuesday."))
        #expect(text.contains("Sam drives the pickup loop at 3:30"))
        #expect(text.contains("Rain is likely at pickup, so grab the umbrella."))
        #expect(text.contains("Coming up: Swim lesson (Emma) at 5:30 for Sam & Emma; SERC planning at 7 for Jess."))
        #expect(!text.contains("Dentist"), "already over")
        #expect(!text.contains("needs"), "needs are a morning thing")
    }

    @Test func afternoonAfterTheLoop() {
        let text = brief(SampleHousehold.tuesday, "16:30")
        #expect(text.hasPrefix("Here's the rest of today."))
        #expect(!text.contains("pickup loop at"))
        #expect(text.contains("Still to come: Swim lesson (Emma) at 5:30"))
        let late = brief(SampleHousehold.tuesday, "20:45")
        #expect(late.contains("Nothing else is on the calendars I can see."))
    }

    @Test func checkedOffNeedsAreSkipped() {
        let done: Set = [KidNeed.key(people: ["pre"], item: "Backpack")]
        #expect(brief(SampleHousehold.tuesday, "06:30", done: done).contains("Nora needs Water bottle."))
    }

    @Test func weekendBirthdays() {
        let text = brief(SampleHousehold.saturday, "07:00")
        #expect(text.contains("Aunt Jo turns 40 today. Happy birthday!"))
        #expect(!text.contains("pickup loop"))
    }

    @Test(arguments: SampleHousehold.seededDays)
    func neverCallsTimeFree(_ date: LocalDate) {
        for hhmm in ["06:30", "12:00", "15:15", "20:00"] {
            let text = brief(date, hhmm).lowercased()
            #expect(!text.contains("free"), "\(date) \(hhmm): \(text)")
            #expect(!text.contains("open time"), "\(date) \(hhmm)")
        }
    }

    @Test func aMissingSharedCalendarIsOneAlertNotEveryLane() {
        let plan = Fixture.planner.plan(for: SampleHousehold.wednesday, input: DayInput(calendarsOnDevice: ["Sam", "Kate"]))
        let text = composer.brief(plan, now: Fixture.at("2026-10-21", "06:30"), weather: nil)
        #expect(text.contains("The Family calendar isn't on this device"))
        #expect(!text.contains("so I can't see"))
    }
}

@Suite("Household editing")
struct HouseholdEditingTests {
    var rules = SampleHousehold.rules

    @Test func uniqueIDs() {
        #expect(HouseholdRules.uniqueID(from: "SERC → Jess", existing: []) == "serc-jess")
        #expect(HouseholdRules.uniqueID(from: "SERC → Jess", existing: ["serc-jess"]) == "serc-jess-2")
        #expect(HouseholdRules.uniqueID(from: "Zoë's  swim!", existing: []) == "zoe-s-swim")
        #expect(HouseholdRules.uniqueID(from: "→", existing: ["item"]) == "item-2")
    }

    @Test func newPeopleGetAnUnusedColor() {
        let person = rules.newPerson(name: "Ava")
        #expect(person.id == "ava")
        #expect(person.color == LaneColor(hex: "#64C8FF"))
    }

    @Test func moveToAddsAnExactTitleRuleAtTheTop() throws {
        var rules = rules
        let rule = rules.moveEvents(titled: "Dentist", to: ["dad"])
        #expect(rules.assignmentRules.first == rule)
        #expect(rule.name == "Dentist → Sam")
        #expect(rule.conditions == [RuleCondition(field: .title, op: .is, value: "Dentist")])
        let plan = try DayPlanner(rules: rules).plan(for: SampleHousehold.tuesday, input: SampleHousehold.input(on: SampleHousehold.tuesday))
        let dentist = try #require(plan.items.first { $0.title == "Dentist" })
        #expect(dentist.people == ["dad"])
        #expect(dentist.origin == .calendar(title: "Family", attribution: .rule("Dentist → Sam")))
        // Moving it again updates the same rule.
        let count = rules.assignmentRules.count
        rules.moveEvents(titled: "Dentist", to: ["mom"])
        #expect(rules.assignmentRules.count == count)
        #expect(rules.assignmentRules[0].name == "Dentist → Kate")
        #expect(RulesValidator.validate(rules).filter { $0.severity == .error }.isEmpty)
    }

    @Test func hideAndDraftRules() {
        var rules = rules
        let hide = rules.hideEvents(titled: "Busy", calendar: "Sam")
        #expect(hide.summary(names: Fixture.planner.names) == "If Title is \"Busy\" and Calendar is \"Sam\" → Hide from Today")
        let draft = rules.draftRule(containing: "SERC", assignTo: ["grandpa"])
        #expect(draft.name == "SERC → Jess" && draft.id == "serc-jess")
        #expect(draft.actions == [.assignTo(["grandpa"])])
        #expect(rules.draftRule().name == "New rule")
    }

    @Test func removingAPersonCleansUpAfterThem() {
        var rules = rules
        let refs = rules.references(to: "grandpa")
        #expect(refs.contains("the Family calendar"))
        #expect(refs.contains("\"With the grandparents\""))
        #expect(refs.contains("the rule \"SERC → Jess\""))
        rules.removePerson("grandpa")
        #expect(rules.person("grandpa") == nil)
        #expect(rules.calendars.first { $0.title == "Family" }?.defaultOwner == nil)
        #expect(rules.care.first?.caregivers == ["grandma"])
        #expect(!rules.assignmentRules.contains { $0.id == "serc" })
        #expect(rules.references(to: "grandpa").isEmpty)
    }

    @Test func calendarUses() {
        var rules = rules
        #expect(rules.use(ofCalendar: "family") == .shared(defaultOwner: "grandpa"))
        #expect(rules.use(ofCalendar: "US Holidays") == .ignored)
        rules.setUse(.personal(owner: "grandma"), ofCalendar: "Nana")
        #expect(rules.personalCalendar(of: "grandma") == "Nana")
        rules.setPersonalCalendar("Kate (work)", for: "mom")
        #expect(rules.personalCalendar(of: "mom") == "Kate (work)")
        #expect(!rules.calendars.contains { $0.title == "Kate" })
        rules.setUse(.ignored, ofCalendar: "Nana")
        #expect(rules.personalCalendar(of: "grandma") == nil)
    }

    @Test func householdText() {
        let text = HouseholdText(planner: Fixture.planner)
        #expect(text.block(rules.blocks[0]) == "Sam · every day · 8:30 AM–5:00 PM")
        #expect(text.block(rules.blocks[2]) == "Nora · Tue, Thu · 9:00 AM–11:30 AM · district calendar")
        #expect(text.schoolCalendar(rules.schoolCalendars["district"]!) == "14 school days off · 1 early release · Aug 19 – May 27")
        #expect(text.care(rules.care[0]) == "Jess & Grandma watch Nora & Twins · weekdays from 7:45 AM until pickup")
        #expect(text.loop(rules.pickupLoop!)
            == "Sam drives · weekdays, when school ends (5:00 PM without school) · School (Emma) → Grandparents' (Nora & Twins) → Home")
        #expect(text.checkIns(rules.checkIns) == "6:30 AM · 12:00 PM · 3:15 PM (Time Sensitive)")
        #expect(text.person(rules.person("dad")!) == "Sam calendar · also \"Dad\"")
        #expect(text.person(rules.person("twinA")!) == "shares the Twins lane · also \"Twins\"")
        #expect(text.person(rules.person("grandpa")!) == "Family calendar default · also \"Grandpa\", \"Papa\"")
    }

    @Test func builtInRules() {
        let builtIns = BuiltInRule.all(Fixture.planner)
        #expect(builtIns.map(\.name) == ["Names in titles", "Personal calendars", "Family calendar default"])
        #expect(builtIns[2].summary == "Anything on Family that names nobody goes to Jess.")
    }
}

@Suite("Home location")
struct HomeLocationTests {
    @Test func roundTripsThroughTheWriter() throws {
        var rules = SampleHousehold.rules
        rules.home = .rounded(latitude: 41.878_14, longitude: -87.629_81, label: "Home")
        #expect(rules.home == HomeLocation(latitude: 41.878, longitude: -87.63, label: "Home"))
        let text = RulesWriter.text(rules)
        #expect(text.contains("\"home\": { \"latitude\": 41.878, \"longitude\": -87.63, \"label\": \"Home\" }"))
        let reloaded = try RulesLoader.load(Data(text.utf8)).rules
        #expect(reloaded == rules)
    }

    @Test func numbers() {
        #expect(JSONPrinter.number(42) == "42")
        #expect(JSONPrinter.number(-87.63) == "-87.63")
        #expect(JSONPrinter.number(0.001) == "0.001")
    }

    @Test func outOfRangeIsAnError() {
        var rules = SampleHousehold.rules
        rules.home = HomeLocation(latitude: 91, longitude: 0)
        #expect(RulesValidator.validate(rules).contains { $0.path == "home.latitude" && $0.severity == .error })
    }

    @Test func unknownKeysAreRejected() {
        let data = Fixture.rulesJSON { $0["home"] = ["latitude": 41.9, "longitude": -87.6, "zoom": 3] }
        #expect(throws: RulesError.self) { try RulesLoader.load(data) }
    }
}
