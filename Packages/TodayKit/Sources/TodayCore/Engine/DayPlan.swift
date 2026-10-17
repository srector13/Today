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

    public init(id: String, calendarTitle: String, title: String, start: Date, end: Date, isAllDay: Bool = false) {
        self.id = id
        self.calendarTitle = calendarTitle
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

/// Why an event landed on the lanes it did.
public enum Attribution: String, Sendable, Equatable {
    /// A personal calendar's owner.
    case calendarOwner
    /// A shared calendar's default owner: the title named nobody.
    case defaultOwner
    /// People named in the title (on a shared calendar, instead of the default).
    case namedInTitle
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

    public func overlaps(_ start: Date, _ end: Date) -> Bool {
        self.start < end && self.end > start
    }

    func with(people: [PersonID]) -> TimelineItem {
        TimelineItem(id: id, title: title, kind: kind, start: start, end: end, isAllDay: isAllDay,
                     people: people, importance: importance, origin: origin, detail: detail)
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
