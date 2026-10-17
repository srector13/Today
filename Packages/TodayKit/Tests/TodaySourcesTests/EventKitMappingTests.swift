#if canImport(EventKit)
import CoreGraphics
import EventKit
import Foundation
import Testing
import TodayCore
@testable import TodaySources

/// EventKit conversions, built from unsaved EKEvents: no calendar access
/// needed, so these run on the macOS CI host.
@Suite("EventKit mapping")
struct EventKitMappingTests {
    let store = EKEventStore()
    let clock = HouseholdClock.chicago

    func event(_ title: String, calendar: String, start: Date, end: Date, allDay: Bool = false) -> EKEvent {
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = calendar
        let event = EKEvent(eventStore: store)
        event.calendar = cal
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = allDay
        event.location = "Library annex"
        return event
    }

    @Test func timedEventKeepsItsInstants() {
        let start = clock.instant(LocalDate(iso: "2026-10-20")!, LocalTime("19:00")!)
        let end = clock.instant(LocalDate(iso: "2026-10-20")!, LocalTime("20:30")!)
        let mapped = EventKitMapping.sourceEvent(event("SERC planning", calendar: "Family", start: start, end: end), clock: clock)
        #expect(mapped.title == "SERC planning")
        #expect(mapped.calendarTitle == "Family")
        #expect(mapped.start == start && mapped.end == end)
        #expect(mapped.location == "Library annex")
        #expect(!mapped.isAllDay)
    }

    // EventKit re-pins an all-day event's dates to midnight in the test
    // machine's own zone (UTC on CI). Noon UTC falls on the same calendar day
    // in every zone within ±12 hours, so these inputs survive that on any Mac.
    // The zone arithmetic itself is tested in TodayCore (HouseholdClockTests).

    @Test func allDayEventMapsToWholeHouseholdDays() {
        let noonOct24 = Date(timeIntervalSince1970: 1_792_843_200) // 2026-10-24T12:00Z
        let mapped = EventKitMapping.sourceEvent(event("Trip", calendar: "Family", start: noonOct24, end: noonOct24, allDay: true), clock: clock)
        #expect(mapped.isAllDay)
        #expect(mapped.start == clock.startOfDay(LocalDate(iso: "2026-10-24")!))
        #expect(mapped.end == clock.endOfDay(LocalDate(iso: "2026-10-24")!))
    }

    @Test func multiDayAllDayEvent() {
        let noonNov25 = Date(timeIntervalSince1970: 1_795_608_000) // 2026-11-25T12:00Z
        let noonNov27 = Date(timeIntervalSince1970: 1_795_780_800) // 2026-11-27T12:00Z
        let dates = EventKitMapping.allDayDates(of: event("Break", calendar: "Family", start: noonNov25, end: noonNov27, allDay: true), clock: clock)
        #expect(dates.first.iso == "2026-11-25")
        #expect(dates.last.iso == "2026-11-27")
    }

    @Test(arguments: [
        ("Aunt Jo’s Birthday", "Aunt Jo"),
        ("Aunt Jo's Birthday", "Aunt Jo"),
        ("Chris’ Birthday", "Chris"),
        ("Jordan Birthday", "Jordan"),
        ("Party", "Party"),
    ])
    func birthdayNames(_ title: String, _ name: String) {
        #expect(EventKitMapping.birthdayName(fromTitle: title) == name)
    }

    @Test func calendarColorsAsHex() {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let orange = CGColor(colorSpace: srgb, components: [1, 159.0 / 255, 69.0 / 255, 1])!
        #expect(EventKitMapping.hex(orange) == "#FF9F45")
        #expect(EventKitMapping.hex(nil) == nil)
    }

    @Test func reminderDueDate() {
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = "Kids"
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = "Picture day form - Emma"
        reminder.dueDateComponents = DateComponents(year: 2026, month: 10, day: 20)
        let mapped = EventKitMapping.sourceReminder(reminder)
        #expect(mapped.listTitle == "Kids")
        #expect(mapped.due == LocalDate(iso: "2026-10-20"))
        reminder.dueDateComponents = nil
        #expect(EventKitMapping.sourceReminder(reminder).due == nil)
    }
}
#endif
