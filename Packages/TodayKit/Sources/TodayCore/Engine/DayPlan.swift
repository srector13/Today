import Foundation

/// A calendar event as a source hands it to the planner. M2's EventKit
/// source fills these from the device; tests and seeded days build them
/// directly.
public struct SourceEvent: Sendable, Equatable {
    public var id: String
    /// The calendar's name, matched against `CalendarRule.title`.
    public var calendarTitle: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?

    public init(
        id: String, calendarTitle: String, title: String, start: Date, end: Date,
        isAllDay: Bool = false, location: String? = nil, notes: String? = nil
    ) {
        self.id = id
        self.calendarTitle = calendarTitle
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
    }
}

/// An open reminder from one of the rules' Reminders lists.
public struct SourceReminder: Sendable, Equatable {
    public var id: String
    public var listTitle: String
    public var title: String
    /// `nil`: no due date, so it shows every day until done.
    public var due: LocalDate?

    public init(id: String, listTitle: String, title: String, due: LocalDate?) {
        self.id = id
        self.listTitle = listTitle
        self.title = title
        self.due = due
    }
}

/// A birthday from the iOS Birthdays calendar (contacts' birthdays).
public struct SourceBirthday: Sendable, Equatable {
    public var name: String
    public var month: Int
    public var day: Int
    public var year: Int?

    public init(name: String, month: Int, day: Int, year: Int? = nil) {
        self.name = name
        self.month = month
        self.day = day
        self.year = year
    }
}

/// Everything the device sources hand the planner for one day.
public struct DayInput: Sendable {
    public var events: [SourceEvent]
    /// The names of the calendars the device can read. A lane whose calendar
    /// is missing shows "no data", never a free day.
    public var calendarsOnDevice: Set<String>
    public var reminders: [SourceReminder]
    public var birthdays: [SourceBirthday]

    public init(
        events: [SourceEvent] = [], calendarsOnDevice: Set<String>,
        reminders: [SourceReminder] = [], birthdays: [SourceBirthday] = []
    ) {
        self.events = events
        self.calendarsOnDevice = calendarsOnDevice
        self.reminders = reminders
        self.birthdays = birthdays
    }
}

/// Why an event landed on the lanes it did.
public enum Attribution: Sendable, Equatable {
    /// A personal calendar's owner.
    case calendarOwner
    /// A shared calendar's default owner: the title named nobody.
    case defaultOwner
    /// People named in the title (on a shared calendar, instead of the default).
    case namedInTitle
    /// One of the household's assignment rules, by name.
    case rule(String)

    public var label: String {
        switch self {
        case .calendarOwner: "calendarOwner"
        case .defaultOwner: "defaultOwner"
        case .namedInTitle: "namedInTitle"
        case let .rule(name): "rule \"\(name)\""
        }
    }
}

/// One stretch of someone's day, from a rule or a calendar.
public struct TimelineItem: Sendable, Equatable, Identifiable {
    public enum Origin: Sendable, Equatable {
        /// The id of the block, care rule or loop that made it.
        case rule(String)
        case calendar(title: String, attribution: Attribution)
    }

    public let id: String
    public let title: String
    public let kind: ItemKind
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let people: [PersonID]
    public let importance: Importance
    public let origin: Origin
    /// A second line, e.g. the loop's stops.
    public let detail: String?
    /// Every assignment rule that matched the event, for "why is this here?".
    public var rules: [String] = []

    public func overlaps(_ start: Date, _ end: Date) -> Bool {
        self.start < end && self.end > start
    }

    func with(people: [PersonID]) -> TimelineItem {
        TimelineItem(id: id, title: title, kind: kind, start: start, end: end, isAllDay: isAllDay,
                     people: people, importance: importance, origin: origin, detail: detail, rules: rules)
    }
}

/// How a school-kind block stands on the day.
public struct SchoolStatus: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case inSession(start: LocalTime, end: LocalTime, earlyRelease: Bool)
        /// A day off or a break inside the term.
        case noSchool(label: String?)
        /// Before the first day or after the last (summer).
        case outOfTerm
    }

    public let blockID: String
    public let title: String
    public let people: [PersonID]
    public let state: State

    public var isInSession: Bool {
        if case .inSession = state { return true }
        return false
    }
}

