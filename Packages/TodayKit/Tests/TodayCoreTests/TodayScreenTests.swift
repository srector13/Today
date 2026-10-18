import Foundation
import Testing
@testable import TodayCore

/// The logic behind the Today screen: the lanes' window and layout, "Up
/// next", the "why is this here?" text and display formats.
@Suite("Today screen")
struct TodayScreenTests {
    let planner = Fixture.planner

    func seeded(_ date: LocalDate) -> DayPlan {
        SampleHousehold.plan(for: date)
    }

    // MARK: Window

    @Test func restOfTodayStartsAtTheCurrentHour() {
        let plan = seeded(SampleHousehold.tuesday)
        let window = TimelineWindow.restOfDay(plan, now: Fixture.at("2026-10-20", "14:40"))
        #expect(window.isRestOfDay)
        #expect(window.start == Fixture.time("14:00") && window.end == Fixture.time("21:00"))
        #expect(window.label == "2 PM – 9 PM")
        let marks = window.hourMarks(clock: plan.clock)
        #expect(marks.map(\.label) == ["2 PM", "3", "4", "5", "6", "7", "8", "9"])
        #expect(marks.first?.fraction == 0 && marks.last?.fraction == 1)
        #expect(abs(window.fraction(Fixture.at("2026-10-20", "14:40")) - 40.0 / 420) < 1e-9)
    }

    @Test func wholeDayBeforeTheWindowOpensOrOnAnotherDay() {
        let plan = seeded(SampleHousehold.tuesday)
        #expect(!TimelineWindow.restOfDay(plan, now: Fixture.at("2026-10-20", "05:30")).isRestOfDay)
        #expect(!TimelineWindow.restOfDay(plan, now: Fixture.at("2026-10-20", "20:15")).isRestOfDay)
        #expect(!TimelineWindow.restOfDay(plan, now: Fixture.at("2026-10-19", "14:40")).isRestOfDay)
        let day = TimelineWindow.day(plan)
        #expect(day.label == "6 AM – 9 PM")
        // Fifteen hours: a mark every third hour.
        #expect(day.hourMarks(clock: plan.clock).map(\.label) == ["6 AM", "9", "12", "3", "6", "9"])
        #expect(day.fraction(Fixture.at("2026-10-20", "03:00")) == 0)
    }

    // MARK: Lanes

    @Test func overlappingCallAndLoopShareTheLaneInRows() throws {
        let plan = seeded(SampleHousehold.wednesday)
        let sam = try #require(plan.lane("Sam"))
        let window = TimelineWindow.restOfDay(plan, now: Fixture.at("2026-10-21", "14:40"))
        let blocks = LaneLayout.blocks(for: sam, in: window)
        let work = try #require(blocks.first { $0.item.id == "block:work" })
        #expect(work.style == .background && work.rows == 1)
        let call = try #require(blocks.first { $0.item.title == "Call with vendor" })
        let loop = try #require(blocks.first { $0.item.id == "loop" })
        #expect(call.style == .normal && loop.style == .high)
        #expect(call.rows == 2 && loop.rows == 2 && call.row != loop.row)
        // Nothing before 2 PM is drawn.
        #expect(!blocks.contains { $0.item.title == "Team standup" })
        // The SERC rule moved Sam's board call to Jess.
        #expect(!blocks.contains { $0.item.title == "SERC board call" })
    }

    @Test func separateItemsKeepTheFullHeight() throws {
        let plan = seeded(SampleHousehold.tuesday)
        let emma = try #require(plan.lane("Emma"))
        let blocks = LaneLayout.blocks(for: emma, in: TimelineWindow.day(plan))
        let foreground = blocks.filter { $0.style != .background }
        #expect(!foreground.isEmpty && foreground.allSatisfy { $0.rows == 1 })
        #expect(blocks.contains { $0.item.id == "block:school" && $0.style == .background })
        // All-day items are chips, not bars.
        #expect(!blocks.contains { $0.item.isAllDay })
        #expect(LaneLayout.allDay(for: emma).map(\.title) == ["Picture day - Emma"])
    }

