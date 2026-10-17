import Foundation

public enum Weekday: String, CaseIterable, Codable, Sendable, Comparable {
    case mon, tue, wed, thu, fri, sat, sun

    public var isWeekend: Bool { self == .sat || self == .sun }

    public var shortName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// The days a rule applies on. In the rules file: `"daily"`, `"weekdays"`,
/// `"weekends"`, or a list such as `["tue", "thu"]`.
public struct DaySet: Hashable, Sendable {
    public let days: Set<Weekday>

    public init(_ days: Set<Weekday>) { self.days = days }

    public static let daily = DaySet(Set(Weekday.allCases))
    public static let weekdays = DaySet([.mon, .tue, .wed, .thu, .fri])
    public static let weekends = DaySet([.sat, .sun])

    public func contains(_ weekday: Weekday) -> Bool { days.contains(weekday) }

    public func isSuperset(of other: DaySet) -> Bool { days.isSuperset(of: other.days) }

    /// The days in `other` this set lacks, in week order.
    public func missing(from other: DaySet) -> [Weekday] {
        other.days.subtracting(days).sorted()
    }
}

extension DaySet: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let word = try? container.decode(String.self) {
            switch word {
            case "daily": self = .daily
            case "weekdays": self = .weekdays
            case "weekends": self = .weekends
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "\"\(word)\" is not a day set. Use \"daily\", \"weekdays\", \"weekends\" or a list like [\"tue\", \"thu\"]."
                ))
            }
            return
        }
        let list = try container.decode([String].self)
        var days = Set<Weekday>()
        for name in list {
            guard let day = Weekday(rawValue: name.lowercased()) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "\"\(name)\" is not a day. Use mon, tue, wed, thu, fri, sat or sun."
                ))
            }
            days.insert(day)
        }
        guard !days.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "The day list is empty."))
        }
        self.init(days)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .daily: try container.encode("daily")
        case .weekdays: try container.encode("weekdays")
        case .weekends: try container.encode("weekends")
        default: try container.encode(days.sorted().map(\.rawValue))
        }
    }
}

extension DaySet: CustomStringConvertible {
    public var description: String {
        switch self {
        case .daily: "daily"
        case .weekdays: "weekdays"
        case .weekends: "weekends"
        default: days.sorted().map(\.shortName).joined(separator: "/")
        }
    }
}
