import Foundation

/// A plain-text rendering of a `DayPlan`: a 15-minute lane chart, then each
/// lane's items. It's how M1 shows a day before there is any UI, and the
/// golden files in the tests pin it, so a rules or engine change that moves
/// anything shows up as a readable diff.
public enum PlanText {
    public static func render(_ plan: DayPlan, planner: DayPlanner) -> String {
        var out: [String] = []
        out.append("\(longDate(plan.date))  (\(plan.clock.timeZone.identifier))")
        out.append("")

        for school in plan.schools {
            let who = planner.names(school.people)
            switch school.state {
            case let .inSession(start, end, early):
                out.append(row(school.title, "in session \(start.short)–\(end.short)\(early ? " (early release)" : "") · \(who)"))
            case let .noSchool(label):
                out.append(row(school.title, "no school\(label.map { " (\($0))" } ?? "") · \(who)"))
            case .outOfTerm:
                out.append(row(school.title, "out of term · \(who)"))
            }
        }
        if let loop = plan.pickupLoop {
            let stops = loop.stops.map { "\($0.time.short) \($0.place) (\(planner.names($0.kids)))" }
            let route = (stops + ["home ~\(loop.end.short)"]).joined(separator: " → ")
            out.append(row(loop.title, route + (loop.usedFallbackStart ? "  [fallback start]" : "")))
        }
        if plan.schools.isEmpty && plan.pickupLoop == nil {
            out.append(row("Schedule", plan.isWeekend ? "weekend: no school, no pickup loop" : "no school, no pickup loop"))
        }

        out.append("")
        out.append("Alerts")
        if plan.alerts.isEmpty { out.append("  (none)") }
        for alert in plan.alerts {
            out.append("  ! [\(alert.kind.rawValue)] \(alert.message)")
        }

        out.append("")
        out.append("Needs")
        if plan.needs.isEmpty { out.append("  (none)") }
        for need in plan.needs {
            out.append("  \(pad(planner.names(need.people), 10)) \(need.items.joined(separator: ", "))")
        }

        out.append("")
        out += chart(plan)

        out.append("")
        for group in plan.laneGroups {
            out.append(group.group.title)
            for lane in group.lanes {
                if case let .noData(reason) = lane.data {
                    out.append("  \(lane.label)  [NO DATA: \(reason)]")
                } else {
                    out.append("  \(lane.label)")
                }
                if lane.items.isEmpty {
                    out.append(lane.data.isKnown ? "    (nothing scheduled)" : "    (unknown)")
                }
                for item in lane.items {
                    out.append("    \(itemLine(item, plan: plan, lane: lane, planner: planner))")
                }
            }
        }
        if !plan.missingCalendars.isEmpty {
            out.append("")
            out.append("Not on this device: \(plan.missingCalendars.joined(separator: ", "))")
        }
        if !plan.unlistedCalendars.isEmpty {
            out.append("")
            out.append("Not in the rules (ignored): \(plan.unlistedCalendars.joined(separator: ", "))")
        }
        return out.map { line in
            String(line.reversed().drop { $0 == " " }.reversed())
        }.joined(separator: "\n") + "\n"
    }

    // MARK: Chart

    /// Chart letters, strongest first: where items overlap, the first wins.
    static let legend: [(ItemKind, Character)] = [
        (.pickupLoop, "P"), (.appointment, "E"), (.activity, "A"),
        (.school, "S"), (.care, "C"), (.work, "W"),
    ]

    static func chart(_ plan: DayPlan) -> [String] {
        let start = plan.dayWindow.start.minutesSinceMidnight
        let end = plan.dayWindow.end.minutesSinceMidnight
        let slots = stride(from: start, to: end, by: 15).map { minute in
            (plan.clock.instant(plan.date, LocalTime(hour: minute / 60, minute: minute % 60)!),
             plan.clock.instant(plan.date, LocalTime(hour: (minute + 15) / 60 % 24, minute: (minute + 15) % 60)!))
        }
        var hours = ""
        for minute in stride(from: start, to: end, by: 60) {
            let hour = minute / 60
            let label = "\(hour % 12 == 0 ? 12 : hour % 12)\(hour < 12 ? "a" : "p")"
            hours += pad(label, 4)
        }
        var lines = ["  " + pad("", 10) + hours]
        for group in plan.laneGroups {
            lines.append(group.group.title)
            for lane in group.lanes {
                let timed = lane.items.filter { !$0.isAllDay }
                let empty: Character = lane.data.isKnown ? "·" : "?"
                let cells = slots.map { slot -> Character in
                    let covering = timed.filter { $0.overlaps(slot.0, slot.1) }
                    return legend.first { entry in covering.contains { $0.kind == entry.0 } }?.1 ?? empty
                }
                lines.append("  " + pad(String(lane.label.prefix(9)), 10) + String(cells))
            }
        }
        lines.append("  " + legend.map { "\($0.1) \($0.0.rawValue)" }.joined(separator: " · ") + " · \u{00B7} nothing · ? no data")
        return lines
    }

    // MARK: Lines

    static func itemLine(_ item: TimelineItem, plan: DayPlan, lane: Lane, planner: DayPlanner) -> String {
        let time = item.isAllDay
            ? pad("all day", 11)
            : "\(plan.clock.localTime(of: item.start).hhmm)–\(plan.clock.localTime(of: item.end).hhmm)"
        var line = "\(time)  \(item.title)"
        if let detail = item.detail {
            line += " · \(detail)"
        }
        if case let .calendar(title, attribution) = item.origin {
            line += "  [\(title): \(attribution.rawValue)]"
        }
        // Who else shares an event, when it isn't just this lane.
        let others = item.people.filter { !lane.people.contains($0) }
        if item.kind == .appointment, !others.isEmpty {
            line += "  (with \(planner.names(others)))"
        }
        return line
    }

    static func row(_ label: String, _ value: String) -> String {
        "\(pad(label, 12)) \(value)"
    }

    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    static func longDate(_ date: LocalDate) -> String {
        let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let months = ["January", "February", "March", "April", "May", "June", "July",
                      "August", "September", "October", "November", "December"]
        let weekday = weekdays[Weekday.allCases.firstIndex(of: date.weekday)!]
        return "\(weekday), \(months[date.month - 1]) \(date.day), \(date.year)"
    }
}