public struct PickupLoopPlan: Sendable, Equatable {
    public struct Stop: Sendable, Equatable {
        public let place: String
        public let time: LocalTime
        public let kids: [PersonID]
    }

    public let title: String
    public let driver: PersonID
    public let start: LocalTime
    /// Home again, by the loop's estimate.
    public let end: LocalTime
    public let stops: [Stop]
    /// The usual start's block didn't run (no school), so the fallback applied.
    public let usedFallbackStart: Bool
}

public struct PlanAlert: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case noSchool
        case earlyRelease
        /// A kid with no school and no care rule covering them.
        case uncoveredKid
        /// A caregiver has an appointment while they have the kids.
        case careConflict
        /// The driver has an appointment during the pickup loop.
        case loopConflict
        /// The loop should run but has no start time.
        case noLoopTime
        /// A shared calendar the rules list isn't on the device.
        case missingCalendar
    }

    public let kind: Kind
    public let message: String
    public let people: [PersonID]
    /// When a conflict stops mattering (the overlap is over); `nil` for
    /// alerts about the whole day.
    public var end: Date? = nil

    public func isOver(at now: Date) -> Bool {
        end.map { $0 <= now } ?? false
    }
}

/// What a kid needs today. Lane-mates who need the same things share one
/// entry ("Twins: Diaper bag").
public struct KidNeed: Sendable, Equatable {
    public let people: [PersonID]
    public let items: [String]
}

/// Whether a lane's calendar data is on this device.
public enum LaneData: Sendable, Equatable {
    case known
    /// Never draw or speak this lane's open time as free: we can't see it.
    case noData(reason: String)

    public var isKnown: Bool { self == .known }
}

/// One row of the timeline: a person, or people sharing a lane label.
public struct Lane: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let group: PersonGroup
    public let people: [PersonID]
    /// Items that touch any of `people`; identical items for lane-mates are merged.
    public let items: [TimelineItem]
    public let data: LaneData
    /// The first member's color; lane-mates share it.
    public let color: LaneColor
    /// A one-person lane's photo file name, if they have one.
    public let photo: String?
    public let initials: String
}

/// A birthday coming up within the rules' lookahead.
public struct UpcomingBirthday: Sendable, Equatable {
    public let name: String
    public let date: LocalDate
    public let daysAway: Int
    /// The age they turn, when the birth year is known.
    public let turning: Int?
    /// Set when the birthday is a household member's.
    public let person: PersonID?
}

public struct LaneGroup: Sendable, Equatable, Identifiable {
    public let group: PersonGroup
    public let lanes: [Lane]

    public var id: String { group.rawValue }
}

/// Everything the household rules and the day's calendars say about one day.
public struct DayPlan: Sendable {
    public let date: LocalDate
    public let clock: HouseholdClock
    public let dayWindow: DayWindow
    public let schools: [SchoolStatus]
    public let pickupLoop: PickupLoopPlan?
    /// All-day items first, then by start.
    public let items: [TimelineItem]
    public let laneGroups: [LaneGroup]
    public let alerts: [PlanAlert]
    public let needs: [KidNeed]
    /// Birthdays only: never trips or other all-day events.
    public let birthdays: [UpcomingBirthday]
    /// Events an assignment rule hid, for a "show hidden" view.
    public let hiddenItems: [TimelineItem]
    /// Calendars the rules list that aren't on this device.
    public let missingCalendars: [String]
    /// Calendars with events today that the rules don't list, so no one owns them.
    public let unlistedCalendars: [String]

    public var isWeekend: Bool { date.weekday.isWeekend }

    public func items(for person: PersonID) -> [TimelineItem] {
        items.filter { $0.people.contains(person) }
    }

    public func school(_ blockID: String) -> SchoolStatus? {
        schools.first { $0.blockID == blockID }
    }

    public var lanes: [Lane] { laneGroups.flatMap(\.lanes) }
}
