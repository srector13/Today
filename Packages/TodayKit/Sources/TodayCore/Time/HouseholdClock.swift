import Foundation

/// The one place local dates and times become instants, and back.
///
/// Every conversion goes through a Gregorian calendar pinned to the
/// household's zone (America/Chicago), never the device's. A phone that
/// travels, or a simulator set to UTC, still sees school at 8:15 Chicago
/// time. `scripts/check-time-zone-discipline.sh` fails CI if code reaches
/// for the device's calendar or zone instead.
public struct HouseholdClock: Sendable {
    public let timeZone: TimeZone
    public let calendar: Calendar

    public struct UnknownTimeZone: Error, CustomStringConvertible {
        public let identifier: String
        public var description: String { "Unknown time zone \"\(identifier)\"" }
    }

    public init(timeZoneIdentifier: String) throws {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else {
            throw UnknownTimeZone(identifier: timeZoneIdentifier)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.timeZone = zone
        self.calendar = calendar
    }

    public static let chicago = try! HouseholdClock(timeZoneIdentifier: "America/Chicago")

    /// The instant `time` happens on `date` in the household's zone. A wall
    /// time skipped by a spring-forward change resolves to the next valid one.
    public func instant(_ date: LocalDate, _ time: LocalTime) -> Date {
        let components = DateComponents(
            year: date.year, month: date.month, day: date.day,
            hour: time.hour, minute: time.minute
        )
        return calendar.date(from: components)!
    }

    public func startOfDay(_ date: LocalDate) -> Date {
        calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day))!
    }

    /// The start of the next day: days are half-open, [start, end).
    public func endOfDay(_ date: LocalDate) -> Date {
        startOfDay(date.adding(days: 1))
    }

    public func localDate(of instant: Date) -> LocalDate {
        let c = calendar.dateComponents([.year, .month, .day], from: instant)
        return LocalDate(year: c.year!, month: c.month!, day: c.day!)!
    }

    public func localTime(of instant: Date) -> LocalTime {
        let c = calendar.dateComponents([.hour, .minute], from: instant)
        return LocalTime(hour: c.hour!, minute: c.minute!)!
    }
}
