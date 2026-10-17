import Foundation
import Testing
@testable import TodayCore

@Suite("Pickup loop")
struct PickupLoopTests {
    @Test func schoolDayLoopGoesSchoolThenGrandparentsThenHome() throws {
        let plan = Fixture.plan("2026-10-21")
        let loop = try #require(plan.pickupLoop)
        #expect(loop.driver == "dad")
        #expect(loop.start == Fixture.time("15:30"))
        #expect(loop.stops.map(\.place) == ["School", "Grandma & Grandpa's"])
        #expect(loop.stops.map(\.time) == [Fixture.time("15:30"), Fixture.time("15:45")])
        #expect(loop.stops.map(\.kids) == [["kinder"], ["pre", "twinA", "twinB"]])
        #expect(loop.end == Fixture.time("16:00"))
        #expect(!loop.usedFallbackStart)
    }

    @Test func driversLoopItemMattersMost() throws {
        let plan = Fixture.plan("2026-10-21")
        let item = try #require(plan.items.first { $0.id == "loop" })
        #expect(item.people == ["dad"])
        #expect(item.importance == .high)
        #expect(item.detail == "School 3:30 → Grandma & Grandpa's 3:45 → home ~4:00")
        // A school-day afternoon is never free: Dad has work plus the loop.
        #expect(plan.schedule(for: "dad") == ["08:30–17:00 Work", "15:30–16:00 Pickup loop"])
    }

    @Test func kidsRideFromTheirStop() {
        let plan = Fixture.plan("2026-10-21")
        #expect(plan.schedule(for: "kinder").last == "15:30–16:00 Pickup → home")
        #expect(plan.schedule(for: "twinA").last == "15:45–16:00 Pickup → home")
        let rides = plan.items.filter { $0.kind == .pickupLoop && $0.id != "loop" }
        #expect(rides.allSatisfy { $0.importance == .low })
    }

    @Test func noSchoolWeekdaySkipsTheSchoolStopAndUsesTheFallback() throws {
        let loop = try #require(Fixture.plan("2026-10-23").pickupLoop)
        #expect(loop.usedFallbackStart)
        #expect(loop.start == Fixture.time("17:00"))
        #expect(loop.stops.map(\.place) == ["Grandma & Grandpa's"])
        #expect(loop.stops.first?.time == Fixture.time("17:00"))
        #expect(loop.end == Fixture.time("17:15"))
    }

    @Test func earlyReleaseMovesTheLoop() throws {
        let loop = try #require(Fixture.plan("2026-12-18").pickupLoop)
        #expect(loop.start == Fixture.time("12:30"))
        #expect(loop.stops.map(\.time) == [Fixture.time("12:30"), Fixture.time("12:45")])
    }

    @Test(arguments: ["2026-10-24", "2026-10-25"])
    func noLoopOnWeekends(_ iso: String) {
        let plan = Fixture.plan(iso)
        #expect(plan.pickupLoop == nil)
        #expect(plan.items.allSatisfy { $0.kind != .pickupLoop })
    }

    @Test func withoutAFallbackANoSchoolDayHasNoLoopAndSaysSo() throws {
        let planner = try Fixture.planner { rules in
            var loop = rules["pickupLoop"] as! [String: Any]
            loop.removeValue(forKey: "fallbackStart")
            rules["pickupLoop"] = loop
        }
        let plan = Fixture.plan("2026-10-23", planner: planner)
        #expect(plan.pickupLoop == nil)
        #expect(plan.alerts(.noLoopTime).count == 1)
    }

    @Test func driverAppointmentDuringTheLoopAlerts() {
        let plan = Fixture.plan("2026-10-21", events: [
            Fixture.event("Call with vendor", on: "Sam", "2026-10-21", "15:15", "15:45"),
            Fixture.event("Standup", on: "Sam", "2026-10-21", "09:00", "09:15"),
        ])
        #expect(plan.alerts(.loopConflict).map(\.message) == [
            "Sam: Call with vendor 3:15–3:45 overlaps the pickup loop (3:30–4:00).",
        ])
    }

    @Test func appointmentRightAfterTheLoopDoesNotAlert() {
        let plan = Fixture.plan("2026-10-21", events: [
            Fixture.event("Call", on: "Sam", "2026-10-21", "16:00", "16:30"),
        ])
        #expect(plan.alerts(.loopConflict).isEmpty)
    }
}

