import Foundation
import TodayCore

/// The household rules the app ships with (`Rules/household.json`), and
/// where the app keeps its own editable copy.
enum AppRules {
    static let appGroup = "group.PolarReailty.Today"

    static var bundledURL: URL? {
        Bundle.main.url(forResource: "household", withExtension: "json")
    }

    /// The App Group container, so the widget reads the same rules. Unsigned
    /// builds (CI, or a re-sign without the group) have no container; the
    /// app's own Application Support folder stands in.
    static var storeDirectory: URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return group.appendingPathComponent("Household", isDirectory: true)
        }
        return URL.applicationSupportDirectory.appendingPathComponent("Household", isDirectory: true)
    }

    static func load() -> Result<LoadedRules, RulesError> {
        guard let url = bundledURL else {
            return .failure(RulesError(issues: [RulesIssue(.error, "", "household.json is missing from the app bundle.")]))
        }
        return Result { () throws(RulesError) in try RulesLoader.load(contentsOf: url) }
    }

    /// `nil` when the bundled rules load; otherwise what's wrong, for display.
    static func loadErrorMessage() -> String? {
        switch load() {
        case .success: nil
        case let .failure(error): error.description
        }
    }
}

/// Launch-environment hooks for UI tests and seeded screenshots. Read only
/// in Debug builds, like MyTeams' `MYTEAMS_HOME_NOW`.
enum AppLaunch {
    /// `TODAY_SEED=2026-10-21`: show the sample household's seeded day.
    static let seedKey = "TODAY_SEED"
    /// `TODAY_NOW=<seconds since 1970>`: pin the clock. Seeded days pin it
    /// to 2:40 PM on the seeded day without it.
    static let nowKey = "TODAY_NOW"

    static var seedDate: LocalDate? {
        #if DEBUG
        ProcessInfo.processInfo.environment[seedKey].flatMap(LocalDate.init(iso:))
        #else
        nil
        #endif
    }

    static var pinnedNow: Date? {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment[nowKey], let seconds = TimeInterval(raw) {
            return Date(timeIntervalSince1970: seconds)
        }
        #endif
        return nil
    }
}
