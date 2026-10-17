import Foundation

/// The one thing to glance at: the Today screen's "Up next" card and,
/// later, the Lock Screen widget ("Pickup loop 3:30").
public struct NextUp: Sendable, Equatable {
    public let item: TimelineItem
    /// Already started and not over.
    public let isUnderway: Bool
    /// The loop's stops, when the item is the pickup loop.
    public let loop: PickupLoopPlan?

    /// How far ahead an important item (the pickup loop) takes "Up next"
    /// over earlier, ordinary ones.
    public static let importantLead: TimeInterval = 90 * 60

    /// Timed items that matter (`normal` and up) and aren't over. An
    /// important one starting within `importantLead` wins; otherwise the
    /// earliest. Background context (work, care) and the kids' rides never
    /// show here.
    public static func find(in plan: DayPlan, now: Date) -> NextUp? {
        let candidates = plan.items
            .filter { !$0.isAllDay && $0.importance >= .normal && $0.end > now }
            .sorted { ($0.start, $1.importance, $0.id) < ($1.start, $0.importance, $1.id) }
        let soonImportant = candidates.first {
            $0.importance == .high && $0.start <= now.addingTimeInterval(importantLead)
        }
        guard let item = soonImportant ?? candidates.first else { return nil }
        return NextUp(item: item, isUnderway: item.start <= now,
                      loop: item.kind == .pickupLoop ? plan.pickupLoop : nil)
    }

    /// "3:30 PM · in 50 min · Sam drives", "7:00 PM · in 4 hr · Jess".
    public func subtitle(planner: DayPlanner, now: Date) -> String {
        let clock = planner.clock
        let start = clock.localTime(of: item.start)
        var parts = [isUnderway ? "Now until \(clock.localTime(of: item.end).twelveHour)" : start.twelveHour]
        if !isUnderway { parts.append(DisplayFormat.until(item.start, from: now)) }
        if let loop {
            parts.append("\(planner.names([loop.driver])) drives")
        } else if !item.people.isEmpty {
            parts.append(planner.names(item.people))
        }
        return parts.joined(separator: " · ")
    }

    /// The Lock Screen line: "Pickup loop 3:30".
    public func shortLine(clock: HouseholdClock) -> String {
        "\(item.title) \(clock.localTime(of: item.start).short)"
    }
}