@Suite("In-law coverage")
struct CoverageTests {
    @Test func preschoolDaySplitsHerCareAroundPreschool() {
        let plan = Fixture.plan("2026-10-20")
        #expect(plan.schedule(for: "pre") == [
            "07:45–09:00 With Grandma & Grandpa",
            "09:00–11:30 Preschool",
            "11:30–15:45 With Grandma & Grandpa",
            "15:45–16:00 Pickup → home",
        ])
    }

    @Test func noPreschoolMeansAllDayWithTheGrandparents() {
        let plan = Fixture.plan("2026-10-21")
        #expect(plan.schedule(for: "pre") == [
            "07:45–15:45 With Grandma & Grandpa",
            "15:45–16:00 Pickup → home",
        ])
    }

    @Test func twinsAreWithTheGrandparentsUntilTheirStop() throws {
        let plan = Fixture.plan("2026-10-20")
        let twins = try #require(plan.lane("Twins"))
        #expect(twins.people == ["twinA", "twinB"])
        let care = twins.items.filter { $0.kind == .care }
        #expect(care.count == 1)
        #expect(care.first?.people == ["twinA", "twinB"])
        #expect(plan.schedule(for: "twinB").first == "07:45–15:45 With Grandma & Grandpa")
    }

    @Test func grandparentsSeeWhoTheyAreWatching() {
        let plan = Fixture.plan("2026-10-20")
        for grandparent in ["grandpa", "grandma"] {
            #expect(plan.schedule(for: grandparent).first == "07:45–15:45 Watching Nora & Twins")
        }
    }

    @Test func kindergartnerIsNeverInTheGrandparentsCare() {
        let plan = Fixture.plan("2026-10-21")
        #expect(plan.items(for: "kinder").allSatisfy { $0.kind != .care })
    }

    @Test func noSchoolDayCareRunsToTheFallbackLoop() {
        let plan = Fixture.plan("2026-10-23")
        #expect(plan.schedule(for: "twinA").first == "07:45–17:00 With Grandma & Grandpa")
    }

    @Test func noCareOnWeekends() {
        let plan = Fixture.plan("2026-10-24")
        #expect(plan.items.allSatisfy { $0.kind != .care })
    }

    @Test func grandparentAppointmentDuringCareAlerts() {
        let plan = Fixture.plan("2026-10-20", events: [Fixture.event("Dentist", "2026-10-20", "10:00", "11:00")])
        #expect(plan.alerts(.careConflict).map(\.message) == [
            "Grandpa: Dentist 10:00–11:00 while watching the kids (7:45–3:45).",
        ])
        #expect(plan.alerts(.careConflict).first?.people == ["grandpa"])
    }

    @Test func grandparentEveningAppointmentDoesNotAlert() {
        let plan = Fixture.plan("2026-10-20", events: [Fixture.event("Dinner", "2026-10-20", "18:00", "19:00")])
        #expect(plan.alerts(.careConflict).isEmpty)
    }

    @Test func kidsOwnAppointmentIsNotAGrandparentConflict() {
        let plan = Fixture.plan("2026-10-20", events: [Fixture.event("Twins checkup", "2026-10-20", "10:00", "11:00")])
        #expect(plan.alerts(.careConflict).isEmpty)
    }

    @Test func bothGrandparentsNamedAlertsOnceForBoth() {
        let plan = Fixture.plan("2026-10-21", events: [Fixture.event("Grandma & Grandpa: bank", "2026-10-21", "13:00", "13:30")])
        #expect(plan.alerts(.careConflict).map(\.people) == [["grandma", "grandpa"]])
    }
}

@Suite("Lanes and needs")
struct LaneAndNeedsTests {
    @Test func lanesAreGroupedUsKidsGrandparents() {
        let plan = Fixture.plan("2026-10-21")
        #expect(plan.laneGroups.map(\.group) == [.parents, .kids, .grandparents])
        #expect(plan.laneGroups.map { $0.lanes.map(\.label) } == [
            ["Sam", "Kate"], ["Emma", "Nora", "Twins"], ["Grandpa", "Grandma"],
        ])
    }

    @Test func missingPersonalCalendarIsNoDataNotFree() {
        let plan = Fixture.plan("2026-10-20", calendars: ["Family", "Sam"])
        let kate = plan.lane("Kate")
        #expect(kate?.data == .noData(reason: "the \"Kate\" calendar isn't on this device"))
        #expect(plan.missingCalendars == ["Kate"])
        // The other lanes are still known.
        #expect(plan.lane("Sam")?.data == .known)
        #expect(plan.lane("Grandpa")?.data == .known)
    }

    @Test func presentButEmptyCalendarIsKnown() {
        let plan = Fixture.plan("2026-10-21")
        #expect(plan.lane("Kate")?.data == .known)
        #expect(plan.lane("Kate")?.items.isEmpty == true)
    }

    @Test func missingSharedCalendarBlanksTheDefaultOwnerAndAlerts() {
        let plan = Fixture.plan("2026-10-21", calendars: ["Sam", "Kate"])
        #expect(plan.lane("Grandpa")?.data.isKnown == false)
        #expect(plan.alerts(.missingCalendar).count == 1)
    }

    @Test func noCalendarAccessAtAllBlanksEveryCalendarLane() {
        let plan = Fixture.plan("2026-10-21", calendars: [])
        #expect(plan.lane("Sam")?.data.isKnown == false)
        #expect(plan.lane("Kate")?.data.isKnown == false)
        #expect(plan.lane("Grandpa")?.data.isKnown == false)
        // Rules still draw what they know.
        #expect(plan.schedule(for: "kinder").first == "08:15–15:30 School")
    }

    @Test func needsFollowBlocksAndWeekdays() {
        let tuesday = Fixture.plan("2026-10-20")
        #expect(tuesday.needs == [
            KidNeed(people: ["pre"], items: ["Backpack", "Water bottle"]),
            KidNeed(people: ["twinA", "twinB"], items: ["Diaper bag"]),
        ])
        let wednesday = Fixture.plan("2026-10-21")
        #expect(wednesday.needs.first == KidNeed(people: ["kinder"], items: ["Library book"]))
        #expect(Fixture.plan("2026-10-24").needs.isEmpty)
        // The library book needs school to run, even on a Wednesday.
        #expect(Fixture.plan("2026-11-25").needs.allSatisfy { !$0.people.contains("kinder") })
    }
}
