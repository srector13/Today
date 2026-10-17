import Foundation

/// Words for dates, times and spans, shared by the Today screen, widgets and
/// the spoken brief. English only, and never the device's locale or zone:
/// the times are already household-local.
public enum DisplayFormat {
    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    public static func monthName(_ month: Int) -> String {
        monthNames[(month - 1) % 12]
    }

    /// "Oct".
    public static func shortMonthName(_ month: Int) -> String {
        String(monthName(month).prefix(3))
    }

    /// "Tuesday".
    public static func weekdayName(_ weekday: Weekday) -> String {
        switch weekday {
        case .mon: "Monday"
        case .tue: "Tuesday"
        case .wed: "Wednesday"
        case .thu: "Thursday"
        case .fri: "Friday"
        case .sat: "Saturday"
        case .sun: "Sunday"
        }
    }

    /// "October 20".
    public static func monthDay(_ date: LocalDate) -> String {
        "\(monthName(date.month)) \(date.day)"
    }

    /// "Saturday, Oct 24".
    public static func weekdayShortDate(_ date: LocalDate) -> String {
        "\(weekdayName(date.weekday)), \(shortMonthName(date.month)) \(date.day)"
    }

    /// "Tue Oct 20".
    public static func shortDate(_ date: LocalDate) -> String {
        "\(date.weekday.shortName) \(shortMonthName(date.month)) \(date.day)"
    }

    /// "May 14, 2021".
    public static func longDate(_ date: LocalDate) -> String {
        "\(shortMonthName(date.month)) \(date.day), \(date.year)"
    }

    /// "today", "tomorrow", "in 4 days".
    public static func relativeDays(_ days: Int) -> String {
        switch days {
        case ..<0: "\(-days) days ago"
        case 0: "today"
        case 1: "tomorrow"
        default: "in \(days) days"
        }
    }

    /// "9" on the hour, else "9:30": the compact form for chips and spans.
    public static func compactTime(_ time: LocalTime) -> String {
        time.minute == 0 ? String(time.hour % 12 == 0 ? 12 : time.hour % 12) : time.short
    }

    /// "8:15–3:30", or "9–11:30".
    public static func span(_ start: LocalTime, _ end: LocalTime) -> String {
        "\(compactTime(start))–\(compactTime(end))"
    }

    /// "8:30 AM–5:00 PM".
    public static func twelveHourSpan(_ start: LocalTime, _ end: LocalTime) -> String {
        "\(start.twelveHour)–\(end.twelveHour)"
    }

    /// "in 50 min", "in 1 hr 10 min", "in 3 hr", "now".
    public static func until(_ start: Date, from now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return "now" }
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 || hours >= 3 ? "in \(hours) hr" : "in \(hours) hr \(rest) min"
    }

    /// The hour marks over the lanes: "2 PM" for the first, then "3", "4"...
    public static func hourMark(_ hour: Int, first: Bool) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return first ? "\(h12) \(hour < 12 ? "AM" : "PM")" : String(h12)
    }

    /// "every day", "weekdays", "weekends", "Tue, Thu".
    public static func days(_ set: DaySet) -> String {
        switch set {
        case .daily: "every day"
        case .weekdays: "weekdays"
        case .weekends: "weekends"
        default: set.days.sorted().map(\.shortName).joined(separator: ", ")
        }
    }

    /// "Jess's", "Twins'" (a shared lane's label is plural).
    public static func possessive(_ name: String, plural: Bool = false) -> String {
        plural && name.hasSuffix("s") ? name + "'" : name + "'s"
    }
}
