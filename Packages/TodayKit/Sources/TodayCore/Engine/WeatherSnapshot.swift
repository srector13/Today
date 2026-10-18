import Foundation

/// What the weather card and the brief need, in plain values: the app fills
/// it from WeatherKit, seeded days from `SampleHousehold`.
public struct WeatherSnapshot: Sendable, Equatable {
    public struct Hour: Sendable, Equatable, Identifiable {
        public let time: Date
        /// °F.
        public let temperature: Int
        /// 0...1.
        public let precipitationChance: Double
        /// An SF Symbol name.
        public let symbol: String

        public var id: Date { time }

        public init(time: Date, temperature: Int, precipitationChance: Double, symbol: String) {
            self.time = time
            self.temperature = temperature
            self.precipitationChance = precipitationChance
            self.symbol = symbol
        }
    }

    /// °F.
    public let temperature: Int
    /// "Partly cloudy".
    public let condition: String
    public let symbol: String
    public let high: Int
    public let low: Int
    public let hours: [Hour]
    /// Conditions now; `false` for another day's forecast, where
    /// `temperature` is the high.
    public let isCurrent: Bool

    public init(
        temperature: Int, condition: String, symbol: String, high: Int, low: Int, hours: [Hour],
        isCurrent: Bool = true
    ) {
        self.temperature = temperature
        self.condition = condition
        self.symbol = symbol
        self.high = high
        self.low = low
        self.hours = hours
        self.isCurrent = isCurrent
    }

    /// From this chance up, rain is "likely" (the card tints the hour).
    public static let likely = 0.5

    /// The next `count` hours, starting with the one under way.
    public func hours(from now: Date, count: Int) -> [Hour] {
        Array(hours.filter { $0.time.addingTimeInterval(3600) > now }.prefix(count))
    }

    /// The highest chance of rain from the hour under way at `start`
    /// through the hour `end` falls in (home at 4:00 counts the 4 PM hour).
    public func rainChance(from start: Date, through end: Date) -> Double? {
        let overlapping = hours.filter { $0.time <= end && $0.time.addingTimeInterval(3600) > start }
        return overlapping.map(\.precipitationChance).max()
    }

    /// The first hour from `now` on with rain likely.
    public func firstLikelyRain(after now: Date, before end: Date) -> Hour? {
        hours.first { $0.time.addingTimeInterval(3600) > now && $0.time < end && $0.precipitationChance >= Self.likely }
    }

    /// "40%".
    public static func percent(_ chance: Double) -> String {
        "\(Int((chance * 100 / 10).rounded()) * 10)%"
    }
}