    @Test func threeWayOverlapUsesThreeRows() throws {
        let events = [
            Fixture.event("A", on: "Sam", "2026-10-24", "10:00", "11:00"),
            Fixture.event("B", on: "Sam", "2026-10-24", "10:30", "11:30"),
            Fixture.event("C", on: "Sam", "2026-10-24", "10:45", "12:00"),
            Fixture.event("D", on: "Sam", "2026-10-24", "11:00", "11:15"),
            Fixture.event("E", on: "Sam", "2026-10-24", "13:00", "14:00"),
        ]
        let plan = Fixture.plan("2026-10-24", events: events)
        let blocks = LaneLayout.blocks(for: try #require(plan.lane("Sam")), in: TimelineWindow.day(plan))
            .filter { $0.style != .background }
        let byTitle = Dictionary(uniqueKeysWithValues: blocks.map { ($0.item.title, $0) })
        #expect(byTitle["A"]?.rows == 3 && byTitle["B"]?.rows == 3 && byTitle["C"]?.rows == 3)
        #expect(Set([byTitle["A"]!.row, byTitle["B"]!.row, byTitle["C"]!.row]) == [0, 1, 2])
        // D starts when A ends, so it reuses A's row.
        #expect(byTitle["D"]?.row == byTitle["A"]?.row)
        #expect(byTitle["E"]?.rows == 1)
    }

    @Test func noDataLaneHasNoBlocksButKeepsItsRules() throws {
        let plan = seeded(SampleHousehold.tuesday)
        let kate = try #require(plan.lane("Kate"))
        #expect(!kate.data.isKnown)
        #expect(LaneLayout.blocks(for: kate, in: TimelineWindow.day(plan)).isEmpty)
    }

    // MARK: List view

    @Test func aLaneAsAListShowsWhatsLeftOfToday() throws {
        let plan = seeded(SampleHousehold.wednesday)
        let sam = try #require(plan.lane("Sam"))
        let rows = LaneAgenda.rows(for: sam, now: Fixture.at("2026-10-21", "14:40"), clock: plan.clock)
        #expect(rows.map(\.item.title) == ["Work", "Call with vendor", "Pickup loop"])
        #expect(rows.map(\.time) == ["Now", "3:15 PM", "3:30 PM"])
        #expect(rows[0].detail == "Until 5:00 PM" && rows[0].style == .background)
        #expect(rows[2].detail == "School 3:30 → Grandparents' 3:45 → home ~4:00" && rows[2].style == .high)
    }

    @Test func anotherDayListsTheWholeDayWithAllDayItemsFirst() throws {
        let plan = seeded(SampleHousehold.tuesday)
        let emma = try #require(plan.lane("Emma"))
        let rows = LaneAgenda.rows(for: emma, now: nil, clock: plan.clock)
        #expect(rows.first?.time == "All day" && rows.first?.item.title == "Picture day - Emma")
        #expect(rows.dropFirst().map(\.item.start) == rows.dropFirst().map(\.item.start).sorted())
        #expect(rows.contains { $0.item.id == "block:school" && $0.time == "8:15 AM" && $0.detail == "Until 3:30 PM" })
        #expect(!rows.contains { $0.time == "Now" })
        let serc = try #require(plan.lane("Jess").flatMap { LaneAgenda.rows(for: $0, now: nil, clock: plan.clock) }?
            .first { $0.item.title == "SERC planning" })
        #expect(serc.detail == "Until \(plan.clock.localTime(of: serc.item.end).twelveHour) · Library annex")
    }

    // MARK: Up next

    @Test func theLoopIsUpNextWithinNinetyMinutes() throws {
        let plan = seeded(SampleHousehold.wednesday)
        let next = try #require(NextUp.find(in: plan, now: Fixture.at("2026-10-21", "14:40")))
        // The vendor call (3:15) is earlier, but the loop matters more.
        #expect(next.item.id == "loop")
        #expect(next.loop?.stops.map(\.place) == ["School", "Grandparents'"])
        #expect(next.subtitle(planner: planner, now: Fixture.at("2026-10-21", "14:40")) == "3:30 PM · in 50 min · Sam drives")
        #expect(next.shortLine(clock: plan.clock) == "Pickup loop 3:30")
        #expect(next.subtitle(planner: planner, now: Fixture.at("2026-10-21", "00:00"), relative: false) == "3:30 PM · Sam drives")
    }

    @Test func earlierOrdinaryItemsWinWhenTheLoopIsFarOff() throws {
        let plan = seeded(SampleHousehold.wednesday)
        let underway = try #require(NextUp.find(in: plan, now: Fixture.at("2026-10-21", "13:10")))
        #expect(underway.item.title == "Nana's book club" && underway.isUnderway)
        #expect(underway.subtitle(planner: planner, now: Fixture.at("2026-10-21", "13:10")) == "Now until 2:30 PM · Grandma")
        let morning = try #require(NextUp.find(in: plan, now: Fixture.at("2026-10-21", "09:00")))
        #expect(morning.item.title == "Client review")
    }

    @Test func backgroundAndRidesAreNeverUpNext() throws {
        let plan = seeded(SampleHousehold.tuesday)
        let late = try #require(NextUp.find(in: plan, now: Fixture.at("2026-10-20", "16:30")))
        #expect(late.item.title == "Swim lesson (Emma)")
        #expect(NextUp.find(in: plan, now: Fixture.at("2026-10-20", "20:45")) == nil)
    }

    // MARK: Why is this here?

