import Foundation
import Observation
import TodayCore
import TodaySources

/// The app's state: the household rules from the shared store, today's
/// plan from EventKit, the weather, and which needs are checked off.
///
/// Seeded mode (`TODAY_SEED`, Debug only) runs the same screens on the
/// sample household and its sample events, with a pinned clock, for
/// screenshots and UI tests. Its edits go to a throwaway store.
@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case loading
        case ready
        case rulesError(String)
    }

    enum WeatherState: Equatable {
        case idle
        case loading
        case ready
        /// No home location in the rules yet.
        case needsHome
        case unavailable(String)
    }

    let seedDate: LocalDate?
    var isSeeded: Bool { seedDate != nil }

    private(set) var status: Status = .loading
    private(set) var warnings: [RulesIssue] = []
    /// The saved rules were unusable; the last good copy is in use.
    private(set) var recoveredFrom: String?
    private(set) var bundledUpdateAvailable = false
    private(set) var calendarAccess: EventKitSource.Access
    private(set) var remindersAccess: EventKitSource.Access
    private(set) var planner: DayPlanner?
    private(set) var plan: DayPlan?
    private(set) var now: Date
    private(set) var weather: WeatherSnapshot?
    private(set) var weatherState: WeatherState = .idle
    private(set) var weatherLegalPage: URL?
    private(set) var deviceCalendars: [DeviceCalendar] = []
    private(set) var deviceReminderLists: [String] = []
    private(set) var doneNeeds: Set<String> = []

    @ObservationIgnored let store: HouseholdStore
    @ObservationIgnored private let source = EventKitSource()
    @ObservationIgnored private var bundled: Data?
    @ObservationIgnored private var lastInput: DayInput?
    @ObservationIgnored private var weatherFetchedAt: Date?

    var rules: HouseholdRules? { planner?.rules }

    init(seed: LocalDate? = AppLaunch.seedDate) {
        seedDate = seed
        if let seed {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SeededHousehold-\(seed.iso)", isDirectory: true)
            try? FileManager.default.removeItem(at: directory)
            store = HouseholdStore(directory: directory)
            calendarAccess = .granted
            remindersAccess = .granted
            now = AppLaunch.pinnedNow ?? SampleHousehold.now(on: seed)
        } else {
            store = HouseholdStore(directory: AppRules.storeDirectory)
            calendarAccess = EventKitSource.calendarAccess
            remindersAccess = EventKitSource.remindersAccess
            now = AppLaunch.pinnedNow ?? Date()
        }
    }

    /// The day on screen: the seeded day, or today in the household's zone.
    var date: LocalDate? {
        if let seedDate { return seedDate }
        return planner.map { $0.clock.localDate(of: now) }
    }

    // MARK: Loading

    func load() async {
        let data: Data
        if isSeeded {
            data = Data(SampleHousehold.rulesJSON.utf8)
        } else {
            guard let url = AppRules.bundledURL, let file = try? Data(contentsOf: url) else {
                status = .rulesError("household.json is missing from the app bundle.")
                return
            }
            data = file
        }
        bundled = data
        do {
            let loaded = try store.load(bundled: data)
            recoveredFrom = loaded.recoveredFrom?.description
            bundledUpdateAvailable = loaded.bundledUpdateAvailable
            try use(loaded.rules, warnings: loaded.warnings)
            status = .ready
        } catch {
            status = .rulesError(String(describing: error))
            return
        }
        await refresh()
    }

    private func use(_ rules: HouseholdRules, warnings: [RulesIssue]) throws {
        planner = try DayPlanner(rules: rules)
        self.warnings = warnings.filter { $0.severity == .warning }
    }

    /// Rebuilds the day from what the device can read right now.
    func refresh() async {
        guard let planner else { return }
        if !isSeeded { now = AppLaunch.pinnedNow ?? Date() }
        guard let date else { return }
        let input: DayInput
        if isSeeded {
            input = SampleHousehold.input(on: date)
            deviceCalendars = Self.sampleCalendars(on: date)
            deviceReminderLists = ["Groceries", "Kids"]
        } else {
            calendarAccess = EventKitSource.calendarAccess
            remindersAccess = EventKitSource.remindersAccess
            input = await source.input(for: date, rules: planner.rules, clock: planner.clock)
            deviceCalendars = await source.deviceCalendars()
            deviceReminderLists = await source.reminderListTitles()
        }
        lastInput = input
        // The rules may have been saved while EventKit was reading.
        let current = self.planner ?? planner
        plan = current.plan(for: date, input: input)
        doneNeeds = NeedsLog.done(on: date, persisted: !isSeeded)
        await refreshWeather()
    }

    /// Moves the clock on; a new day reloads everything.
    func tick() {
        guard !isSeeded, AppLaunch.pinnedNow == nil, let planner else { return }
        let next = Date()
        let newDay = planner.clock.localDate(of: next) != plan?.date
        now = next
        let stale = weatherFetchedAt.map { next.timeIntervalSince($0) > 30 * 60 } ?? true
        if newDay {
            Task { await refresh() }
        } else if stale, weatherState != .needsHome {
            Task { await refreshWeather() }
        }
    }

    func connectCalendars() async {
        let granted = await source.requestAccess()
        calendarAccess = granted.calendars
        remindersAccess = granted.reminders
        await refresh()
    }

    // MARK: Weather

    func refreshWeather() async {
        if let seedDate {
            weather = SampleHousehold.weather(on: seedDate)
            weatherState = .ready
            return
        }
        guard let planner, let date else { return }
        guard let home = planner.rules.home else {
            weather = nil
            weatherState = .needsHome
            return
        }
        if weather == nil { weatherState = .loading }
        do {
            let result = try await WeatherLoader.load(home, date: date, clock: planner.clock)
            weather = result.snapshot
            weatherLegalPage = result.legalPage
            weatherState = .ready
            weatherFetchedAt = Date()
        } catch {
            weatherState = .unavailable(error.localizedDescription)
        }
    }

    /// Sets the rules' home to the phone's location (rounded), for the forecast.
    /// Returns what went wrong, if anything.
    func useCurrentLocationForHome() async -> String? {
        do {
            let location = try await LocationFinder.current()
            guard var rules else { return "The rules aren't loaded." }
            rules.home = .rounded(latitude: location.latitude, longitude: location.longitude, label: "Home")
            let issues = save(rules)
            return issues.isEmpty ? nil : issues.map(\.message).joined(separator: "\n")
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Brief and needs

    func briefText() -> String? {
        guard let planner, let plan else { return nil }
        return BriefComposer(planner: planner).brief(plan, now: now, weather: weather, doneNeeds: doneNeeds)
    }

    func toggleNeed(_ key: String) {
        guard let date else { return }
        if doneNeeds.contains(key) {
            doneNeeds.remove(key)
        } else {
            doneNeeds.insert(key)
        }
        if !isSeeded { NeedsLog.save(doneNeeds, on: date) }
    }

    // MARK: Editing

    /// Validates and saves edited rules, then replans. Returns the problems
    /// that stopped the save (nothing is saved then).
    @discardableResult
    func save(_ rules: HouseholdRules) -> [RulesIssue] {
        do {
            try store.save(rules)
        } catch {
            return error.issues
        }
        do {
            try use(rules, warnings: RulesValidator.validate(rules))
        } catch {
            return [RulesIssue(.error, "timeZone", String(describing: error))]
        }
        if let planner, let date, let lastInput {
            plan = planner.plan(for: date, input: lastInput)
        }
        Task { await refresh() }
        return []
    }

    /// A saved copy of the person's photo; the file name for `Person.photo`.
    func savePhoto(_ jpeg: Data, for id: PersonID) -> String? {
        try? store.savePhoto(jpeg, for: id)
    }

    func photoURL(_ name: String?) -> URL? {
        name.map { store.photoURL(named: $0) }
    }

    /// The next two weeks of events, for the rule editor's preview.
    func upcomingEvents() async -> [SourceEvent] {
        if isSeeded { return SampleHousehold.events(from: SampleHousehold.tuesday, days: 14) }
        guard let planner, let date else { return [] }
        return await source.events(from: date, days: 14, clock: planner.clock)
    }

    /// The rules file, written where the share sheet can pick it up.
    func exportURL() -> URL? {
        guard let data = try? store.exportData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("household.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Replaces the rules with a file from Files, if it loads cleanly.
    func importRules(from url: URL) -> [RulesIssue] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            return [RulesIssue(.error, "", "Couldn't read \(url.lastPathComponent).")]
        }
        return importRules(data)
    }

    /// Takes the household.json that shipped with this build.
    func importBundledRules() -> [RulesIssue] {
        guard let bundled else { return [RulesIssue(.error, "", "No bundled rules.")] }
        return importRules(bundled)
    }

    private func importRules(_ data: Data) -> [RulesIssue] {
        do {
            let loaded = try store.importRules(data, bundled: bundled)
            try use(loaded.rules, warnings: loaded.warnings)
        } catch let error as RulesError {
            return error.issues
        } catch {
            return [RulesIssue(.error, "", String(describing: error))]
        }
        bundledUpdateAvailable = false
        recoveredFrom = nil
        Task { await refresh() }
        return []
    }

    // MARK: Seeded device

    private static func sampleCalendars(on date: LocalDate) -> [DeviceCalendar] {
        let onDevice = SampleHousehold.calendarsOnDevice(on: date)
        let all = [
            DeviceCalendar(title: "Family", colorHex: "#6AD07A", account: "iCloud", isBirthdays: false),
            DeviceCalendar(title: "Sam", colorHex: "#5E9EFF", account: "iCloud", isBirthdays: false),
            DeviceCalendar(title: "Kate", colorHex: "#C58CFF", account: "iCloud", isBirthdays: false),
            DeviceCalendar(title: "US Holidays", colorHex: "#8E8E93", account: "Subscribed", isBirthdays: false),
        ]
        return all.filter { onDevice.contains($0.title) }
            + [DeviceCalendar(title: "Birthdays", colorHex: "#FF7AB6", account: "Other", isBirthdays: true)]
    }
}

/// Which of a day's needs are checked off, kept for that day only.
enum NeedsLog {
    private static let key = "needs.done"

    static func done(on date: LocalDate, persisted: Bool) -> Set<String> {
        guard persisted, let saved = UserDefaults.standard.dictionary(forKey: key),
              saved["date"] as? String == date.iso, let keys = saved["keys"] as? [String] else { return [] }
        return Set(keys)
    }

    static func save(_ keys: Set<String>, on date: LocalDate) {
        UserDefaults.standard.set(["date": date.iso, "keys": keys.sorted()], forKey: key)
    }
}
