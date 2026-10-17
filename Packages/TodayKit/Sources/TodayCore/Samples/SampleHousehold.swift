import Foundation

/// A fictional household shaped like the real one, with events that exercise
/// every rule. The seeded screenshot days and the golden tests use it, so
/// they never depend on the real names in `Rules/household.json`.
///
/// The three seeded days:
/// - Tue 2026-10-20: school + preschool; an untagged family event that lands
///   on Grandpa during the in-laws' care; a name-tagged all-day event; Kate's
///   calendar is not on the device, so her lane is "no data".
/// - Wed 2026-10-21: school only; a work call that overlaps the pickup loop,
///   a possessive alias ("Nana's") and a haircut naming one kid.
/// - Sat 2026-10-24: weekend; an event naming two kids, a trip naming both
///   grandparents, and an event on a calendar the rules don't list.
public enum SampleHousehold {
    public static let tuesday = LocalDate(year: 2026, month: 10, day: 20)!
    public static let wednesday = LocalDate(year: 2026, month: 10, day: 21)!
    public static let saturday = LocalDate(year: 2026, month: 10, day: 24)!
    public static let seededDays = [tuesday, wednesday, saturday]

    public static var rules: HouseholdRules {
        // The JSON is a literal in this file, so it can only fail if edited badly;
        // the tests load it on every run.
        try! RulesLoader.load(Data(rulesJSON.utf8)).rules
    }

    /// The calendars the seeded device can read on `date`. Tuesday is the
    /// "wife's calendar isn't shared to this phone" case.
    public static func calendarsOnDevice(on date: LocalDate) -> Set<String> {
        date == tuesday ? ["Family", "Sam", "US Holidays"] : ["Family", "Sam", "Kate", "US Holidays"]
    }

    public static func plan(for date: LocalDate) -> DayPlan {
        // The sample rules are valid by construction (the tests load them).
        let planner = try! DayPlanner(rules: rules)
        return planner.plan(for: date, events: events(on: date), calendarsOnDevice: calendarsOnDevice(on: date))
    }

    public static func events(on date: LocalDate) -> [SourceEvent] {
        let clock = HouseholdClock.chicago
        func at(_ hhmm: String) -> Date { clock.instant(date, LocalTime(hhmm)!) }
        func timed(_ id: String, _ calendar: String, _ title: String, _ start: String, _ end: String) -> SourceEvent {
            SourceEvent(id: "\(date.iso)-\(id)", calendarTitle: calendar, title: title, start: at(start), end: at(end))
        }
        func allDay(_ id: String, _ calendar: String, _ title: String) -> SourceEvent {
            SourceEvent(id: "\(date.iso)-\(id)", calendarTitle: calendar, title: title,
                        start: clock.startOfDay(date), end: clock.endOfDay(date), isAllDay: true)
        }

        switch date {
        case tuesday:
            return [
                allDay("picture", "Family", "Picture day - Emma"),
                timed("dentist", "Family", "Dentist", "10:00", "11:00"),
                timed("swim", "Family", "Swim lesson (Emma)", "17:30", "18:00"),
                timed("standup", "Sam", "Team standup", "09:00", "09:15"),
            ]
        case wednesday:
            return [
                timed("bookclub", "Family", "Nana's book club", "13:00", "14:30"),
                timed("haircut", "Family", "Haircut – Nora", "16:30", "17:00"),
                timed("call", "Sam", "Call with vendor", "15:15", "15:45"),
                timed("client", "Kate", "Client review", "10:00", "11:30"),
                timed("yoga", "Kate", "Yoga", "18:00", "19:00"),
            ]
        case saturday:
            return [
                allDay("trip", "Family", "Trip to Dallas: Grandma & Grandpa"),
                timed("party", "Family", "Birthday party — Emma & Nora", "10:00", "12:00"),
                timed("lunch", "Family", "Lunch at the club", "12:30", "13:30"),
                timed("market", "Kate", "Farmers market", "08:00", "09:30"),
                timed("holiday", "US Holidays", "Some observance", "00:00", "23:59"),
            ]
        default:
            return []
        }
    }

