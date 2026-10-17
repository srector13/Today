import Foundation

/// A calendar date with no time of day and no time zone, written "2026-10-20".
///
/// The rules file speaks in local dates and times. They become instants
/// (`Date`) only through `HouseholdClock`, which pins the household's zone.
/// The arithmetic here works on proleptic Gregorian day numbers, so nothing
/// in it can pick up the device's calendar or time zone.
public struct LocalDate: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month),
              (1...Self.daysInMonth(year: year, month: month)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "YYYY-MM-DD".
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// The date `dayNumber` days after 1970-01-01 (`civil_from_days`).
    public init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        year = yoe + era * 400 + (m <= 2 ? 1 : 0)
        month = m
        day = d
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(dayNumber: dayNumber + days)
    }

    public var weekday: Weekday {
        // 1970-01-01 was a Thursday; Weekday.allCases starts on Monday.
        let index = ((dayNumber + 3) % 7 + 7) % 7
        return Weekday.allCases[index]
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}

extension LocalDate: CustomStringConvertible {
    public var description: String { iso }
}

extension LocalDate: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let date = LocalDate(iso: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "\"\(raw)\" is not a date. Write dates as YYYY-MM-DD, e.g. \"2026-11-26\"."
            ))
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}
