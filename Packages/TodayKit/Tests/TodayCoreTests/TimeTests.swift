import Foundation
import Testing
@testable import TodayCore

@Suite("Local dates and times")
struct LocalDateTimeTests {
    @Test func parsesAndPrintsISODates() {
        #expect(LocalDate(iso: "2026-10-20")?.iso == "2026-10-20")
        #expect(LocalDate(iso: "2028-02-29") != nil)
        #expect(LocalDate(iso: "2027-02-29") == nil)
        #expect(LocalDate(iso: "2026-13-01") == nil)
        #expect(LocalDate(iso: "2026-10-2") == nil)
        #expect(LocalDate(iso: "10/20/2026") == nil)
    }

    @Test func weekdays() {
        #expect(LocalDate(iso: "1970-01-01")?.weekday == .thu)
        #expect(LocalDate(iso: "2026-10-17")?.weekday == .sat)
        #expect(LocalDate(iso: "2026-10-20")?.weekday == .tue)
        #expect(LocalDate(iso: "2026-10-21")?.weekday == .wed)
        #expect(LocalDate(iso: "2026-10-24")?.weekday == .sat)
        #expect(LocalDate(iso: "1969-12-31")?.weekday == .wed)
    }

    @Test func dayArithmeticCrossesMonthsYearsAndLeapDays() {
        let date = LocalDate(iso: "2026-12-31")!
        #expect(date.adding(days: 1).iso == "2027-01-01")
        #expect(LocalDate(iso: "2028-02-28")!.adding(days: 1).iso == "2028-02-29")
        #expect(LocalDate(iso: "2026-03-01")!.adding(days: -1).iso == "2026-02-28")
        for offset in [-800_000, -1, 0, 1, 20_000, 400_000] {
            let roundTrip = LocalDate(dayNumber: offset)
            #expect(roundTrip.dayNumber == offset)
        }
    }

    @Test(arguments: ["08:15", "8:15", "00:00", "23:59", "15:30"])
    func acceptsTimes(_ text: String) {
        #expect(LocalTime(text) != nil)
    }

    @Test(arguments: ["24:00", "8:5", "815", "08.15", "8:15 PM", "-1:00", "", "１:００"])
    func rejectsTimes(_ text: String) {
        #expect(LocalTime(text) == nil)
    }

    @Test func timeFormats() {
        let time = LocalTime("15:30")!
        #expect(time.hhmm == "15:30")
        #expect(time.short == "3:30")
        #expect(time.twelveHour == "3:30 PM")
        #expect(LocalTime("00:05")!.twelveHour == "12:05 AM")
        #expect(LocalTime("12:00")!.twelveHour == "12:00 PM")
        #expect(LocalTime("23:50")!.adding(minutes: 15) == nil)
    }

    @Test func daySetsDecodeWordsAndLists() throws {
        func decode(_ json: String) throws -> DaySet {
            try JSONDecoder().decode(DaySet.self, from: Data(json.utf8))
        }
        #expect(try decode("\"daily\"") == .daily)
        #expect(try decode("\"weekdays\"") == .weekdays)
        #expect(try decode("[\"tue\", \"THU\"]").days == [.tue, .thu])
        #expect(throws: DecodingError.self) { try decode("\"tuesdays\"") }
        #expect(throws: DecodingError.self) { try decode("[\"tues\"]") }
        #expect(throws: DecodingError.self) { try decode("[]") }
    }
}

@Suite("Household clock: always America/Chicago")
struct HouseholdClockTests {
    let clock = HouseholdClock.chicago

    @Test func schoolStartIsCentralTimeNotUTC() {
        // CDT is UTC-5 in October.
        let start = clock.instant(LocalDate(iso: "2026-10-20")!, LocalTime("08:15")!)
        #expect(start == Date(timeIntervalSince1970: 1_792_502_100)) // 2026-10-20T13:15:00Z
    }

