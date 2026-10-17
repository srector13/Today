import Foundation

/// A block that runs on a given day, with that day's times.
public struct BlockOccurrence: Sendable, Equatable {
    public let block: BlockRule
    public let start: LocalTime
    /// The block's end, or the early-release time.
    public let end: LocalTime
    public let earlyRelease: EarlyRelease?
}

/// Turns the household rules plus a day's calendar events into a `DayPlan`.
///
/// The rules add what no calendar holds: work hours, school (minus days off,
/// with early releases), the in-laws' care, and the pickup loop. Events land
/// on lanes by their calendar's owner, or by the people their title names.
public struct DayPlanner: Sendable {
    public let rules: HouseholdRules
    public let clock: HouseholdClock
    let attributor: TitleAttributor
    let ruleEngine: RuleEngine

    public init(rules: HouseholdRules) throws {
        self.rules = rules
        clock = try HouseholdClock(timeZoneIdentifier: rules.timeZone)
        attributor = TitleAttributor(people: rules.people)
        ruleEngine = RuleEngine(rules: rules.assignmentRules)
    }

    /// `input.calendarsOnDevice` has no default on purpose: a lane whose
    /// calendar is missing must show "no data", never a free day, so every
    /// caller has to say what it could see.
    public func plan(for date: LocalDate, input: DayInput) -> DayPlan {
        var builder = PlanBuilder(planner: self, date: date)
        return builder.build(input)
    }

    public func plan(for date: LocalDate, events: [SourceEvent], calendarsOnDevice: Set<String>) -> DayPlan {
        plan(for: date, input: DayInput(events: events, calendarsOnDevice: calendarsOnDevice))
    }

    /// The block's times on `date`, or `nil` when it doesn't run: wrong
    /// weekday, outside its school's term, or a day off.
    public func occurrence(of block: BlockRule, on date: LocalDate) -> BlockOccurrence? {
        guard block.days.contains(date.weekday) else { return nil }
        guard let calendarID = block.schoolCalendar, let calendar = rules.schoolCalendars[calendarID] else {
            return BlockOccurrence(block: block, start: block.start, end: block.end, earlyRelease: nil)
        }
        guard calendar.isInTerm(date), calendar.noSchool(on: date) == nil else { return nil }
        if let early = calendar.earlyRelease(on: date), early.end < block.end, early.end > block.start {
            return BlockOccurrence(block: block, start: block.start, end: early.end, earlyRelease: early)
        }
        return BlockOccurrence(block: block, start: block.start, end: block.end, earlyRelease: nil)
    }

    /// Whether the school block `blockID` is in session on `date`.
    public func isSchoolDay(_ blockID: String, on date: LocalDate) -> Bool {
        guard let block = rules.blocks.first(where: { $0.id == blockID }) else { return false }
        return occurrence(of: block, on: date) != nil
    }

    /// Who an event belongs to. On a shared calendar a name in the title wins
    /// over the default owner; on a personal calendar named people join the owner.
    public func owners(of title: String, on calendar: CalendarRule) -> (people: [PersonID], attribution: Attribution) {
        let named = attributor.people(namedIn: title)
        switch calendar.role {
        case .shared:
            if named.isEmpty, let owner = calendar.defaultOwner {
                return ([owner], .defaultOwner)
            }
            return (named, .namedInTitle)
        case .personal:
            guard let owner = calendar.owner else { return (named, .namedInTitle) }
            return ([owner] + named.filter { $0 != owner }, .calendarOwner)
        }
    }

    /// "Nora & Twins": names in rules order, a full lane by its label.
    public func names(_ ids: [PersonID]) -> String {
        var labels: [String] = []
        var remaining = Set(ids)
        for person in rules.people where remaining.contains(person.id) {
            if let lane = person.lane {
                let mates = rules.people.filter { $0.lane == lane }.map(\.id)
                if mates.count > 1, Set(mates).isSubset(of: Set(ids)) {
                    if !labels.contains(lane) { labels.append(lane) }
                    remaining.subtract(mates)
                    continue
                }
            }
            labels.append(person.name)
            remaining.remove(person.id)
        }
        labels += remaining.sorted()
        return Self.list(labels)
    }

