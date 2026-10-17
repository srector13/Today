import Foundation

public typealias PersonID = String

/// Everything the app knows about the household that isn't on a calendar,
/// decoded from `Rules/household.json`. The JSON Schema next to that file
/// documents each key; `RulesValidator` checks what a schema can't (every id
/// a rule names exists, times run forward, the loop collects every kid in
/// care).
public struct HouseholdRules: Sendable, Equatable {
    public var schemaVersion: Int
    /// The zone every date and time in the file is written in.
    public var timeZone: String
    /// Open questions. Each shows as a "rules incomplete" warning until removed.
    public var todo: [String]
    /// The hours the lanes draw.
    public var dayWindow: DayWindow
    /// Where the weather card's forecast is for; `nil` until set.
    public var home: HomeLocation?
    public var people: [Person]
    public var calendars: [CalendarRule]
    /// Recurring blocks that are on no calendar: work, school, preschool.
    public var blocks: [BlockRule]
    /// Terms, days off and early releases, by id; a school block names one.
    public var schoolCalendars: [String: SchoolCalendar]
    public var care: [CareRule]
    public var pickupLoop: PickupLoopRule?
    public var needs: [NeedRule]
    /// Reminders lists whose open items show as kids' needs.
    public var reminderLists: [ReminderListRule]
    /// Mail-style rules, in order; they run before the built-in attribution.
    public var assignmentRules: [AssignmentRule]
    public var birthdays: BirthdaySettings
    public var checkIns: [CheckInRule]
    /// How much each kind of item matters, e.g. for "next up" on the Lock
    /// Screen. Kinds the file leaves out keep `Importance.defaults`.
    public var importance: [ItemKind: Importance]

    /// The version this app writes. Version 1 files (M1: no colors, photos
    /// or assignment rules) still load.
    public static let currentSchemaVersion = 2
    public static let supportedSchemaVersions = 1...2

    public func person(_ id: PersonID) -> Person? {
        people.first { $0.id == id }
    }

    public func importance(of kind: ItemKind) -> Importance {
        importance[kind] ?? Importance.defaults[kind] ?? .normal
    }

    /// The person's chosen color, or a palette color by their position.
    public func laneColor(of id: PersonID) -> LaneColor {
        guard let index = people.firstIndex(where: { $0.id == id }) else { return LaneColor.palette[0] }
        return people[index].color ?? LaneColor.palette[index % LaneColor.palette.count]
    }
}

extension HouseholdRules: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, timeZone, todo, dayWindow, home, people, calendars, blocks
        case schoolCalendars, care, pickupLoop, needs, reminderLists, assignmentRules
        case birthdays, checkIns, importance
    }

    public init(from decoder: any Decoder) throws {
        // "$schema" points editors at household.schema.json; the app ignores it.
        try decoder.rejectUnknownKeys(CodingKeys.self, also: ["$schema"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        timeZone = try c.decode(String.self, forKey: .timeZone)
        todo = try c.decodeIfPresent([String].self, forKey: .todo) ?? []
        dayWindow = try c.decodeIfPresent(DayWindow.self, forKey: .dayWindow) ?? .standard
        home = try c.decodeIfPresent(HomeLocation.self, forKey: .home)
        people = try c.decode([Person].self, forKey: .people)
        calendars = try c.decodeIfPresent([CalendarRule].self, forKey: .calendars) ?? []
        blocks = try c.decodeIfPresent([BlockRule].self, forKey: .blocks) ?? []
        schoolCalendars = try c.decodeIfPresent([String: SchoolCalendar].self, forKey: .schoolCalendars) ?? [:]
        care = try c.decodeIfPresent([CareRule].self, forKey: .care) ?? []
        pickupLoop = try c.decodeIfPresent(PickupLoopRule.self, forKey: .pickupLoop)
        needs = try c.decodeIfPresent([NeedRule].self, forKey: .needs) ?? []
        reminderLists = try c.decodeIfPresent([ReminderListRule].self, forKey: .reminderLists) ?? []
        assignmentRules = try c.decodeIfPresent([AssignmentRule].self, forKey: .assignmentRules) ?? []
        birthdays = try c.decodeIfPresent(BirthdaySettings.self, forKey: .birthdays) ?? BirthdaySettings()
        checkIns = try c.decodeIfPresent([CheckInRule].self, forKey: .checkIns) ?? CheckInRule.defaults
        let rawImportance = try c.decodeIfPresent([String: Importance].self, forKey: .importance) ?? [:]
        var importance: [ItemKind: Importance] = [:]
        for (key, value) in rawImportance {
            guard let kind = ItemKind(rawValue: key) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath + [CodingKeys.importance, AnyCodingKey(stringValue: key)],
                    debugDescription: "\"\(key)\" is not an item kind. Use one of: \(ItemKind.allCases.map(\.rawValue).joined(separator: ", "))."
                ))
            }
            importance[kind] = value
        }
        self.importance = importance
    }
}