    public static let rulesJSON = """
    {
      "schemaVersion": 1,
      "timeZone": "America/Chicago",
      "dayWindow": { "start": "06:00", "end": "21:00" },
      "people": [
        { "id": "dad",     "name": "Sam",     "group": "parents",      "aliases": ["Dad"] },
        { "id": "mom",     "name": "Kate",    "group": "parents",      "aliases": ["Mom"] },
        { "id": "kinder",  "name": "Emma",    "group": "kids",         "birthDate": "2021-05-14" },
        { "id": "pre",     "name": "Nora",    "group": "kids",         "birthDate": "2023-02-02" },
        { "id": "twinA",   "name": "Leo",     "group": "kids",         "lane": "Twins", "aliases": ["Twins"] },
        { "id": "twinB",   "name": "Max",     "group": "kids",         "lane": "Twins", "aliases": ["Twins"] },
        { "id": "grandpa", "name": "Grandpa", "group": "grandparents", "aliases": ["Papa"] },
        { "id": "grandma", "name": "Grandma", "group": "grandparents", "aliases": ["Nana"] }
      ],
      "calendars": [
        { "title": "Family", "role": "shared",   "defaultOwner": "grandpa" },
        { "title": "Sam",    "role": "personal", "owner": "dad" },
        { "title": "Kate",   "role": "personal", "owner": "mom" }
      ],
      "blocks": [
        { "id": "work", "title": "Work", "kind": "work", "who": ["dad"],
          "days": "daily", "start": "08:30", "end": "17:00" },
        { "id": "school", "title": "School", "kind": "school", "who": ["kinder"],
          "days": "weekdays", "start": "08:15", "end": "15:30", "schoolCalendar": "district" },
        { "id": "preschool", "title": "Preschool", "kind": "school", "who": ["pre"],
          "days": ["tue", "thu"], "start": "09:00", "end": "11:30", "schoolCalendar": "district" }
      ],
      "schoolCalendars": {
        "district": {
          "firstDay": "2026-08-19",
          "lastDay": "2027-05-27",
          "noSchool": [
            { "date": "2026-10-23", "label": "Teacher in-service" },
            { "from": "2026-11-25", "to": "2026-11-27", "label": "Thanksgiving" },
            { "from": "2026-12-21", "to": "2027-01-01", "label": "Winter break" }
          ],
          "earlyRelease": [ { "date": "2026-12-18", "end": "12:30" } ]
        }
      },
      "care": [
        { "id": "inlaws", "title": "With Grandma & Grandpa",
          "caregivers": ["grandma", "grandpa"], "kids": ["pre", "twinA", "twinB"],
          "days": "weekdays", "from": "07:45", "until": "pickupLoop" }
      ],
      "pickupLoop": {
        "driver": "dad", "days": "weekdays",
        "startsAt": "school.end", "fallbackStart": "17:00",
        "minutesBetweenStops": 15, "minutesToHome": 15,
        "stops": [
          { "place": "School", "collect": ["kinder"], "onlyWhen": "school" },
          { "place": "Grandma & Grandpa's", "collect": ["pre", "twinA", "twinB"] }
        ]
      },
      "needs": [
        { "who": ["pre"], "onDaysOf": "preschool", "items": ["Backpack", "Water bottle"] },
        { "who": ["kinder"], "days": ["wed"], "onDaysOf": "school", "items": ["Library book"] },
        { "who": ["twinA", "twinB"], "days": "weekdays", "items": ["Diaper bag"] }
      ],
      "checkIns": [
        { "kind": "morning",   "at": "06:30" },
        { "kind": "midday",    "at": "12:00" },
        { "kind": "afternoon", "at": "15:15", "timeSensitive": true }
      ],
      "importance": { "pickupLoop": "high", "appointment": "normal" }
    }
    """
}