    /// The next `month`/`day` on or after `date`. A Feb 29 birthday falls on
    /// Feb 28 in other years.
    static func nextBirthday(month: Int, day: Int, onOrAfter date: LocalDate) -> LocalDate? {
        func occurrence(in year: Int) -> LocalDate? {
            LocalDate(year: year, month: month, day: day)
                ?? (month == 2 && day == 29 ? LocalDate(year: year, month: 2, day: 28) : nil)
        }
        guard let thisYear = occurrence(in: date.year) else { return nil }
        return thisYear >= date ? thisYear : occurrence(in: date.year + 1)
    }

    static func list(_ words: [String]) -> String {
        switch words.count {
        case 0: ""
        case 1: words[0]
        default: words.dropLast().joined(separator: ", ") + " & " + words.last!
        }
    }
}

// MARK: - Building one day

private struct PlanBuilder {
    let planner: DayPlanner
    let date: LocalDate
    var rules: HouseholdRules { planner.rules }
    var clock: HouseholdClock { planner.clock }

    var items: [TimelineItem] = []
    var hidden: [TimelineItem] = []
    var alerts: [PlanAlert] = []

    init(planner: DayPlanner, date: LocalDate) {
        self.planner = planner
        self.date = date
    }

    mutating func build(_ input: DayInput) -> DayPlan {
        let weekday = date.weekday
        var occurrences: [String: BlockOccurrence] = [:]
        for block in rules.blocks {
            if let occurrence = planner.occurrence(of: block, on: date) {
                occurrences[block.id] = occurrence
            }
        }

        let onDevice = Set(input.calendarsOnDevice.map { $0.lowercased() })
        let missing = rules.calendars.filter { !onDevice.contains($0.title.lowercased()) }
        let noData = noDataReasons(missing)

        addBlockItems(occurrences)
        let schools = schoolStatuses(occurrences)
        let loop = planLoop(occurrences)
        let careWindows = addCare(occurrences, loop: loop)
        let unlisted = addEvents(input.events.filter { onDevice.contains($0.calendarTitle.lowercased()) })
        alertForSchools(schools, weekday: weekday)
        alertForConflicts(careWindows: careWindows, loop: loop)

        items.sort(by: Self.order)
        hidden.sort(by: Self.order)
        return DayPlan(
            date: date,
            clock: clock,
            dayWindow: rules.dayWindow,
            schools: schools,
            pickupLoop: loop,
            items: items,
            laneGroups: laneGroups(noData: noData),
            alerts: alerts,
            needs: needs(occurrences, reminders: input.reminders),
            birthdays: birthdays(input.birthdays),
            hiddenItems: hidden,
            missingCalendars: missing.map(\.title),
            unlistedCalendars: unlisted
        )
    }

    /// The people whose day we can't see, and why. A personal calendar that
    /// isn't on the device blanks its owner. A missing shared calendar blanks
    /// everyone, because a name in a title can put its events on any lane,
    /// and it alerts.
    private mutating func noDataReasons(_ missing: [CalendarRule]) -> [PersonID: String] {
        var reasons: [PersonID: String] = [:]
        for calendar in missing where calendar.role == .personal {
            if let owner = calendar.owner {
                reasons[owner] = "the \"\(calendar.title)\" calendar isn't on this device"
            }
        }
        for calendar in missing {
            switch calendar.role {
            case .personal:
                continue
            case .shared:
                for person in rules.people where reasons[person.id] == nil {
                    reasons[person.id] = "the \"\(calendar.title)\" calendar isn't on this device"
                }
                alerts.append(PlanAlert(
                    kind: .missingCalendar,
                    message: "The \(calendar.title) calendar isn't on this device, so its events are missing from every lane.",
                    people: calendar.defaultOwner.map { [$0] } ?? []
                ))
            }
        }
        return reasons
    }

    // MARK: Blocks

