import Foundation

/// The stretch of the day the lanes draw.
public struct TimelineWindow: Sendable, Equatable {
    public let date: LocalDate
    public let start: LocalTime
    public let end: LocalTime
    public let startInstant: Date
    public let endInstant: Date
    /// Starts at the current hour rather than the day window's start.
    public let isRestOfDay: Bool

    init(date: LocalDate, start: LocalTime, end: LocalTime, clock: HouseholdClock, isRestOfDay: Bool) {
        self.date = date
        self.start = start
        self.end = end
        startInstant = clock.instant(date, start)
        endInstant = clock.instant(date, end)
        self.isRestOfDay = isRestOfDay
    }

    /// The rules' whole day window.
    public static func day(_ plan: DayPlan) -> TimelineWindow {
        TimelineWindow(date: plan.date, start: plan.dayWindow.start, end: plan.dayWindow.end,
                       clock: plan.clock, isRestOfDay: false)
    }

    /// "Rest of today": from the current hour to the window's end. The whole
    /// window on another day, before it opens, or in its last hour.
    public static func restOfDay(_ plan: DayPlan, now: Date) -> TimelineWindow {
        guard plan.clock.localDate(of: now) == plan.date else { return day(plan) }
        let time = plan.clock.localTime(of: now)
        guard let hour = LocalTime(hour: time.hour, minute: 0),
              hour > plan.dayWindow.start,
              let lastHour = plan.dayWindow.end.adding(minutes: -60), hour < lastHour
        else { return day(plan) }
        return TimelineWindow(date: plan.date, start: hour, end: plan.dayWindow.end,
                              clock: plan.clock, isRestOfDay: true)
    }

    /// Where `instant` falls, 0 at the start and 1 at the end, clamped.
    public func fraction(_ instant: Date) -> Double {
        let total = endInstant.timeIntervalSince(startInstant)
        guard total > 0 else { return 0 }
        return min(max(instant.timeIntervalSince(startInstant) / total, 0), 1)
    }

    public func contains(_ instant: Date) -> Bool {
        instant >= startInstant && instant <= endInstant
    }

    public struct HourMark: Sendable, Equatable, Identifiable {
        public let hour: Int
        public let fraction: Double
        public let label: String
        public var id: Int { hour }
    }

    /// One mark per whole hour from the start through the end.
    public func hourMarks(clock: HouseholdClock) -> [HourMark] {
        let first = start.minute == 0 ? start.hour : start.hour + 1
        guard first <= end.hour else { return [] }
        return (first...end.hour).compactMap { hour in
            guard let time = LocalTime(hour: hour, minute: 0) else { return nil }
            return HourMark(hour: hour, fraction: fraction(clock.instant(date, time)),
                            label: DisplayFormat.hourMark(hour, first: hour == first))
        }
    }

    /// "2 PM – 9 PM".
    public var label: String {
        func text(_ t: LocalTime) -> String {
            t.minute == 0 ? DisplayFormat.hourMark(t.hour, first: true) : t.twelveHour
        }
        return "\(text(start)) – \(text(end))"
    }
}

/// One item drawn on a lane: where it sits, and how loud it is.
public struct LaneBlock: Sendable, Equatable, Identifiable {
    public enum Style: Sendable, Equatable {
        /// Full height, faint: work, school, care.
        case background
        /// The lane's color at medium strength: appointments, rides.
        case normal
        /// Solid lane color: the pickup loop, important events.
        case high
    }

    public let item: TimelineItem
    /// 0...1 across the window.
    public let start: Double
    public let end: Double
    public let style: Style
    /// Overlapping foreground items split the lane's height into `rows`.
    public let row: Int
    public let rows: Int

    public var id: String { item.id }
}

public enum LaneLayout {
    /// The lane's timed items inside `window`, with overlapping foreground
    /// items stacked in rows. Background items sit behind, full height.
    public static func blocks(for lane: Lane, in window: TimelineWindow) -> [LaneBlock] {
        let visible = lane.items.filter { item in
            guard !item.isAllDay else { return false }
            if item.start == item.end {
                return item.start >= window.startInstant && item.start < window.endInstant
            }
            return item.start < window.endInstant && item.end > window.startInstant
        }
        var blocks: [LaneBlock] = visible.filter { style(of: $0) == .background }.map {
            LaneBlock(item: $0, start: window.fraction($0.start), end: window.fraction($0.end),
                      style: .background, row: 0, rows: 1)
        }

        let foreground = visible.filter { style(of: $0) != .background }
            .sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        var cluster: [(item: TimelineItem, row: Int)] = []
        var rowEnds: [Date] = []
        var clusterEnd = Date.distantPast
        func flush() {
            let rows = max(rowEnds.count, 1)
            blocks += cluster.map {
                LaneBlock(item: $0.item, start: window.fraction($0.item.start), end: window.fraction($0.item.end),
                          style: style(of: $0.item), row: $0.row, rows: rows)
            }
            cluster = []
            rowEnds = []
        }
        for item in foreground {
            if !cluster.isEmpty, item.start >= clusterEnd { flush() }
            let end = max(item.end, item.start)
            if let row = rowEnds.firstIndex(where: { $0 <= item.start }) {
                rowEnds[row] = end
                cluster.append((item, row))
            } else {
                rowEnds.append(end)
                cluster.append((item, rowEnds.count - 1))
            }
            clusterEnd = cluster.count == 1 ? end : max(clusterEnd, end)
        }
        flush()
        return blocks
    }

    /// The lane's all-day items (trips, picture day): shown as chips, not bars.
    public static func allDay(for lane: Lane) -> [TimelineItem] {
        lane.items.filter(\.isAllDay)
    }

    /// Work, school and care are the day's backdrop; everything else is as
    /// loud as it is important.
    public static func style(of item: TimelineItem) -> LaneBlock.Style {
        switch item.kind {
        case .work, .school, .care: return .background
        case .activity, .appointment, .pickupLoop: break
        }
        return switch item.importance {
        case .background: .background
        case .low, .normal: .normal
        case .high: .high
        }
    }
}
