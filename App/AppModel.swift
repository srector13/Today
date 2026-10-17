import Foundation
import Observation
import TodayCore
import TodaySources

/// Loads the household rules from the shared store and today's calendars,
/// reminders and birthdays from EventKit, and builds the day plan.
@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case loading
        case ready
        case rulesError(String)
    }

    private(set) var status: Status = .loading
    private(set) var warnings: [RulesIssue] = []
    /// The saved rules were unusable; the last good copy is in use.
    private(set) var recoveredFrom: String?
    private(set) var bundledUpdateAvailable = false
    private(set) var calendarAccess = EventKitSource.calendarAccess
    private(set) var remindersAccess = EventKitSource.remindersAccess
    private(set) var planner: DayPlanner?
    private(set) var plan: DayPlan?

    private let store = HouseholdStore(directory: AppRules.storeDirectory)
    private let source = EventKitSource()

    func load() async {
        guard let url = AppRules.bundledURL, let bundled = try? Data(contentsOf: url) else {
            status = .rulesError("household.json is missing from the app bundle.")
            return
        }
        do {
            let loaded = try store.load(bundled: bundled)
            warnings = loaded.warnings
            recoveredFrom = loaded.recoveredFrom?.description
            bundledUpdateAvailable = loaded.bundledUpdateAvailable
            planner = try DayPlanner(rules: loaded.rules)
            status = .ready
        } catch {
            status = .rulesError(String(describing: error))
            return
        }
        await refresh()
    }

    /// Rebuilds today's plan from what the device can read right now.
    func refresh() async {
        guard let planner else { return }
        calendarAccess = EventKitSource.calendarAccess
        remindersAccess = EventKitSource.remindersAccess
        let today = planner.clock.localDate(of: AppLaunch.now)
        let input = await source.input(for: today, rules: planner.rules, clock: planner.clock)
        plan = planner.plan(for: today, input: input)
    }

    func connectCalendars() async {
        let granted = await source.requestAccess()
        calendarAccess = granted.calendars
        remindersAccess = granted.reminders
        await refresh()
    }
}
