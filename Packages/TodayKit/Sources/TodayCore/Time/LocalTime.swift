import Foundation

/// A wall-clock time with no date and no time zone, written "08:15" or "8:15".
public struct LocalTime: Hashable, Comparable, Sendable {
    public let hour: Int
    public let minute: Int

    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Parses 24-hour "HH:mm"; a one-digit hour ("8:15") is accepted too.
    public init?(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        self.init(hour: h, minute: m)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    /// `nil` when the result would leave the day.
    public func adding(minutes: Int) -> LocalTime? {
        let total = minutesSinceMidnight + minutes
        guard (0..<(24 * 60)).contains(total) else { return nil }
        return LocalTime(hour: total / 60, minute: total % 60)
    }

    /// "08:15": the rules file's own spelling.
    public var hhmm: String { String(format: "%02d:%02d", hour, minute) }

    /// "8:15", the glanceable form: no leading zero, no AM/PM.
    public var short: String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d", h12, minute)
    }

    /// "8:15 AM".
    public var twelveHour: String { "\(short) \(hour < 12 ? "AM" : "PM")" }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

extension LocalTime: CustomStringConvertible {
    public var description: String { hhmm }
}

extension LocalTime: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let time = LocalTime(raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "\"\(raw)\" is not a time. Write 24-hour times in quotes, e.g. \"08:15\" or \"15:30\"."
            ))
        }
        self = time
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hhmm)
    }
}
