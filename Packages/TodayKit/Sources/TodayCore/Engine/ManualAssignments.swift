import Foundation

/// People picked by hand for one event, or for every repeat of it.
public struct ManualAssignment: Sendable, Equatable, Codable {
    /// The calendar event's identifier (shared by a series' repeats).
    public var eventID: String
    /// The day of the one occurrence picked; `nil` for every repeat.
    public var date: LocalDate?
    /// The event's title when it was picked, for showing the list.
    public var title: String
    public var people: [PersonID]

    public init(eventID: String, date: LocalDate?, title: String, people: [PersonID]) {
        self.eventID = eventID
        self.date = date
        self.title = title
        self.people = people
    }
}

/// The household's manual picks: they beat assignment rules, names in
/// titles and calendar defaults. Kept beside the rules file, not in it,
/// since they're about particular events rather than rules.
public struct ManualAssignments: Sendable, Equatable, Codable {
    public var entries: [ManualAssignment]

    public init(entries: [ManualAssignment] = []) {
        self.entries = entries
    }

    /// The pick for this occurrence, else for the whole series.
    public func entry(for event: SourceEvent, on date: LocalDate) -> ManualAssignment? {
        entries.first { $0.eventID == event.id && $0.date == date }
            ?? entries.first { $0.eventID == event.id && $0.date == nil }
    }

    /// Picks `people` for the occurrence on `date`, or for every repeat when
    /// `date` is nil (which also drops that series' one-off picks).
    public mutating func set(_ people: [PersonID], for event: SourceEvent, on date: LocalDate?) {
        entries.removeAll { $0.eventID == event.id && ($0.date == date || date == nil) }
        entries.append(ManualAssignment(eventID: event.id, date: date, title: event.title, people: people))
    }

    /// Forgets the pick for this occurrence and the series.
    public mutating func clear(for event: SourceEvent, on date: LocalDate) {
        entries.removeAll { $0.eventID == event.id && ($0.date == date || $0.date == nil) }
    }

    /// Drops one-off picks for days before `date`; series picks stay.
    public mutating func prune(before date: LocalDate) {
        entries.removeAll { entry in entry.date.map { $0 < date } ?? false }
    }

    /// Drops a person from every pick, and picks left with nobody.
    public mutating func remove(_ person: PersonID) {
        entries = entries.compactMap { entry in
            var e = entry
            e.people.removeAll { $0 == person }
            return e.people.isEmpty ? nil : e
        }
    }
}
