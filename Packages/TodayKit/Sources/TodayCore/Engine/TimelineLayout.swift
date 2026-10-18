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

    /// A mark per whole hour from the start through the end; every second
    /// or third hour on a long window, so the labels don't collide.
    public func hourMarks(clock: HouseholdClock) -> [HourMark] {
        let first = start.minute == 0 ? start.hour : start.hour + 1
        guard first <= end.hour else { return [] }
        let span = end.hour - first
        let step = span <= 8 ? 1 : span <= 12 ? 2 : 3
        return stride(from: first, through: end.hour, by: step).compactMap { hour in
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

/// One line of a lane in the list view: "3:15 PM · Call with vendor ·
/// Until 3:45 PM".
public struct AgendaRow: Sendable, Equatable, Identifiable {
    public let item: TimelineItem
    /// "3:15 PM", "Now" while it's on, or "All day".
    public let time: String
    /// "Until 3:45 PM", then the item's own detail: where it is. The
    /// driver's pickup loop has its stops instead.
    public let detail: String?
    public let style: LaneBlock.Style

    public var id: String { item.id }
}

public enum LaneAgenda {
    /// The lane's items as a list: all-day ones first, then the timed ones
    /// by start. Given `now` (today), what's already over is left out.
    public static func rows(for lane: Lane, now: Date?, clock: HouseholdClock) -> [AgendaRow] {
        let allDay = lane.items.filter(\.isAllDay).map {
            AgendaRow(item: $0, time: "All day", detail: $0.detail, style: LaneLayout.style(of: $0))
        }
        let timed = lane.items
            .filter { item in
                guard !item.isAllDay else { return false }
                guard let now else { return true }
                return item.end > now || (item.start == item.end && item.start >= now)
            }
            .sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
            .map { item in
                let underway = now.map { item.start <= $0 } ?? false
                var detail: [String] = []
                // The driver's loop lists its stops, home time included.
                if item.end > item.start, item.id != "loop" {
                    detail.append("Until \(clock.localTime(of: item.end).twelveHour)")
                }
                if let more = item.detail { detail.append(more) }
                return AgendaRow(item: item, time: underway ? "Now" : clock.localTime(of: item.start).twelveHour,
                                 detail: detail.isEmpty ? nil : detail.joined(separator: " · "),
                                 style: LaneLayout.style(of: item))
            }
        return allDay + timed
    }
}
