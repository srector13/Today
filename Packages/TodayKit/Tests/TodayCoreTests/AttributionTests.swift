import Foundation
import Testing
@testable import TodayCore

@Suite("Title-name attribution")
struct AttributionTests {
    let planner = Fixture.planner
    var family: CalendarRule { Fixture.rules.calendars.first { $0.title == "Family" }! }
    var kates: CalendarRule { Fixture.rules.calendars.first { $0.title == "Kate" }! }

    @Test(arguments: [
        // No name: the shared calendar's default owner (Grandpa).
        ("Dentist", ["grandpa"]),
        ("Lunch at the club", ["grandpa"]),
        // A name wins, however it's attached.
        ("Dentist - Emma", ["kinder"]),
        ("Dentist – Emma", ["kinder"]),
        ("Dentist (Emma)", ["kinder"]),
        ("Dentist: Emma", ["kinder"]),
        ("Emma dentist", ["kinder"]),
        ("EMMA DENTIST", ["kinder"]),
        ("Emma's dentist", ["kinder"]),
        ("Emma’s dentist", ["kinder"]),
        // Several names, in title order.
        ("Birthday party — Emma & Nora", ["kinder", "pre"]),
        ("Nora, Emma swim", ["pre", "kinder"]),
        ("Mom & Dad date night", ["mom", "dad"]),
        // Aliases, including possessives and shared aliases.
        ("Papa golf", ["grandpa"]),
        ("Nana's book club", ["grandma"]),
        ("Twins checkup", ["twinA", "twinB"]),
        ("Leo shots", ["twinA"]),
        // Whole words only: names inside other words don't count.
        ("Emmaline's party", ["grandpa"]),
        ("Noranda meeting", ["grandpa"]),
        ("Maxwell House coffee run", ["grandpa"]),
    ])
    func sharedCalendar(_ title: String, _ expected: [PersonID]) {
        #expect(planner.owners(of: title, on: family).people == expected)
    }

    @Test func attributionIsRecorded() {
        #expect(planner.owners(of: "Dentist", on: family).attribution == .defaultOwner)
        #expect(planner.owners(of: "Dentist - Emma", on: family).attribution == .namedInTitle)
        #expect(planner.owners(of: "Dentist - Emma", on: kates).attribution == .calendarOwner)
    }

    @Test func personalCalendarKeepsTheOwnerAndAddsNamedPeople() {
        #expect(planner.owners(of: "Yoga", on: kates).people == ["mom"])
        #expect(planner.owners(of: "Dentist - Emma", on: kates).people == ["mom", "kinder"])
        #expect(planner.owners(of: "Call Mom", on: kates).people == ["mom"])
    }

    @Test func accentsAndMultiWordNames() {
        let people = [
            Person(id: "zoe", name: "Zoë", group: .kids, aliases: [], lane: nil, birthDate: nil),
            Person(id: "gma", name: "Grandma", group: .grandparents, aliases: [], lane: nil, birthDate: nil),
            Person(id: "gmajo", name: "Jo", group: .grandparents, aliases: ["Grandma Jo"], lane: nil, birthDate: nil),
        ]
        let attributor = TitleAttributor(people: people)
        #expect(attributor.people(namedIn: "zoe's recital") == ["zoe"])
        #expect(attributor.people(namedIn: "ZOË recital") == ["zoe"])
        // The longer alias wins at the same position.
        #expect(attributor.people(namedIn: "Lunch with Grandma Jo") == ["gmajo"])
        #expect(attributor.people(namedIn: "Lunch with Grandma") == ["gma"])
    }

    @Test func placeholderNamesNeverMatch() {
        let people = [Person(id: "kid", name: "<Eldest>", group: .kids, aliases: [], lane: nil, birthDate: nil)]
        #expect(TitleAttributor(people: people).people(namedIn: "Eldest checkup").isEmpty)
    }

    @Test func eventsLandOnTheAttributedLanes() throws {
        let plan = Fixture.plan("2026-10-20", events: [
            Fixture.event("Dentist", "2026-10-20", "10:00", "11:00"),
            Fixture.event("Twins checkup", "2026-10-20", "16:30", "17:00"),
        ])
        #expect(plan.lane("Grandpa")?.items.contains { $0.title == "Dentist" } == true)
        #expect(plan.lane("Grandma")?.items.contains { $0.title == "Dentist" } == false)
        // Both twins, one merged item on their shared lane.
        let twins = try #require(plan.lane("Twins"))
        let checkups = twins.items.filter { $0.title == "Twins checkup" }
        #expect(checkups.count == 1)
        #expect(checkups.first?.people == ["twinA", "twinB"])
        #expect(plan.lane("Grandpa")?.items.contains { $0.title == "Twins checkup" } == false)
    }

    @Test func calendarTitlesMatchIgnoringCase() {
        let plan = Fixture.plan("2026-10-21", events: [Fixture.event("Dentist", on: "family", "2026-10-21", "18:00", "19:00")],
                                calendars: ["family", "Sam", "Kate"])
        #expect(plan.items(for: "grandpa").contains { $0.title == "Dentist" })
    }

    @Test func eventsOnUnlistedCalendarsAreIgnored() {
        let plan = Fixture.plan("2026-10-21", events: [Fixture.event("Some observance", on: "US Holidays", "2026-10-21", "09:00", "10:00")],
                                calendars: Fixture.allCalendars.union(["US Holidays"]))
        #expect(plan.items.allSatisfy { $0.title != "Some observance" })
        #expect(plan.unlistedCalendars == ["US Holidays"])
    }

    @Test func multiDayEventsAreClippedToTheDay() throws {
        let trip = SourceEvent(id: "trip", calendarTitle: "Kate", title: "Conference",
                               start: Fixture.at("2026-10-20", "12:00"), end: Fixture.at("2026-10-22", "12:00"))
        let plan = Fixture.plan("2026-10-21", events: [trip])
        let item = try #require(plan.items(for: "mom").first)
        #expect(item.start == Fixture.clock.startOfDay(Fixture.date("2026-10-21")))
        #expect(item.end == Fixture.clock.endOfDay(Fixture.date("2026-10-21")))
        #expect(Fixture.plan("2026-10-23", events: [trip]).items(for: "mom").isEmpty)
    }
}