// MARK: - People

public enum PersonGroup: String, Codable, Sendable, CaseIterable {
    case parents, kids, grandparents

    /// The section heading over the group's lanes.
    public var title: String {
        switch self {
        case .parents: "Us"
        case .kids: "Kids"
        case .grandparents: "Grandparents"
        }
    }
}

public struct Person: Sendable, Equatable, Identifiable {
    public var id: PersonID
    /// The name shown on the lane, and matched in calendar titles.
    public var name: String
    public var group: PersonGroup
    /// Other words that mean this person in a calendar title ("Papa", "Mom").
    public var aliases: [String]
    /// People with the same lane label share one row ("Twins").
    public var lane: String?
    public var birthDate: LocalDate?
    /// Their lane's color; `nil` picks one from the palette by position.
    public var color: LaneColor?
    /// A file name in the household's Photos folder; `nil` shows a monogram.
    public var photo: String?

    public init(
        id: PersonID, name: String, group: PersonGroup, aliases: [String] = [], lane: String? = nil,
        birthDate: LocalDate? = nil, color: LaneColor? = nil, photo: String? = nil
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.aliases = aliases
        self.lane = lane
        self.birthDate = birthDate
        self.color = color
        self.photo = photo
    }

    public var laneLabel: String { lane ?? name }

    /// The letter on a monogram avatar.
    public var initials: String {
        let words = laneLabel.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return String(words.first?.first.map(String.init) ?? "?").uppercased()
    }
}

extension Person: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, group, aliases, lane, birthDate, color, photo
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(PersonID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        group = try c.decode(PersonGroup.self, forKey: .group)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        lane = try c.decodeIfPresent(String.self, forKey: .lane)
        birthDate = try c.decodeIfPresent(LocalDate.self, forKey: .birthDate)
        color = try c.decodeIfPresent(LaneColor.self, forKey: .color)
        photo = try c.decodeIfPresent(String.self, forKey: .photo)
    }
}

// MARK: - Calendars

public enum CalendarRole: String, Codable, Sendable {
    /// A family calendar: an event belongs to `defaultOwner` unless people
    /// are named in its title, and then it belongs to them instead.
    case shared
    /// One person's calendar: events belong to `owner`, plus anyone named.
    case personal
}

public struct CalendarRule: Sendable, Equatable {
    /// The calendar's name as iOS shows it.
    public var title: String
    public var role: CalendarRole
    public var owner: PersonID?
    public var defaultOwner: PersonID?

    public init(title: String, role: CalendarRole, owner: PersonID? = nil, defaultOwner: PersonID? = nil) {
        self.title = title
        self.role = role
        self.owner = owner
        self.defaultOwner = defaultOwner
    }
}

extension CalendarRule: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case title, role, owner, defaultOwner
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        role = try c.decode(CalendarRole.self, forKey: .role)
        owner = try c.decodeIfPresent(PersonID.self, forKey: .owner)
        defaultOwner = try c.decodeIfPresent(PersonID.self, forKey: .defaultOwner)
    }
}

// MARK: - Blocks

public enum BlockKind: String, Codable, Sendable {
    case work, school, activity

    var itemKind: ItemKind {
        switch self {
        case .work: .work
        case .school: .school
        case .activity: .activity
        }
    }
}

/// A recurring stretch of someone's day that no calendar holds.
public struct BlockRule: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var kind: BlockKind
    public var who: [PersonID]
    public var days: DaySet
    public var start: LocalTime
    public var end: LocalTime
    /// For school: the calendar whose terms and days off apply.
    public var schoolCalendar: String?

    public init(
        id: String, title: String, kind: BlockKind, who: [PersonID], days: DaySet,
        start: LocalTime, end: LocalTime, schoolCalendar: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.who = who
        self.days = days
        self.start = start
        self.end = end
        self.schoolCalendar = schoolCalendar
    }
}

