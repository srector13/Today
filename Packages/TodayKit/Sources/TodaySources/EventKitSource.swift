#if canImport(EventKit)
import EventKit
import Foundation
import TodayCore

/// Reads calendars, reminders and the Birthdays calendar on the device, and
/// hands them to the planner as plain `TodayCore` values. Nothing leaves the
/// phone.
///
/// `EKEventStore` isn't safe to share between tasks, so it lives inside this
/// actor and only `Sendable` values come out.
public actor EventKitSource {
    public enum Access: Sendable, Equatable {
        case notDetermined
        case granted
        /// Denied or restricted: Settings is the only way back.
        case denied
        /// Add-only access (iOS 17+): we can't read, so it counts as no data.
        case writeOnly
    }

    private let store = EKEventStore()

    public init() {}

    /// Callers don't need to import EventKit to ask.
    public static var calendarAccess: Access { access(for: .event) }
    public static var remindersAccess: Access { access(for: .reminder) }

    public static func access(for type: EKEntityType) -> Access {
        switch EKEventStore.authorizationStatus(for: type) {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        case .writeOnly: .writeOnly
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    /// Asks for full access to calendars, then reminders. Returns what was granted.
    public func requestAccess() async -> (calendars: Access, reminders: Access) {
        // The completion-handler forms keep the store on this actor; only the
        // Bool crosses back.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.requestFullAccessToEvents { _, _ in continuation.resume() }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.requestFullAccessToReminders { _, _ in continuation.resume() }
        }
        return (Self.access(for: .event), Self.access(for: .reminder))
    }

    /// The names of the event calendars this device can read, Birthdays
    /// excluded (it feeds the birthdays card, not lanes). Empty without access.
    public func calendarsOnDevice() -> Set<String> {
        guard Self.access(for: .event) == .granted else { return [] }
        return Set(store.calendars(for: .event).filter { $0.type != .birthday }.map(\.title))
    }

    /// Everything the planner needs for `date`.
    public func input(for date: LocalDate, rules: HouseholdRules, clock: HouseholdClock) async -> DayInput {
        DayInput(
            events: events(on: date, clock: clock),
            calendarsOnDevice: calendarsOnDevice(),
            reminders: await reminders(in: rules.reminderLists.map(\.title)),
            birthdays: birthdays(from: date, days: rules.birthdays.lookaheadDays, clock: clock)
        )
    }

    public func events(on date: LocalDate, clock: HouseholdClock) -> [SourceEvent] {
        guard Self.access(for: .event) == .granted else { return [] }
        let calendars = store.calendars(for: .event).filter { $0.type != .birthday }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(
            withStart: clock.startOfDay(date), end: clock.endOfDay(date), calendars: calendars)
        return store.events(matching: predicate).map { EventKitMapping.sourceEvent($0, clock: clock) }
    }

    /// Birthdays from the device's Birthdays calendar between `date` and
    /// `days` later.
    public func birthdays(from date: LocalDate, days: Int, clock: HouseholdClock) -> [SourceBirthday] {
        guard Self.access(for: .event) == .granted else { return [] }
        let calendars = store.calendars(for: .event).filter { $0.type == .birthday }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(
            withStart: clock.startOfDay(date), end: clock.endOfDay(date.adding(days: days)), calendars: calendars)
        return store.events(matching: predicate).map { event in
            let day = EventKitMapping.allDayDates(of: event, clock: clock).first
            return SourceBirthday(name: EventKitMapping.birthdayName(fromTitle: event.title ?? ""),
                                  month: day.month, day: day.day)
        }
    }

    /// Open reminders in the named lists.
    public func reminders(in listTitles: [String]) async -> [SourceReminder] {
        guard Self.access(for: .reminder) == .granted, !listTitles.isEmpty else { return [] }
        let wanted = Set(listTitles.map { $0.lowercased() })
        let lists = store.calendars(for: .reminder).filter { wanted.contains($0.title.lowercased()) }
        guard !lists.isEmpty else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        return await withCheckedContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { reminders in
                // Map inside the callback: EKReminder can't cross tasks.
                let mapped = (reminders ?? []).map(EventKitMapping.sourceReminder)
                continuation.resume(returning: mapped)
            }
        }
    }
}

/// EventKit → TodayCore conversions, kept separate so they're testable
/// without calendar access.
public enum EventKitMapping {
    public static func sourceEvent(_ event: EKEvent, clock: HouseholdClock) -> SourceEvent {
        let id = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString
        let calendar = event.calendar?.title ?? ""
        if event.isAllDay {
            let dates = allDayDates(of: event, clock: clock)
            return SourceEvent(id: id, calendarTitle: calendar, title: event.title ?? "",
                               start: clock.startOfDay(dates.first), end: clock.endOfDay(dates.last),
                               isAllDay: true, location: event.location, notes: event.notes)
        }
        return SourceEvent(id: id, calendarTitle: calendar, title: event.title ?? "",
                           start: event.startDate, end: event.endDate,
                           isAllDay: false, location: event.location, notes: event.notes)
    }

    /// The first and last day of an all-day event, in household dates.
    ///
    /// All-day events float: EventKit pins them to midnight in the device's
    /// zone, which on a phone travelling outside Chicago lands on the wrong
    /// Chicago day at midnight. Reading each end at midday is right for any
    /// zone within ±12 hours.
    public static func allDayDates(of event: EKEvent, clock: HouseholdClock) -> (first: LocalDate, last: LocalDate) {
        let halfDay: TimeInterval = 12 * 3600
        let first = clock.localDate(of: event.startDate.addingTimeInterval(halfDay))
        let last = clock.localDate(of: event.endDate.addingTimeInterval(-halfDay))
        return (first, max(first, last))
    }

    /// "Aunt Jo’s Birthday" → "Aunt Jo".
    public static func birthdayName(fromTitle title: String) -> String {
        for suffix in ["’s Birthday", "'s Birthday", "’ Birthday", "' Birthday", " Birthday"]
        where title.hasSuffix(suffix) {
            return String(title.dropLast(suffix.count))
        }
        return title
    }

    public static func sourceReminder(_ reminder: EKReminder) -> SourceReminder {
        let due = reminder.dueDateComponents.flatMap { components -> LocalDate? in
            guard let year = components.year, let month = components.month, let day = components.day else { return nil }
            return LocalDate(year: year, month: month, day: day)
        }
        return SourceReminder(id: reminder.calendarItemExternalIdentifier ?? UUID().uuidString,
                              listTitle: reminder.calendar?.title ?? "",
                              title: reminder.title ?? "", due: due)
    }
}
#endif
