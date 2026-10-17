import Foundation
import Testing
@testable import TodayCore

@Suite("School-day detection")
struct SchoolDayTests {
    let planner = Fixture.planner

    @Test(arguments: [
        ("2026-10-19", true),  // Mon
        ("2026-10-20", true),  // Tue
        ("2026-10-22", true),  // Thu
        ("2026-10-23", false), // Fri, teacher in-service
        ("2026-10-24", false), // Sat
        ("2026-10-25", false), // Sun
        ("2026-11-24", true),  // Tue before Thanksgiving break
        ("2026-11-25", false), // Thanksgiving break, first day
        ("2026-11-27", false), // Thanksgiving break, last day
        ("2026-11-30", true),  // back
        ("2026-12-21", false), // winter break starts
        ("2027-01-01", false), // winter break ends
        ("2027-01-04", true),  // back
        ("2026-08-18", false), // before the first day
        ("2026-08-19", true),  // first day (Wed)
        ("2027-05-27", true),  // last day (Thu)
        ("2027-05-28", false), // summer
    ])
    func kindergarten(_ iso: String, _ expected: Bool) {
        #expect(planner.isSchoolDay("school", on: Fixture.date(iso)) == expected)
    }

    @Test(arguments: [
        ("2026-10-19", false), // Mon
        ("2026-10-20", true),  // Tue
        ("2026-10-21", false), // Wed
        ("2026-10-22", true),  // Thu
        ("2026-10-24", false), // Sat
        ("2026-11-26", false), // Thanksgiving Thursday
    ])
    func preschoolOnlyTuesdayAndThursday(_ iso: String, _ expected: Bool) {
        #expect(planner.isSchoolDay("preschool", on: Fixture.date(iso)) == expected)
    }

    @Test func schoolIsAddedFromRulesNotCalendars() throws {
        // No events at all: school still appears, 8:15–3:30.
        let plan = Fixture.plan("2026-10-21")
        #expect(plan.schedule(for: "kinder").first == "08:15–15:30 School")
        let status = try #require(plan.school("school"))
        #expect(status.state == .inSession(start: Fixture.time("08:15"), end: Fixture.time("15:30"), earlyRelease: false))
    }

    @Test func dayOffAlertsAndFlagsTheUncoveredKid() {
        let plan = Fixture.plan("2026-10-23")
        #expect(plan.school("school")?.state == .noSchool(label: "Teacher in-service"))
        #expect(plan.alerts(.noSchool).map(\.message) == ["No school today (Teacher in-service)."])
        // Emma isn't in any care rule, so someone has to decide who has her.
        #expect(plan.alerts(.uncoveredKid).map(\.people) == [["kinder"]])
        #expect(plan.items(for: "kinder").isEmpty)
    }

    @Test func summerIsOutOfTermWithoutAnAlert() {
        let plan = Fixture.plan("2027-06-02")
        #expect(plan.school("school")?.state == .outOfTerm)
        #expect(plan.alerts(.noSchool).isEmpty)
    }

    @Test func earlyReleaseShortensSchoolAndAlerts() {
        let plan = Fixture.plan("2026-12-18")
        #expect(plan.school("school")?.state == .inSession(start: Fixture.time("08:15"), end: Fixture.time("12:30"), earlyRelease: true))
        #expect(plan.schedule(for: "kinder").first == "08:15–12:30 School")
        #expect(plan.alerts(.earlyRelease).map(\.message) == ["Early release: School ends 12:30 instead of 3:30."])
    }

    @Test func weekendHasNoSchoolStatusesOrAlerts() {
        let plan = Fixture.plan("2026-10-24")
        #expect(plan.schools.isEmpty)
        #expect(plan.alerts.isEmpty)
        #expect(plan.isWeekend)
    }

    @Test func workBlockRunsEveryDayIncludingWeekends() {
        for iso in ["2026-10-20", "2026-10-23", "2026-10-24", "2026-10-25"] {
            #expect(Fixture.plan(iso).schedule(for: "dad").first == "08:30–17:00 Work", "\(iso)")
        }
    }
}