extension BlockRule: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, kind, who, days, start, end, schoolCalendar
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        kind = try c.decode(BlockKind.self, forKey: .kind)
        who = try c.decode([PersonID].self, forKey: .who)
        days = try c.decode(DaySet.self, forKey: .days)
        start = try c.decode(LocalTime.self, forKey: .start)
        end = try c.decode(LocalTime.self, forKey: .end)
        schoolCalendar = try c.decodeIfPresent(String.self, forKey: .schoolCalendar)
    }
}

// MARK: - School calendars

public struct SchoolCalendar: Sendable, Equatable {
    /// The term; outside it the school block doesn't run (summer).
    public var firstDay: LocalDate?
    public var lastDay: LocalDate?
    public var noSchool: [NoSchoolDays]
    public var earlyRelease: [EarlyRelease]

    public init(
        firstDay: LocalDate? = nil, lastDay: LocalDate? = nil,
        noSchool: [NoSchoolDays] = [], earlyRelease: [EarlyRelease] = []
    ) {
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.noSchool = noSchool
        self.earlyRelease = earlyRelease
    }

    public func noSchool(on date: LocalDate) -> NoSchoolDays? {
        noSchool.first { $0.from <= date && date <= $0.to }
    }

    public func earlyRelease(on date: LocalDate) -> EarlyRelease? {
        earlyRelease.first { $0.date == date }
    }

    public func isInTerm(_ date: LocalDate) -> Bool {
        if let firstDay, date < firstDay { return false }
        if let lastDay, date > lastDay { return false }
        return true
    }
}

extension SchoolCalendar: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case firstDay, lastDay, noSchool, earlyRelease
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstDay = try c.decodeIfPresent(LocalDate.self, forKey: .firstDay)
        lastDay = try c.decodeIfPresent(LocalDate.self, forKey: .lastDay)
        noSchool = try c.decodeIfPresent([NoSchoolDays].self, forKey: .noSchool) ?? []
        earlyRelease = try c.decodeIfPresent([EarlyRelease].self, forKey: .earlyRelease) ?? []
    }
}

/// One day off or a break. In the file, either a date string
/// (`"2026-11-26"`), `{"date": ..., "label": ...}`, or
/// `{"from": ..., "to": ..., "label": ...}` for a run of days.
public struct NoSchoolDays: Sendable, Equatable {
    public var from: LocalDate
    public var to: LocalDate
    public var label: String?

    public init(from: LocalDate, to: LocalDate, label: String? = nil) {
        self.from = from
        self.to = to
        self.label = label
    }
}

extension NoSchoolDays: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case date, from, to, label
    }

    public init(from decoder: any Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self) {
            guard let date = LocalDate(iso: raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "\"\(raw)\" is not a date. Write dates as YYYY-MM-DD, e.g. \"2026-11-26\"."
                ))
            }
            self.init(from: date, to: date, label: nil)
            return
        }
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let label = try c.decodeIfPresent(String.self, forKey: .label)
        if let date = try c.decodeIfPresent(LocalDate.self, forKey: .date) {
            self.init(from: date, to: date, label: label)
        } else {
            self.init(
                from: try c.decode(LocalDate.self, forKey: .from),
                to: try c.decode(LocalDate.self, forKey: .to),
                label: label
            )
        }
    }
}

public struct EarlyRelease: Sendable, Equatable {
    public var date: LocalDate
    /// When school lets out instead of the block's usual end.
    public var end: LocalTime
    public var label: String?

    public init(date: LocalDate, end: LocalTime, label: String? = nil) {
        self.date = date
        self.end = end
        self.label = label
    }
}

extension EarlyRelease: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case date, end, label
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(LocalDate.self, forKey: .date)
        end = try c.decode(LocalTime.self, forKey: .end)
        label = try c.decodeIfPresent(String.self, forKey: .label)
    }
}

// MARK: - Care

/// When a care arrangement hands the kids back.
public enum CareEnd: Sendable, Equatable {
    /// At the loop stop that collects each kid.
    case pickupLoop
    case time(LocalTime)
}

extension CareEnd: Decodable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "pickupLoop" {
            self = .pickupLoop
        } else if let time = LocalTime(raw) {
            self = .time(time)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "\"\(raw)\" is not an end. Use \"pickupLoop\" or a time like \"15:45\"."
            ))
        }
    }
}