    @Test func fallBackDayKeepsWallTimes() {
        // 2026-11-01: clocks fall back at 2:00 AM; 8:15 is CST (UTC-6).
        let saturday = clock.instant(LocalDate(iso: "2026-10-31")!, LocalTime("08:15")!)
        let sunday = clock.instant(LocalDate(iso: "2026-11-01")!, LocalTime("08:15")!)
        #expect(sunday.timeIntervalSince(saturday) == 25 * 3600)
        #expect(clock.localTime(of: sunday) == LocalTime("08:15"))
        let day = LocalDate(iso: "2026-11-01")!
        #expect(clock.endOfDay(day).timeIntervalSince(clock.startOfDay(day)) == 25 * 3600)
    }

    @Test func springForwardDayKeepsWallTimes() {
        // 2027-03-14: clocks spring forward; the day is 23 hours long.
        let day = LocalDate(iso: "2027-03-14")!
        let before = clock.instant(LocalDate(iso: "2027-03-13")!, LocalTime("08:15")!)
        let after = clock.instant(day, LocalTime("08:15")!)
        #expect(after.timeIntervalSince(before) == 23 * 3600)
        #expect(clock.endOfDay(day).timeIntervalSince(clock.startOfDay(day)) == 23 * 3600)
        #expect(clock.localTime(of: after) == LocalTime("08:15"))
    }

    @Test func lateEveningIsStillTheSameChicagoDay() {
        // 2026-10-21T03:00Z is 10:00 PM on Oct 20 in Chicago, not Oct 21.
        let instant = Date(timeIntervalSince1970: 1_792_551_600)
        #expect(clock.localDate(of: instant).iso == "2026-10-20")
        #expect(clock.localTime(of: instant) == LocalTime("22:00"))
    }

    /// What calendars hand over for an all-day event on a phone in `zone`:
    /// local midnight of the first day, and either 23:59:59 of the last day
    /// or the next midnight.
    private func allDay(_ first: String, _ last: String, in zone: String, exclusiveEnd: Bool) -> (Date, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        let a = LocalDate(iso: first)!, b = LocalDate(iso: last)!
        let start = calendar.date(from: DateComponents(year: a.year, month: a.month, day: a.day))!
        let end = exclusiveEnd
            ? calendar.date(from: DateComponents(year: b.adding(days: 1).year, month: b.adding(days: 1).month, day: b.adding(days: 1).day))!
            : calendar.date(from: DateComponents(year: b.year, month: b.month, day: b.day, hour: 23, minute: 59, second: 59))!
        return (start, end)
    }

    @Test(arguments: [
        ("America/Chicago", false), ("America/Chicago", true),
        ("America/Los_Angeles", false), ("America/Los_Angeles", true),
        ("America/New_York", false), ("Etc/UTC", false), ("Etc/UTC", true),
    ])
    func allDayEventsKeepTheirDaysFromAnyNearbyZone(_ zone: String, _ exclusiveEnd: Bool) {
        let (start, end) = allDay("2026-10-24", "2026-10-24", in: zone, exclusiveEnd: exclusiveEnd)
        let oneDay = clock.allDayDates(start: start, end: end)
        #expect(oneDay.first.iso == "2026-10-24" && oneDay.last.iso == "2026-10-24", "\(zone)")

        let (s, e) = allDay("2026-11-25", "2026-11-27", in: zone, exclusiveEnd: exclusiveEnd)
        let threeDays = clock.allDayDates(start: s, end: e)
        #expect(threeDays.first.iso == "2026-11-25" && threeDays.last.iso == "2026-11-27", "\(zone)")
    }

    @Test func allDayAcrossTheFallBackChange() {
        // Oct 31 – Nov 1, 2026: the second day is 25 hours long in Chicago.
        let (start, end) = allDay("2026-10-31", "2026-11-01", in: "America/Chicago", exclusiveEnd: false)
        let dates = clock.allDayDates(start: start, end: end)
        #expect(dates.first.iso == "2026-10-31" && dates.last.iso == "2026-11-01")
    }

    @Test func unknownZoneThrows() {
        #expect(throws: HouseholdClock.UnknownTimeZone.self) {
            try HouseholdClock(timeZoneIdentifier: "America/Chicagoo")
        }
    }

    @Test func plannerUsesTheRulesZone() throws {
        let plan = Fixture.plan("2026-10-20")
        let school = try #require(plan.items.first { $0.id == "block:school" })
        #expect(school.start == Date(timeIntervalSince1970: 1_792_502_100))
        #expect(plan.clock.timeZone.identifier == "America/Chicago")
    }
}