    private mutating func addBlockItems(_ occurrences: [String: BlockOccurrence]) {
        for block in rules.blocks {
            guard let occurrence = occurrences[block.id] else { continue }
            let kind = block.kind.itemKind
            items.append(TimelineItem(
                id: "block:\(block.id)",
                title: block.title,
                kind: kind,
                start: instant(occurrence.start),
                end: instant(occurrence.end),
                isAllDay: false,
                people: block.who,
                importance: rules.importance(of: kind),
                origin: .rule(block.id),
                detail: occurrence.earlyRelease.map { "Early release\($0.label.map { ": \($0)" } ?? "")" }
            ))
        }
    }

    private func schoolStatuses(_ occurrences: [String: BlockOccurrence]) -> [SchoolStatus] {
        rules.blocks.compactMap { block in
            guard block.kind == .school, block.days.contains(date.weekday) else { return nil }
            let state: SchoolStatus.State
            if let occurrence = occurrences[block.id] {
                state = .inSession(start: occurrence.start, end: occurrence.end, earlyRelease: occurrence.earlyRelease != nil)
            } else if let id = block.schoolCalendar, let calendar = rules.schoolCalendars[id], !calendar.isInTerm(date) {
                state = .outOfTerm
            } else {
                let label = block.schoolCalendar.flatMap { rules.schoolCalendars[$0]?.noSchool(on: date)?.label }
                state = .noSchool(label: label)
            }
            return SchoolStatus(blockID: block.id, title: block.title, people: block.who, state: state)
        }
    }

    // MARK: Pickup loop

    private mutating func planLoop(_ occurrences: [String: BlockOccurrence]) -> PickupLoopPlan? {
        guard let rule = rules.pickupLoop, rule.days.contains(date.weekday) else { return nil }
        let start: LocalTime
        var usedFallback = false
        switch rule.startsAt {
        case let .time(time):
            start = time
        case let .blockEnd(blockID):
            if let occurrence = occurrences[blockID] {
                start = occurrence.end
            } else if let fallback = rule.fallbackStart {
                start = fallback
                usedFallback = true
            } else {
                alerts.append(PlanAlert(
                    kind: .noLoopTime,
                    message: "No \(blockID) today, and the rules give the \(rule.title.lowercased()) no other start time.",
                    people: [rule.driver]
                ))
                return nil
            }
        }

        var stops: [PickupLoopPlan.Stop] = []
        var time = start
        for stop in rule.stops {
            if let required = stop.onlyWhen, occurrences[required] == nil { continue }
            if !stops.isEmpty {
                time = Self.later(time, by: rule.minutesBetweenStops)
            }
            stops.append(.init(place: stop.place, time: time, kids: stop.collect))
        }
        guard !stops.isEmpty else { return nil }
        let end = Self.later(time, by: rule.minutesToHome)
        let loop = PickupLoopPlan(title: rule.title, driver: rule.driver, start: start, end: end,
                                  stops: stops, usedFallbackStart: usedFallback)

        let route = stops.map { "\($0.place) \($0.time.short)" } + ["home ~\(end.short)"]
        items.append(TimelineItem(
            id: "loop",
            title: rule.title,
            kind: .pickupLoop,
            start: instant(start),
            end: instant(end),
            isAllDay: false,
            people: [rule.driver],
            importance: rules.importance(of: .pickupLoop),
            origin: .rule("pickupLoop"),
            detail: route.joined(separator: " → ")
        ))
        // The kids' side of the loop: in the car from their stop until home.
        // Low importance, so "next up" shows the driver's loop, not each ride.
        for stop in stops {
            for kid in stop.kids {
                items.append(TimelineItem(
                    id: "loop:\(kid)",
                    title: "Pickup → home",
                    kind: .pickupLoop,
                    start: instant(stop.time),
                    end: instant(end),
                    isAllDay: false,
                    people: [kid],
                    importance: .low,
                    origin: .rule("pickupLoop"),
                    detail: "Picked up at \(stop.place) \(stop.time.short)"
                ))
            }
        }
        return loop
    }

    // MARK: Care

