import Foundation

/// A fictional household shaped like the real one, with events that exercise
/// every rule. The seeded screenshot days and the golden tests use it, so
/// they never depend on the real household's file. (Jess, the father-in-law,
/// is the real name; the rest are placeholders.)
///
/// The three seeded days:
/// - Tue 2026-10-20: school + preschool; an untagged family event that lands
///   on Jess during the in-laws' care; a name-tagged all-day event; Kate's
///   calendar is not on the device, so her lane is "no data"; the SERC rule
///   claims an evening event; a "Busy" block is hidden by a rule; a Kids
///   reminder becomes Emma's need.
/// - Wed 2026-10-21: school only; a work call that overlaps the pickup loop;
///   a possessive alias ("Nana's"); the SERC rule moves an event off Sam's
///   own calendar onto Jess's lane; an event on "Us", the calendar Sam and
///   Kate share, which asks who each unnamed event is for.
/// - Sat 2026-10-24: weekend; an event naming two kids, a trip naming both
///   grandparents, an event on a calendar the rules don't list, and Aunt
///   Jo's birthday from the device's Birthdays calendar.
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
        date == tuesday ? ["Family", "Sam", "Us", "US Holidays"] : ["Family", "Sam", "Kate", "Us", "US Holidays"]
    }

    public static func input(on date: LocalDate) -> DayInput {
        DayInput(
            events: events(on: date),
            calendarsOnDevice: calendarsOnDevice(on: date),
            reminders: reminders,
            birthdays: contactBirthdays
        )
    }

    public static func plan(for date: LocalDate) -> DayPlan {
        // The sample rules are valid by construction (the tests load them).
        let planner = try! DayPlanner(rules: rules)
        return planner.plan(for: date, input: input(on: date))
    }

    /// The seeded screenshots' clock: 2:40 PM, as in the approved mockup.
    public static func now(on date: LocalDate) -> Date {
        HouseholdClock.chicago.instant(date, LocalTime(hour: 14, minute: 40)!)
    }

    /// Events over a run of days, for the rule editor's preview.
    public static func events(from start: LocalDate, days: Int) -> [SourceEvent] {
        (0..<days).flatMap { events(on: start.adding(days: $0)) }
    }

    /// A fall day in Chicago; Tuesday's rain arrives at pickup time.
    public static func weather(on date: LocalDate) -> WeatherSnapshot {
        let clock = HouseholdClock.chicago
        let rainy = date == tuesday
        let temps = [48, 49, 51, 53, 55, 57, 59, 61, 63, 64, 64, 62, 60, 58, 56, 54]
        let rain = rainy
            ? [0, 0, 0, 0, 0, 0.1, 0.1, 0.1, 0.1, 0.2, 0.6, 0.45, 0.1, 0, 0, 0]
            : [Double](repeating: 0, count: temps.count)
        let hours = temps.indices.map { index in
            WeatherSnapshot.Hour(
                time: clock.instant(date, LocalTime(hour: 6 + index, minute: 0)!),
                temperature: temps[index],
                precipitationChance: rain[index],
                symbol: rain[index] >= WeatherSnapshot.likely ? "cloud.rain.fill" : (index > 12 ? "cloud.moon.fill" : "cloud.sun.fill")
            )
        }
        return WeatherSnapshot(temperature: 64, condition: rainy ? "Partly cloudy" : "Sunny",
                               symbol: rainy ? "cloud.sun.fill" : "sun.max.fill", high: 68, low: 51, hours: hours)
    }

    /// Open reminders in the Kids list.
    public static let reminders = [
        SourceReminder(id: "r1", listTitle: "Kids", title: "Picture day form - Emma", due: tuesday),
        SourceReminder(id: "r2", listTitle: "Kids", title: "Return library book (Emma)", due: wednesday),
        SourceReminder(id: "r3", listTitle: "Kids", title: "Twins: sunscreen", due: nil),
        SourceReminder(id: "r4", listTitle: "Kids", title: "Buy diapers", due: nil),
        SourceReminder(id: "r5", listTitle: "Groceries", title: "Milk for Emma", due: nil),
    ]

    /// The device's Birthdays calendar (contacts).
    public static let contactBirthdays = [
        SourceBirthday(name: "Aunt Jo", month: 10, day: 24, year: 1986),
        SourceBirthday(name: "Uncle Ray", month: 11, day: 30),
    ]

    public static func events(on date: LocalDate) -> [SourceEvent] {
        let clock = HouseholdClock.chicago
        func at(_ hhmm: String) -> Date { clock.instant(date, LocalTime(hhmm)!) }
        func timed(
            _ id: String, _ calendar: String, _ title: String, _ start: String, _ end: String,
            location: String? = nil, repeating: Bool = false
        ) -> SourceEvent {
            SourceEvent(id: "\(date.iso)-\(id)", calendarTitle: calendar, title: title, start: at(start), end: at(end),
                        location: location, isRecurring: repeating)
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
                timed("swim", "Family", "Swim lesson (Emma)", "17:30", "18:00", repeating: true),
                timed("standup", "Sam", "Team standup", "09:00", "09:15"),
                timed("busy", "Sam", "Busy", "13:00", "14:00"),
                timed("serc", "Family", "SERC planning", "19:00", "20:30", location: "Library annex"),
            ]
        case wednesday:
            return [
                timed("bookclub", "Family", "Nana's book club", "13:00", "14:30"),
                timed("haircut", "Family", "Haircut – Nora", "16:30", "17:00"),
                timed("call", "Sam", "Call with vendor", "15:15", "15:45"),
                timed("serc", "Sam", "SERC board call", "18:30", "19:30"),
                timed("client", "Kate", "Client review", "10:00", "11:30"),
                timed("yoga", "Kate", "Yoga", "18:00", "19:00"),
                timed("conference", "Us", "Parent-teacher conference", "17:15", "17:45"),
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
      "schemaVersion": 3,
      "timeZone": "America/Chicago",
      "dayWindow": { "start": "06:00", "end": "21:00" },
      "people": [
        { "id": "dad",     "name": "Sam",     "group": "parents",      "aliases": ["Dad"], "color": "#5E9EFF" },
        { "id": "mom",     "name": "Kate",    "group": "parents",      "aliases": ["Mom"], "color": "#C58CFF" },
        { "id": "kinder",  "name": "Emma",    "group": "kids",         "birthDate": "2021-05-14", "color": "#FF9F45" },
        { "id": "pre",     "name": "Nora",    "group": "kids",         "birthDate": "2023-02-02", "color": "#FF7AB6" },
        { "id": "twinA",   "name": "Leo",     "group": "kids",         "lane": "Twins", "aliases": ["Twins"],
          "birthDate": "2024-12-09", "color": "#3FD4C2" },
        { "id": "twinB",   "name": "Max",     "group": "kids",         "lane": "Twins", "aliases": ["Twins"],
          "birthDate": "2024-12-09", "color": "#3FD4C2" },
        { "id": "grandpa", "name": "Jess",    "group": "grandparents", "aliases": ["Grandpa", "Papa"], "color": "#6AD07A" },
        { "id": "grandma", "name": "Grandma", "group": "grandparents", "aliases": ["Nana"], "color": "#FFD34E" }
      ],
      "calendars": [
        { "title": "Family", "members": "everyone",      "ifNobodyNamed": ["grandpa"] },
        { "title": "Sam",    "members": ["dad"] },
        { "title": "Kate",   "members": ["mom"] },
        { "title": "Us",     "members": ["dad", "mom"], "ifNobodyNamed": "ask" }
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
        { "id": "inlaws", "title": "With the grandparents",
          "caregivers": ["grandma", "grandpa"], "kids": ["pre", "twinA", "twinB"],
          "days": "weekdays", "from": "07:45", "until": "pickupLoop" }
      ],
      "pickupLoop": {
        "driver": "dad", "days": "weekdays",
        "startsAt": "school.end", "fallbackStart": "17:00",
        "minutesBetweenStops": 15, "minutesToHome": 15,
        "stops": [
          { "place": "School", "collect": ["kinder"], "onlyWhen": "school" },
          { "place": "Grandparents'", "collect": ["pre", "twinA", "twinB"] }
        ]
      },
      "needs": [
        { "who": ["pre"], "onDaysOf": "preschool", "items": ["Backpack", "Water bottle"] },
        { "who": ["kinder"], "days": ["wed"], "onDaysOf": "school", "items": ["Library book"] },
        { "who": ["twinA", "twinB"], "days": "weekdays", "items": ["Diaper bag"] }
      ],
      "reminderLists": [ { "title": "Kids" } ],
      "assignmentRules": [
        { "id": "serc", "name": "SERC → Jess",
          "conditions": [ { "field": "title", "op": "contains", "value": "SERC" } ],
          "actions": [ { "assignTo": ["grandpa"] } ] },
        { "id": "busy", "name": "Hide busy blocks", "match": "all",
          "conditions": [ { "field": "title", "op": "is", "value": "Busy" },
                          { "field": "calendar", "op": "is", "value": "Sam" } ],
          "actions": [ { "hide": true } ] },
        { "id": "swim", "name": "Sam takes swim",
          "conditions": [ { "field": "title", "op": "contains", "value": "swim" } ],
          "actions": [ { "alsoInclude": ["dad"] } ] },
        { "id": "golf", "name": "Golf is background", "enabled": false,
          "conditions": [ { "field": "title", "op": "contains", "value": "tee time" } ],
          "actions": [ { "importance": "background" } ] }
      ],
      "birthdays": { "lookaheadDays": 60 },
      "checkIns": [
        { "kind": "morning",   "at": "06:30" },
        { "kind": "midday",    "at": "12:00" },
        { "kind": "afternoon", "at": "15:15", "timeSensitive": true }
      ],
      "importance": { "pickupLoop": "high", "appointment": "normal" }
    }
    """
}
