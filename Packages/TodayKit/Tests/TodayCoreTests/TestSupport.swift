import Foundation
@testable import TodayCore

/// The sample household's planner, and short ways to build days and events.
enum Fixture {
    static let rules = SampleHousehold.rules
    static let planner = try! DayPlanner(rules: rules)
    static let clock = HouseholdClock.chicago
    static let allCalendars: Set<String> = ["Family", "Sam", "Kate", "Us"]

    static func date(_ iso: String) -> LocalDate {
        LocalDate(iso: iso)!
    }

    static func time(_ hhmm: String) -> LocalTime {
        LocalTime(hhmm)!
    }

    static func at(_ iso: String, _ hhmm: String) -> Date {
        clock.instant(date(iso), time(hhmm))
    }

    static func event(
        _ title: String,
        on calendar: String = "Family",
        _ iso: String,
        _ start: String,
        _ end: String
    ) -> SourceEvent {
        SourceEvent(id: "\(iso)-\(title)", calendarTitle: calendar, title: title,
                    start: at(iso, start), end: at(iso, end))
    }

    static func plan(
        _ iso: String,
        events: [SourceEvent] = [],
        calendars: Set<String> = allCalendars,
        planner: DayPlanner = planner
    ) -> DayPlan {
        planner.plan(for: date(iso), events: events, calendarsOnDevice: calendars)
    }

    /// The sample rules JSON with `edit` applied to its dictionary.
    static func rulesJSON(_ edit: (inout [String: Any]) -> Void) -> Data {
        var object = try! JSONSerialization.jsonObject(with: Data(SampleHousehold.rulesJSON.utf8)) as! [String: Any]
        edit(&object)
        return try! JSONSerialization.data(withJSONObject: object)
    }

    /// A planner over the sample rules with `edit` applied.
    static func planner(_ edit: (inout [String: Any]) -> Void) throws -> DayPlanner {
        try DayPlanner(rules: RulesLoader.load(rulesJSON(edit)).rules)
    }
}

extension DayPlan {
    func lane(_ label: String) -> Lane? {
        lanes.first { $0.label == label }
    }

    /// "07:45–09:00 With the grandparents" lines for one person, timed items only.
    func schedule(for person: PersonID) -> [String] {
        items(for: person).filter { !$0.isAllDay }.map { item in
            "\(clock.localTime(of: item.start).hhmm)–\(clock.localTime(of: item.end).hhmm) \(item.title)"
        }
    }

    func alerts(_ kind: PlanAlert.Kind) -> [PlanAlert] {
        alerts.filter { $0.kind == kind }
    }
}

/// The repository root, from this file's place in it.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // TodayCoreTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // TodayKit
    .deletingLastPathComponent() // Packages
    .deletingLastPathComponent()