/// Someone watching kids on a schedule, e.g. the in-laws on weekdays. A kid
/// at school or preschool during the window is with the school, not the
/// caregivers, for those hours.
public struct CareRule: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String?
    public var caregivers: [PersonID]
    public var kids: [PersonID]
    public var days: DaySet
    public var from: LocalTime
    public var until: CareEnd

    public init(
        id: String, title: String? = nil, caregivers: [PersonID], kids: [PersonID],
        days: DaySet, from: LocalTime, until: CareEnd
    ) {
        self.id = id
        self.title = title
        self.caregivers = caregivers
        self.kids = kids
        self.days = days
        self.from = from
        self.until = until
    }
}

extension CareRule: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, caregivers, kids, days, from, until
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        caregivers = try c.decode([PersonID].self, forKey: .caregivers)
        kids = try c.decode([PersonID].self, forKey: .kids)
        days = try c.decode(DaySet.self, forKey: .days)
        from = try c.decode(LocalTime.self, forKey: .from)
        until = try c.decode(CareEnd.self, forKey: .until)
    }
}

// MARK: - Pickup loop

/// When the loop starts.
public enum LoopStart: Sendable, Equatable {
    /// When a block (school) lets out that day, early releases included.
    case blockEnd(String)
    case time(LocalTime)
}

extension LoopStart: Decodable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let time = LocalTime(raw) {
            self = .time(time)
        } else if raw.hasSuffix(".end"), raw.count > 4 {
            self = .blockEnd(String(raw.dropLast(4)))
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "\"\(raw)\" is not a start. Use a block's end like \"school.end\" or a time like \"15:30\"."
            ))
        }
    }
}

/// The afternoon run: one driver, stops in order, everyone home. Drive times
/// are out of scope, so stops are spaced by a fixed estimate.
public struct PickupLoopRule: Sendable, Equatable {
    public var title: String
    public var driver: PersonID
    public var days: DaySet
    public var startsAt: LoopStart
    /// The start on days the `startsAt` block doesn't run (no school).
    public var fallbackStart: LocalTime?
    public var minutesBetweenStops: Int
    public var minutesToHome: Int
    public var stops: [LoopStop]

    public init(
        title: String = "Pickup loop", driver: PersonID, days: DaySet, startsAt: LoopStart,
        fallbackStart: LocalTime? = nil, minutesBetweenStops: Int = 15, minutesToHome: Int = 15,
        stops: [LoopStop]
    ) {
        self.title = title
        self.driver = driver
        self.days = days
        self.startsAt = startsAt
        self.fallbackStart = fallbackStart
        self.minutesBetweenStops = minutesBetweenStops
        self.minutesToHome = minutesToHome
        self.stops = stops
    }
}

extension PickupLoopRule: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case title, driver, days, startsAt, fallbackStart, minutesBetweenStops, minutesToHome, stops
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Pickup loop"
        driver = try c.decode(PersonID.self, forKey: .driver)
        days = try c.decode(DaySet.self, forKey: .days)
        startsAt = try c.decode(LoopStart.self, forKey: .startsAt)
        fallbackStart = try c.decodeIfPresent(LocalTime.self, forKey: .fallbackStart)
        minutesBetweenStops = try c.decodeIfPresent(Int.self, forKey: .minutesBetweenStops) ?? 15
        minutesToHome = try c.decodeIfPresent(Int.self, forKey: .minutesToHome) ?? 15
        stops = try c.decode([LoopStop].self, forKey: .stops)
    }
}

public struct LoopStop: Sendable, Equatable {
    public var place: String
    public var collect: [PersonID]
    /// The stop happens only on days this block runs (no school, no school stop).
    public var onlyWhen: String?

    public init(place: String, collect: [PersonID], onlyWhen: String? = nil) {
        self.place = place
        self.collect = collect
        self.onlyWhen = onlyWhen
    }
}

extension LoopStop: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case place, collect, onlyWhen
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        place = try c.decode(String.self, forKey: .place)
        collect = try c.decode([PersonID].self, forKey: .collect)
        onlyWhen = try c.decodeIfPresent(String.self, forKey: .onlyWhen)
    }
}

// MARK: - Needs

/// Things a kid needs on certain days: by weekday, on days a block runs, or both.
public struct NeedRule: Sendable, Equatable {
    public var who: [PersonID]
    public var items: [String]
    public var days: DaySet?
    public var onDaysOf: String?

    public init(who: [PersonID], items: [String], days: DaySet? = nil, onDaysOf: String? = nil) {
        self.who = who
        self.items = items
        self.days = days
        self.onDaysOf = onDaysOf
    }
}