    @Test func explainsARule() throws {
        let plan = seeded(SampleHousehold.tuesday)
        let serc = try #require(plan.items.first { $0.title == "SERC planning" })
        let why = planner.explain(serc)
        #expect(why.headline == "On Jess's lane")
        #expect(why.reasons == ["Rule \"SERC → Jess\" · Title contains \"SERC\""])
        #expect(why.source == "Family calendar · Library annex")
        #expect(why.isEvent && why.calendarTitle == "Family")
    }

    @Test func explainsTheBuiltInAttribution() throws {
        let plan = seeded(SampleHousehold.tuesday)
        let dentist = try #require(plan.items.first { $0.title == "Dentist" })
        #expect(planner.explain(dentist).reasons == ["The title names nobody, so the Family calendar's default, Jess, gets it."])
        let swim = try #require(plan.items.first { $0.title == "Swim lesson (Emma)" })
        let why = planner.explain(swim)
        #expect(why.headline == "On Emma's & Sam's lanes")
        #expect(why.reasons == ["The title names Emma.", "Rule \"Sam takes swim\": Also include Sam"])
        let standup = try #require(plan.items.first { $0.title == "Team standup" })
        #expect(planner.explain(standup).reasons == ["It's on Sam's own calendar."])
    }

    @Test func explainsHouseholdRules() throws {
        let plan = seeded(SampleHousehold.tuesday)
        let school = try #require(plan.items.first { $0.id == "block:school" })
        #expect(planner.explain(school).reasons == ["The School block: weekdays, 8:15 AM–3:30 PM, minus the district calendar's days off."])
        #expect(!planner.explain(school).isEvent)
        let twins = try #require(plan.lane("Twins")?.items.first { $0.kind == .care })
        #expect(planner.explain(twins).headline == "On Twins' lane")
        #expect(planner.explain(twins).reasons == ["Care: Jess & Grandma have Nora & Twins weekdays from 7:45 AM until pickup."])
        let loop = try #require(plan.items.first { $0.id == "loop" })
        #expect(planner.explain(loop).reasons
            == ["The pickup loop: Sam drives School → Grandparents' → home, when school ends (5:00 PM without school)."])
    }

    // MARK: Formats

    @Test func displayFormats() {
        let date = Fixture.date("2026-10-24")
        #expect(DisplayFormat.monthDay(date) == "October 24")
        #expect(DisplayFormat.weekdayShortDate(date) == "Saturday, Oct 24")
        #expect(DisplayFormat.shortDate(date) == "Sat Oct 24")
        #expect(DisplayFormat.longDate(Fixture.date("2021-05-14")) == "May 14, 2021")
        #expect(DisplayFormat.relativeDays(0) == "today" && DisplayFormat.relativeDays(1) == "tomorrow")
        #expect(DisplayFormat.relativeDays(4) == "in 4 days")
        #expect(DisplayFormat.span(Fixture.time("09:00"), Fixture.time("11:30")) == "9–11:30")
        #expect(DisplayFormat.span(Fixture.time("08:15"), Fixture.time("15:30")) == "8:15–3:30")
        #expect(DisplayFormat.days(.weekdays) == "weekdays")
        #expect(DisplayFormat.days(DaySet([.thu, .tue])) == "Tue, Thu")
        let now = Fixture.at("2026-10-24", "14:40")
        #expect(DisplayFormat.until(Fixture.at("2026-10-24", "15:30"), from: now) == "in 50 min")
        #expect(DisplayFormat.until(Fixture.at("2026-10-24", "15:50"), from: now) == "in 1 hr 10 min")
        #expect(DisplayFormat.until(Fixture.at("2026-10-24", "19:00"), from: now) == "in 4 hr")
        #expect(DisplayFormat.until(Fixture.at("2026-10-24", "14:00"), from: now) == "now")
        #expect(DisplayFormat.possessive("Jess") == "Jess's")
        #expect(DisplayFormat.possessive("Twins", plural: true) == "Twins'")
    }

    @Test func weatherHelpers() {
        let weather = SampleHousehold.weather(on: SampleHousehold.tuesday)
        let now = Fixture.at("2026-10-20", "14:40")
        #expect(weather.hours(from: now, count: 5).map(\.temperature) == [63, 64, 64, 62, 60])
        #expect(weather.rainChance(from: Fixture.at("2026-10-20", "15:30"), through: Fixture.at("2026-10-20", "16:00")) == 0.6)
        #expect(weather.rainChance(from: Fixture.at("2026-10-20", "12:10"), through: Fixture.at("2026-10-20", "13:50")) == 0.1)
        #expect(weather.firstLikelyRain(after: now, before: Fixture.at("2026-10-20", "21:00"))?.time == Fixture.at("2026-10-20", "16:00"))
        #expect(WeatherSnapshot.percent(0.45) == "50%" && WeatherSnapshot.percent(0.12) == "10%")
    }
}