    /// Adds each kid's time with their caregivers (minus their own school
    /// hours) and the caregivers' side of it. Returns each caregiver's window.
    private mutating func addCare(
        _ occurrences: [String: BlockOccurrence],
        loop: PickupLoopPlan?
    ) -> [(care: CareRule, start: Date, end: Date)] {
        var windows: [(care: CareRule, start: Date, end: Date)] = []
        for care in rules.care where care.days.contains(date.weekday) {
            let from = instant(care.from)
            var latest = from
            var kidsInCare: [PersonID] = []
            let title = care.title ?? "With \(planner.names(care.caregivers))"
            for kid in care.kids {
                let until: LocalTime?
                switch care.until {
                case let .time(time): until = time
                case .pickupLoop: until = loop?.stops.first { $0.kids.contains(kid) }?.time
                }
                guard let until, until > care.from else { continue }
                let end = instant(until)
                let ownBlocks = occurrences.values
                    .filter { $0.block.who.contains(kid) }
                    .map { (instant($0.start), instant($0.end)) }
                let segments = Self.subtract(from: (from, end), ownBlocks)
                for (index, segment) in segments.enumerated() {
                    items.append(TimelineItem(
                        id: "care:\(care.id):\(kid):\(index)",
                        title: title,
                        kind: .care,
                        start: segment.0,
                        end: segment.1,
                        isAllDay: false,
                        people: [kid],
                        importance: rules.importance(of: .care),
                        origin: .rule(care.id),
                        detail: nil
                    ))
                }
                if !segments.isEmpty {
                    kidsInCare.append(kid)
                    latest = max(latest, end)
                }
            }
            guard !kidsInCare.isEmpty else { continue }
            items.append(TimelineItem(
                id: "care:\(care.id)",
                title: "Watching \(planner.names(kidsInCare))",
                kind: .care,
                start: from,
                end: latest,
                isAllDay: false,
                people: care.caregivers,
                importance: rules.importance(of: .care),
                origin: .rule(care.id),
                detail: nil
            ))
            windows.append((care, from, latest))
        }
        return windows
    }

    // MARK: Calendar events

    /// Places each event by the assignment rules, then the built-in
    /// attribution. Returns the calendars that had events nobody claimed.
    private mutating func addEvents(_ events: [SourceEvent]) -> [String] {
        let dayStart = clock.startOfDay(date)
        let dayEnd = clock.endOfDay(date)
        var unlisted = Set<String>()
        for event in events {
            let touchesDay = event.start < dayEnd && (event.end > dayStart || (event.end == event.start && event.start >= dayStart))
            guard touchesDay else { continue }
            guard let assignment = planner.assignment(of: event) else {
                let listed = rules.calendars.contains {
                    $0.title.caseInsensitiveCompare(event.calendarTitle) == .orderedSame
                }
                if !listed { unlisted.insert(event.calendarTitle) }
                continue
            }
            let calendarTitle = rules.calendars.first {
                $0.title.caseInsensitiveCompare(event.calendarTitle) == .orderedSame
            }?.title ?? event.calendarTitle
            let item = TimelineItem(
                id: "event:\(event.id)",
                title: event.title,
                kind: .appointment,
                start: max(event.start, dayStart),
                end: min(event.end, dayEnd),
                isAllDay: event.isAllDay,
                people: assignment.people,
                importance: assignment.importance ?? rules.importance(of: .appointment),
                origin: .calendar(title: calendarTitle, attribution: assignment.attribution),
                detail: event.location,
                rules: assignment.rules
            )
            if assignment.hidden {
                hidden.append(item)
            } else {
                items.append(item)
            }
        }
        return unlisted.sorted()
    }

    // MARK: Alerts

    private mutating func alertForSchools(_ schools: [SchoolStatus], weekday: Weekday) {
        let caredFor = Set(rules.care.filter { $0.days.contains(weekday) }.flatMap(\.kids))
        for school in schools {
            switch school.state {
            case let .noSchool(label):
                alerts.append(PlanAlert(
                    kind: .noSchool,
                    message: "No \(school.title.lowercased()) today\(label.map { " (\($0))" } ?? "").",
                    people: school.people
                ))
                let uncovered = school.people.filter { !caredFor.contains($0) }
                if !uncovered.isEmpty {
                    alerts.append(PlanAlert(
                        kind: .uncoveredKid,
                        message: "No rule says who has \(planner.names(uncovered)) today.",
                        people: uncovered
                    ))
                }
            case let .inSession(_, end, earlyRelease) where earlyRelease:
                let usual = rules.blocks.first { $0.id == school.blockID }?.end
                alerts.append(PlanAlert(
                    kind: .earlyRelease,
                    message: "Early release: \(school.title) ends \(end.short)\(usual.map { " instead of \($0.short)" } ?? "").",
                    people: school.people
                ))
            default:
                break
            }
        }
    }

