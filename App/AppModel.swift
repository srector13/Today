import Foundation
import Observation
import TodayCore
import TodaySources

/// The app's state: the household rules from the shared store, each day's
/// plan from EventKit (any day you swipe to), the weather, manual picks, and
/// which needs are checked off.
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

    /// How far a manual pick reaches.
    enum PickScope: Hashable {
        case thisEvent
        case everyRepeat
        /// A rule for events with this exact title, at the top of the list.
        case everyTitled
    }

    /// One day's data, kept while the app runs.
    struct Day {
        var input: DayInput
        var plan: DayPlan
        var weather: WeatherSnapshot?
        var weatherState: WeatherState = .idle
        var weatherFetchedAt: Date?
    }

    /// Days you can swipe to, around today.
    static let pastDays = 30
    static let futureDays = 60
    /// WeatherKit forecasts this many days ahead (today included).
    static let forecastDays = 10

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
    private(set) var now: Date
    private(set) var days: [LocalDate: Day] = [:]
    private(set) var manual = ManualAssignments()
    private(set) var weatherLegalPage: URL?
    private(set) var deviceCalendars: [DeviceCalendar] = []
    private(set) var deviceReminderLists: [String] = []
    private(set) var doneNeeds: [LocalDate: Set<String>] = [:]
    /// The day on screen.
    var selectedDate: LocalDate

    @ObservationIgnored let store: HouseholdStore
    @ObservationIgnored private let source = EventKitSource()
    @ObservationIgnored private var bundled: Data?

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
            selectedDate = seed
        } else {
            store = HouseholdStore(directory: AppRules.storeDirectory)
            calendarAccess = EventKitSource.calendarAccess
            remindersAccess = EventKitSource.remindersAccess
            let start = AppLaunch.pinnedNow ?? Date()
            now = start
            selectedDate = HouseholdClock.chicago.localDate(of: start)
        }
    }

    var clock: HouseholdClock { planner?.clock ?? .chicago }

    /// Today: the seeded day, or the date in the household's zone.
    var today: LocalDate {
        seedDate ?? clock.localDate(of: now)
    }

    /// The days the Today screen pages through.
    var pageDates: [LocalDate] {
        (-Self.pastDays...Self.futureDays).map { today.adding(days: $0) }
    }

    func plan(on date: LocalDate) -> DayPlan? { days[date]?.plan }
    func weather(on date: LocalDate) -> WeatherSnapshot? { days[date]?.weather }
    func weatherState(on date: LocalDate) -> WeatherState { days[date]?.weatherState ?? .idle }
    func doneNeeds(on date: LocalDate) -> Set<String> { doneNeeds[date] ?? [] }

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
        manual = store.loadAssignments()
        manual.prune(before: today.adding(days: -Self.pastDays))
        if !isSeeded {
            selectedDate = today
            doneNeeds = NeedsLog.load()
        }
        await refresh()
    }

    private func use(_ rules: HouseholdRules, warnings: [RulesIssue]) throws {
        planner = try DayPlanner(rules: rules)
        self.warnings = warnings.filter { $0.severity == .warning }
    }

    /// Re-reads the device: calendar access, its calendars, and every day
    /// already shown (today and the day on screen at least).
    func refresh() async {
        guard planner != nil else { return }
        if isSeeded {
            deviceCalendars = Self.sampleCalendars(on: today)
            deviceReminderLists = ["Groceries", "Kids"]
        } else {
            now = AppLaunch.pinnedNow ?? Date()
            calendarAccess = EventKitSource.calendarAccess
            remindersAccess = EventKitSource.remindersAccess
            deviceCalendars = await source.deviceCalendars()
            deviceReminderLists = await source.reminderListTitles()
        }
        let shown = Set(days.keys).union([today, selectedDate])
        for date in shown.sorted() {
            await loadDay(date, force: true)
        }
    }

    /// Reads and plans `date` if it isn't loaded yet (or `force`).
    func loadDay(_ date: LocalDate, force: Bool = false) async {
        guard let planner, force || days[date] == nil else { return }
        var input: DayInput
        if isSeeded {
            input = SampleHousehold.input(on: date)
        } else {
            input = await source.input(for: date, rules: planner.rules, clock: planner.clock)
        }
        input.manual = manual
        // The rules may have been saved while EventKit was reading.
        let plan = (self.planner ?? planner).plan(for: date, input: input)
        if var day = days[date] {
            day.input = input
            day.plan = plan
            days[date] = day
        } else {
            days[date] = Day(input: input, plan: plan)
        }
        await loadWeather(on: date)
    }

    /// Replans every loaded day from the data already read: after an edit
    /// or a manual pick, so the screen changes at once.
    private func replanLoadedDays() {
        guard let planner else { return }
        for (date, var day) in days {
            day.input.manual = manual
            day.plan = planner.plan(for: date, input: day.input)
            days[date] = day
        }
    }

    /// Moves the clock on; a new day reloads.
    func tick() {
        guard !isSeeded, AppLaunch.pinnedNow == nil, planner != nil else { return }
        let before = today
        now = Date()
        if today != before {
            Task { await refresh() }
        } else if let fetched = days[today]?.weatherFetchedAt, now.timeIntervalSince(fetched) > 30 * 60 {
            Task { await loadWeather(on: today, force: true) }
        }
    }

    func connectCalendars() async {
        let granted = await source.requestAccess()
        calendarAccess = granted.calendars
        remindersAccess = granted.reminders
        await refresh()
    }

    // MARK: Weather

    func loadWeather(on date: LocalDate, force: Bool = false) async {
        guard days[date] != nil, let planner else { return }
        if isSeeded {
            days[date]?.weather = SampleHousehold.weather(on: date)
            days[date]?.weatherState = .ready
            return
        }
        guard let home = planner.rules.home else {
            days[date]?.weather = nil
            days[date]?.weatherState = .needsHome
            return
        }
        let ahead = date.dayNumber - today.dayNumber
        guard (0..<Self.forecastDays).contains(ahead) else {
            days[date]?.weather = nil
            days[date]?.weatherState = .unavailable("Forecasts reach \(Self.forecastDays) days ahead.")
            return
        }
        if !force, let fetched = days[date]?.weatherFetchedAt, now.timeIntervalSince(fetched) < 30 * 60 { return }
        if days[date]?.weather == nil { days[date]?.weatherState = .loading }
        do {
            let result = try await WeatherLoader.load(home, date: date, clock: planner.clock, isToday: ahead == 0)
            days[date]?.weather = result.snapshot
            days[date]?.weatherState = .ready
            days[date]?.weatherFetchedAt = Date()
            weatherLegalPage = result.legalPage
        } catch {
            days[date]?.weatherState = .unavailable(error.localizedDescription)
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

    func briefText(on date: LocalDate) -> String? {
        guard let planner, let plan = plan(on: date) else { return nil }
        return BriefComposer(planner: planner).brief(plan, now: now, weather: weather(on: date),
                                                     doneNeeds: doneNeeds(on: date))
    }

    func toggleNeed(_ key: String, on date: LocalDate) {
        var done = doneNeeds(on: date)
        if done.contains(key) {
            done.remove(key)
        } else {
            done.insert(key)
        }
        doneNeeds[date] = done
        if !isSeeded { NeedsLog.save(doneNeeds, keepingSince: today.adding(days: -14)) }
    }

    // MARK: Manual picks

    /// The pick that decides `item`, if one does.
    func pick(for item: TimelineItem) -> ManualAssignment? {
        guard let event = item.event else { return nil }
        return manual.entry(for: event, on: clock.localDate(of: event.start))
    }

    /// Assigns `item`'s event to `people`: just this occurrence, every
    /// repeat (both kept as manual picks), or every event with its title (a
    /// rule). Returns the problems that stopped it.
    @discardableResult
    func assign(_ item: TimelineItem, to people: [PersonID], scope: PickScope) -> [RulesIssue] {
        guard let event = item.event else {
            return [RulesIssue(.error, "", "Only calendar events can be assigned.")]
        }
        let day = clock.localDate(of: event.start)
        switch scope {
        case .everyTitled:
            guard var rules else { return [] }
            rules.moveEvents(titled: event.title, to: people)
            // A pick would beat the new rule for this event; the rule decides now.
            manual.clear(for: event, on: day)
            savePicks()
            return save(rules)
        case .thisEvent:
            manual.set(people, for: event, on: day)
        case .everyRepeat:
            manual.set(people, for: event, on: nil)
        }
        savePicks()
        replanLoadedDays()
        return []
    }

    /// Forgets the pick for `item` (this occurrence and its series).
    func clearPick(for item: TimelineItem) {
        guard let event = item.event else { return }
        manual.clear(for: event, on: clock.localDate(of: event.start))
        savePicks()
        replanLoadedDays()
    }

    /// Drops someone removed from the household from every pick.
    func forgetPicks(of person: PersonID) {
        manual.remove(person)
        savePicks()
        replanLoadedDays()
    }

    private func savePicks() {
        try? store.saveAssignments(manual)
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
        replanLoadedDays()
        // Reminders lists, calendars and home may have changed: read again.
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
        guard let planner else { return [] }
        return await source.events(from: today, days: 14, clock: planner.clock)
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
        replanLoadedDays()
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
            DeviceCalendar(title: "Us", colorHex: "#FF9F45", account: "iCloud", isBirthdays: false),
            DeviceCalendar(title: "US Holidays", colorHex: "#8E8E93", account: "Subscribed", isBirthdays: false),
        ]
        return all.filter { onDevice.contains($0.title) }
            + [DeviceCalendar(title: "Birthdays", colorHex: "#FF7AB6", account: "Other", isBirthdays: true)]
    }
}

/// Which needs are checked off, by day, for the last two weeks.
enum NeedsLog {
    private static let key = "needs.done.byDay"

    static func load() -> [LocalDate: Set<String>] {
        guard let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] else { return [:] }
        var result: [LocalDate: Set<String>] = [:]
        for (iso, keys) in saved {
            if let date = LocalDate(iso: iso) { result[date] = Set(keys) }
        }
        return result
    }

    static func save(_ done: [LocalDate: Set<String>], keepingSince oldest: LocalDate) {
        var saved: [String: [String]] = [:]
        for (date, keys) in done where date >= oldest && !keys.isEmpty {
            saved[date.iso] = keys.sorted()
        }
        UserDefaults.standard.set(saved, forKey: key)
    }
}