extension NeedRule: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case who, items, days, onDaysOf
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        who = try c.decode([PersonID].self, forKey: .who)
        items = try c.decode([String].self, forKey: .items)
        days = try c.decodeIfPresent(DaySet.self, forKey: .days)
        onDaysOf = try c.decodeIfPresent(String.self, forKey: .onDaysOf)
    }
}

// MARK: - Reminders and birthdays

/// A Reminders list whose open items become kids' needs. A reminder belongs
/// to the people its title names ("Library book - Emma"), else `defaultOwner`.
public struct ReminderListRule: Sendable, Equatable {
    public var title: String
    public var defaultOwner: PersonID?

    public init(title: String, defaultOwner: PersonID? = nil) {
        self.title = title
        self.defaultOwner = defaultOwner
    }
}

extension ReminderListRule: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case title, defaultOwner
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        defaultOwner = try c.decodeIfPresent(PersonID.self, forKey: .defaultOwner)
    }
}

public struct BirthdaySettings: Sendable, Equatable {
    /// How far ahead the birthdays card looks.
    public var lookaheadDays: Int

    public init(lookaheadDays: Int = 30) {
        self.lookaheadDays = lookaheadDays
    }
}

extension BirthdaySettings: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case lookaheadDays
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lookaheadDays = try c.decodeIfPresent(Int.self, forKey: .lookaheadDays) ?? 30
    }
}

// MARK: - Check-ins

public enum CheckInKind: String, Codable, Sendable, CaseIterable {
    case morning, midday, afternoon
}

public struct CheckInRule: Sendable, Equatable {
    public var kind: CheckInKind
    public var at: LocalTime
    /// Breaks through Focus (for the pickup check-in during work).
    public var timeSensitive: Bool

    public init(kind: CheckInKind, at: LocalTime, timeSensitive: Bool = false) {
        self.kind = kind
        self.at = at
        self.timeSensitive = timeSensitive
    }

    public static let defaults = [
        CheckInRule(kind: .morning, at: LocalTime(hour: 6, minute: 30)!, timeSensitive: false),
        CheckInRule(kind: .midday, at: LocalTime(hour: 12, minute: 0)!, timeSensitive: false),
        CheckInRule(kind: .afternoon, at: LocalTime(hour: 15, minute: 15)!, timeSensitive: true),
    ]
}

extension CheckInRule: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, at, timeSensitive
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(CheckInKind.self, forKey: .kind)
        at = try c.decode(LocalTime.self, forKey: .at)
        timeSensitive = try c.decodeIfPresent(Bool.self, forKey: .timeSensitive) ?? false
    }
}

// MARK: - Home

/// Where the household lives, for the weather forecast. Nothing else uses it.
public struct HomeLocation: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    /// What the editor shows, e.g. "Home" or a town name.
    public var label: String?

    public init(latitude: Double, longitude: Double, label: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
    }

    /// Rounded to three decimals (about 100 m): plenty for a forecast, and
    /// the file doesn't pin the house.
    public static func rounded(latitude: Double, longitude: Double, label: String? = nil) -> HomeLocation {
        func round3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
        return HomeLocation(latitude: round3(latitude), longitude: round3(longitude), label: label)
    }
}

extension HomeLocation: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case latitude, longitude, label
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        label = try c.decodeIfPresent(String.self, forKey: .label)
    }
}

// MARK: - Window and importance

public struct DayWindow: Sendable, Equatable {
    public var start: LocalTime
    public var end: LocalTime

    public init(start: LocalTime, end: LocalTime) {
        self.start = start
        self.end = end
    }

    public static let standard = DayWindow(start: LocalTime(hour: 6, minute: 0)!, end: LocalTime(hour: 21, minute: 0)!)
}

extension DayWindow: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case start, end
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decode(LocalTime.self, forKey: .start)
        end = try c.decode(LocalTime.self, forKey: .end)
    }
}

public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case work, school, activity, care, pickupLoop, appointment
}

public enum Importance: String, Codable, Sendable, Comparable, CaseIterable {
    /// Context, never "next up": work hours, kids at the in-laws'.
    case background
    case low
    case normal
    case high

    public static let defaults: [ItemKind: Importance] = [
        .work: .background,
        .care: .background,
        .school: .low,
        .activity: .normal,
        .appointment: .normal,
        .pickupLoop: .high,
    ]

    private var rank: Int { Self.allCases.firstIndex(of: self)! }

    public static func < (lhs: Importance, rhs: Importance) -> Bool { lhs.rank < rhs.rank }
}