    private mutating func alertForConflicts(careWindows: [(care: CareRule, start: Date, end: Date)], loop: PickupLoopPlan?) {
        let appointments = items.filter { $0.kind == .appointment && !$0.isAllDay }
        for window in careWindows {
            for item in appointments where item.overlaps(window.start, window.end) {
                let busy = window.care.caregivers.filter { item.people.contains($0) }
                guard !busy.isEmpty else { continue }
                alerts.append(PlanAlert(
                    kind: .careConflict,
                    message: "\(planner.names(busy)): \(item.title) \(span(item)) while watching the kids (\(span(window.start, window.end))).",
                    people: busy
                ))
            }
        }
        guard let loop else { return }
        let loopStart = instant(loop.start)
        let loopEnd = instant(loop.end)
        for item in appointments where item.people.contains(loop.driver) && item.overlaps(loopStart, loopEnd) {
            alerts.append(PlanAlert(
                kind: .loopConflict,
                message: "\(planner.names([loop.driver])): \(item.title) \(span(item)) overlaps the \(loop.title.lowercased()) (\(loop.start.short)–\(loop.end.short)).",
                people: [loop.driver]
            ))
        }
    }

    // MARK: Needs and lanes

    /// Recurring needs from the rules, then open reminders from the rules'
    /// Reminders lists (due today, overdue, or undated), by the people their
    /// titles name or the list's default owner.
    private func needs(_ occurrences: [String: BlockOccurrence], reminders: [SourceReminder]) -> [KidNeed] {
        var byKid: [PersonID: [String]] = [:]
        func add(_ item: String, for kid: PersonID) {
            if !byKid[kid, default: []].contains(item) {
                byKid[kid, default: []].append(item)
            }
        }
        for rule in rules.needs {
            if let days = rule.days, !days.contains(date.weekday) { continue }
            if let block = rule.onDaysOf, occurrences[block] == nil { continue }
            for kid in rule.who {
                for item in rule.items { add(item, for: kid) }
            }
        }
        for reminder in reminders {
            if let due = reminder.due, due > date { continue }
            guard let list = rules.reminderLists.first(where: {
                $0.title.caseInsensitiveCompare(reminder.listTitle) == .orderedSame
            }) else { continue }
            let named = planner.attributor.people(namedIn: reminder.title)
            let owners = named.isEmpty ? list.defaultOwner.map { [$0] } ?? [] : named
            for owner in owners { add(reminder.title, for: owner) }
        }
        var result: [KidNeed] = []
        var handled = Set<PersonID>()
        for person in rules.people where !handled.contains(person.id) {
            guard let items = byKid[person.id] else { continue }
            // Lane-mates (the twins) who need exactly the same share a line.
            let mates = person.lane.map { lane in rules.people.filter { $0.lane == lane }.map(\.id) } ?? [person.id]
            if mates.count > 1, mates.allSatisfy({ byKid[$0] == items }) {
                result.append(KidNeed(people: mates, items: items))
                handled.formUnion(mates)
            } else {
                result.append(KidNeed(people: [person.id], items: items))
                handled.insert(person.id)
            }
        }
        return result
    }

    private func laneGroups(noData: [PersonID: String]) -> [LaneGroup] {
        PersonGroup.allCases.compactMap { group in
            var keys: [String] = []
            var members: [String: [PersonID]] = [:]
            var labels: [String: String] = [:]
            for person in rules.people where person.group == group {
                let key = person.lane.map { "lane:\($0)" } ?? "person:\(person.id)"
                if members[key] == nil {
                    keys.append(key)
                    labels[key] = person.laneLabel
                }
                members[key, default: []].append(person.id)
            }
            let lanes = keys.map { key in
                let people = members[key]!
                let reason = people.compactMap { noData[$0] }.first
                let first = rules.person(people[0])!
                return Lane(id: key, label: labels[key]!, group: group, people: people,
                            items: Self.merged(items.filter { !Set($0.people).isDisjoint(with: people) }),
                            data: reason.map { .noData(reason: $0) } ?? .known,
                            color: rules.laneColor(of: first.id),
                            photo: people.count == 1 ? first.photo : nil,
                            initials: first.initials)
            }
            return lanes.isEmpty ? nil : LaneGroup(group: group, lanes: lanes)
        }
    }

