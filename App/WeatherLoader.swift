import CoreLocation
import Foundation
import TodayCore
import WeatherKit

/// Today's forecast for the household's home, from WeatherKit, as a
/// `WeatherSnapshot`. WeatherKit needs the app's App ID to carry the
/// WeatherKit capability; without it (a re-sign that drops it) this throws
/// and the card says weather isn't available.
enum WeatherLoader {
    struct Result: Sendable {
        let snapshot: WeatherSnapshot
        /// Apple's required "Data sources" link.
        let legalPage: URL?
    }

    static let fallbackLegalPage = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    /// Today: the current conditions and today's hours. Another day: that
    /// day's forecast, with its high standing in for "now".
    static func load(_ home: HomeLocation, date: LocalDate, clock: HouseholdClock, isToday: Bool) async throws -> Result {
        let location = CLLocation(latitude: home.latitude, longitude: home.longitude)
        let service = WeatherService.shared
        let dayStart = clock.startOfDay(date)
        let dayEnd = clock.endOfDay(date)
        let snapshot: WeatherSnapshot
        if isToday {
            let (current, hourly, daily) = try await service.weather(for: location, including: .current, .hourly, .daily)
            let day = daily.forecast.first { $0.date >= dayStart.addingTimeInterval(-12 * 3600) && $0.date < dayEnd }
                ?? daily.forecast.first
            let temperature = fahrenheit(current.temperature)
            snapshot = WeatherSnapshot(
                temperature: temperature,
                condition: current.condition.description,
                symbol: current.symbolName,
                high: day.map { fahrenheit($0.highTemperature) } ?? temperature,
                low: day.map { fahrenheit($0.lowTemperature) } ?? temperature,
                hours: hours(hourly.forecast, from: dayStart, to: dayEnd)
            )
        } else {
            let (hourly, daily) = try await service.weather(
                for: location,
                including: .hourly(startDate: dayStart, endDate: dayEnd),
                .daily(startDate: dayStart.addingTimeInterval(-12 * 3600), endDate: dayEnd)
            )
            guard let day = daily.forecast.last(where: { $0.date < dayEnd }) else { throw NoForecast() }
            let high = fahrenheit(day.highTemperature)
            snapshot = WeatherSnapshot(
                temperature: high,
                condition: day.condition.description,
                symbol: day.symbolName,
                high: high,
                low: fahrenheit(day.lowTemperature),
                hours: hours(hourly.forecast, from: dayStart, to: dayEnd),
                isCurrent: false
            )
        }
        let legalPage = try? await service.attribution.legalPageURL
        return Result(snapshot: snapshot, legalPage: legalPage ?? fallbackLegalPage)
    }

    struct NoForecast: LocalizedError {
        var errorDescription: String? { "No forecast for that day yet." }
    }

    private static func hours(_ forecast: [HourWeather], from start: Date, to end: Date) -> [WeatherSnapshot.Hour] {
        forecast
            .filter { $0.date >= start && $0.date < end }
            .map { hour in
                WeatherSnapshot.Hour(time: hour.date, temperature: fahrenheit(hour.temperature),
                                     precipitationChance: hour.precipitationChance, symbol: hour.symbolName)
            }
    }

    static func fahrenheit(_ temperature: Measurement<UnitTemperature>) -> Int {
        Int(temperature.converted(to: .fahrenheit).value.rounded())
    }
}

/// One reading of the phone's location, for "Use Current Location".
enum LocationFinder {
    enum Failure: LocalizedError {
        case denied
        case timedOut

        var errorDescription: String? {
            switch self {
            case .denied: "Location access is off for Today (Settings › Privacy › Location Services)."
            case .timedOut: "Couldn't find this iPhone's location. Try again outdoors or with Wi-Fi on."
            }
        }
    }

    static func current() async throws -> (latitude: Double, longitude: Double) {
        try await withThrowingTaskGroup(of: (latitude: Double, longitude: Double).self) { group in
            group.addTask { try await firstFix() }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw Failure.timedOut
            }
            defer { group.cancelAll() }
            guard let fix = try await group.next() else { throw Failure.timedOut }
            return fix
        }
    }

    private static func firstFix() async throws -> (latitude: Double, longitude: Double) {
        // Asks for When In Use access the first time.
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location {
                return (location.coordinate.latitude, location.coordinate.longitude)
            }
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                throw Failure.denied
            }
        }
        throw Failure.timedOut
    }
}
