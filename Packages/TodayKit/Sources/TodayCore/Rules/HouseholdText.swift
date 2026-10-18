import Foundation

/// One-line descriptions for the Household screens' rows.
public struct HouseholdText: Sendable {
    public let planner: DayPlanner
    var rules: HouseholdRules { planner.rules }

    public init(planner: DayPlanner) {
        self.planner = planner
    }

    /// "Sam · every day · 8:30 AM–5:00 PM".
    public func block(_ block: BlockRule) -> String {
        var parts = [planner.names(block.who), DisplayFormat.days(block.days),
                     DisplayFormat.twelveHourSpan(block.start, block.end)]
        if let calendar = block.schoolCalendar { parts.append("\(calendar) calendar") }
        return parts.joined(separator: " · ")
    }

    /// "5 school days off · 1 early release · Aug 19 – May 27".
    public func schoolCalendar(_ calendar: SchoolCalendar) -> String {
        var parts: [String] = []
        let daysOff = calendar.noSchool.reduce(0) { total, entry in
            total + (entry.from.dayNumber...max(entry.from.dayNumber, entry.to.dayNumber))
                .filter { !LocalDate(dayNumber: $0).weekday.isWeekend }.count
        }
        parts.append(daysOff == 0 ? "No days off entered yet" : "\(daysOff) school day\(daysOff == 1 ? "" : "s") off")
        if !calendar.earlyRelease.isEmpty {
            parts.append("\(calendar.earlyRelease.count) early release\(calendar.earlyRelease.count == 1 ? "" : "s")")
        }
        if let first = calendar.firstDay, let last = calendar.lastDay {
            parts.append("\(DisplayFormat.shortMonthName(first.month)) \(first.day) – \(DisplayFormat.shortMonthName(last.month)) \(last.day)")
        }
        return parts.joined(separator: " · ")
    }

    /// "Jess & Grandma watch Nora & Twins · weekdays from 7:45 AM until pickup".
    public func care(_ care: CareRule) -> String {
        "\(planner.names(care.caregivers)) watch\(care.caregivers.count == 1 ? "es" : "") \(planner.names(care.kids)) · "
            + "\(DisplayFormat.days(care.days)) from \(care.from.twelveHour) \(planner.careEnd(care.until))"
    }

    /// "Sam drives · weekdays, when school ends · School (Emma) → Grandparents' (Nora & Twins) → Home".
    public func loop(_ loop: PickupLoopRule) -> String {
        let stops = loop.stops.map { "\($0.place) (\(planner.names($0.collect)))" } + ["Home"]
        return "\(planner.names([loop.driver])) drives · \(DisplayFormat.days(loop.days)), \(planner.loopStart(loop)) · "
            + stops.joined(separator: " → ")
    }

    /// "Sam's calendar", "Sam & Kate · nobody named → ask",
    /// "Everyone · nobody named → Jess".
    public func calendar(_ calendar: CalendarRule) -> String {
        if let owner = calendar.soleMember, calendar.ifNobodyNamed == .members {
            return "\(DisplayFormat.possessive(planner.names([owner]))) calendar"
        }
        let members: String
        switch calendar.members {
        case .everyone: members = "Everyone"
        case let .people(ids): members = planner.names(ids)
        }
        switch calendar.ifNobodyNamed {
        case .members: return "\(members) · nobody named → all of them"
        case .ask: return "\(members) · nobody named → ask"
        case let .people(ids): return "\(members) · nobody named → \(planner.names(ids))"
        }
    }

    /// "6:30 AM · 12:00 PM · 3:15 PM (Time Sensitive)".
    public func checkIns(_ checkIns: [CheckInRule]) -> String {
        checkIns.map { $0.at.twelveHour + ($0.timeSensitive ? " (Time Sensitive)" : "") }.joined(separator: " · ")
    }

    /// The People list's second line: "Sam calendar · also "Dad"".
    public func person(_ person: Person) -> String {
        var parts: [String] = []
        for calendar in rules.calendars {
            if calendar.soleMember == person.id {
                parts.append("\(calendar.title) calendar")
            } else if case let .people(ids) = calendar.members, ids.contains(person.id) {
                parts.append("shares \(calendar.title)")
            }
            if case let .people(ids) = calendar.ifNobodyNamed, ids.contains(person.id) {
                parts.append("\(calendar.title) calendar default")
            }
        }
        let blocks = rules.blocks.filter { $0.who.contains(person.id) && $0.kind != .work }.map(\.title)
        if !blocks.isEmpty { parts.append(blocks.joined(separator: ", ")) }
        if let lane = person.lane, rules.people.filter({ $0.lane == lane }).count > 1 {
            parts.append("shares the \(lane) lane")
        }
        if !person.aliases.isEmpty {
            parts.append("also " + person.aliases.map { "\"\($0)\"" }.joined(separator: ", "))
        }
        return parts.isEmpty ? person.group.title : parts.joined(separator: " · ")
    }
}