    /// Household members' birthdays from the rules, plus the device's
    /// Birthdays calendar, within the lookahead. A name both lists share is
    /// shown once, as the household member.
    private func birthdays(_ sources: [SourceBirthday]) -> [UpcomingBirthday] {
        let lookahead = rules.birthdays.lookaheadDays
        var found: [UpcomingBirthday] = []
        func add(name: String, month: Int, day: Int, year: Int?, person: PersonID?) {
            guard let next = DayPlanner.nextBirthday(month: month, day: day, onOrAfter: date) else { return }
            let away = next.dayNumber - date.dayNumber
            guard away <= lookahead else { return }
            let key = name.lowercased()
            if found.contains(where: { $0.name.lowercased() == key && $0.date == next }) { return }
            found.append(UpcomingBirthday(name: name, date: next, daysAway: away,
                                          turning: year.map { next.year - $0 }, person: person))
        }
        var handled = Set<PersonID>()
        for person in rules.people where !handled.contains(person.id) {
            guard let birth = person.birthDate else { continue }
            // Lane-mates born the same day (the twins) share one entry.
            let twins = person.lane.map { lane in
                rules.people.filter { $0.lane == lane && $0.birthDate == birth }
            } ?? [person]
            handled.formUnion(twins.map(\.id))
            add(name: DayPlanner.list(twins.map(\.name)), month: birth.month, day: birth.day,
                year: birth.year, person: person.id)
        }
        for source in sources {
            add(name: source.name, month: source.month, day: source.day, year: source.year, person: nil)
        }
        return found.sorted { ($0.daysAway, $0.name) < ($1.daysAway, $1.name) }
    }

    /// Lane-mates' identical items (the twins' care) become one item for both.
    private static func merged(_ items: [TimelineItem]) -> [TimelineItem] {
        var result: [TimelineItem] = []
        for item in items {
            if let index = result.firstIndex(where: {
                $0.kind == item.kind && $0.title == item.title && $0.start == item.start
                    && $0.end == item.end && $0.isAllDay == item.isAllDay
            }) {
                let union = result[index].people + item.people.filter { !result[index].people.contains($0) }
                result[index] = result[index].with(people: union)
            } else {
                result.append(item)
            }
        }
        return result
    }

    // MARK: Helpers

    private func instant(_ time: LocalTime) -> Date {
        clock.instant(date, time)
    }

    private func span(_ item: TimelineItem) -> String {
        span(item.start, item.end)
    }

    private func span(_ start: Date, _ end: Date) -> String {
        "\(clock.localTime(of: start).short)–\(clock.localTime(of: end).short)"
    }

    static func later(_ time: LocalTime, by minutes: Int) -> LocalTime {
        time.adding(minutes: minutes) ?? LocalTime(hour: 23, minute: 59)!
    }

    /// `base` minus every cut, as ordered, non-empty pieces.
    static func subtract(from base: (Date, Date), _ cuts: [(Date, Date)]) -> [(Date, Date)] {
        var pieces = [base]
        for cut in cuts {
            pieces = pieces.flatMap { piece -> [(Date, Date)] in
                guard cut.0 < piece.1, cut.1 > piece.0 else { return [piece] }
                var kept: [(Date, Date)] = []
                if piece.0 < cut.0 { kept.append((piece.0, cut.0)) }
                if cut.1 < piece.1 { kept.append((cut.1, piece.1)) }
                return kept
            }
        }
        return pieces.sorted { $0.0 < $1.0 }
    }

    static func order(_ a: TimelineItem, _ b: TimelineItem) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.start != b.start { return a.start < b.start }
        if a.importance != b.importance { return a.importance > b.importance }
        if a.end != b.end { return a.end < b.end }
        return a.id < b.id
    }
}
