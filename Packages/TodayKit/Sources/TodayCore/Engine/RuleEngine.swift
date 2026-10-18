import Foundation

/// What the household's assignment rules decided for one event.
public struct RuleOutcome: Sendable, Equatable {
    /// Who the rules assigned it to; `nil` leaves it to the built-in
    /// attribution (names in titles, calendar owners).
    public var assigned: [PersonID]?
    /// The rule that set `assigned`.
    public var assigningRule: String?
    public var included: [PersonID] = []
    public var hidden = false
    public var importance: Importance?
    /// Names of every rule that matched, in order.
    public var matched: [String] = []
}

/// Runs `AssignmentRule`s, Mail-style: top to bottom, each matching rule's
/// actions applied in turn, stopping at the first matching rule whose
/// `stop` is set (the default, so normally the first match decides).
public struct RuleEngine: Sendable {
    public let rules: [AssignmentRule]

    public init(rules: [AssignmentRule]) {
        self.rules = rules
    }

    public func evaluate(_ event: SourceEvent) -> RuleOutcome {
        var outcome = RuleOutcome()
        for rule in rules where rule.enabled && Self.matches(rule, event) {
            outcome.matched.append(rule.name)
            for action in rule.actions {
                switch action {
                case let .assignTo(people):
                    outcome.assigned = people
                    outcome.assigningRule = rule.name
                case let .alsoInclude(people):
                    for id in people where !outcome.included.contains(id) {
                        outcome.included.append(id)
                    }
                case .hide:
                    outcome.hidden = true
                case let .importance(level):
                    outcome.importance = level
                }
            }
            if rule.stop { break }
        }
        return outcome
    }

    /// Whether the rule's conditions hold for the event, ignoring `enabled`
    /// (so the editor can preview a rule before it's switched on).
    public static func matches(_ rule: AssignmentRule, _ event: SourceEvent) -> Bool {
        guard !rule.conditions.isEmpty else { return false }
        switch rule.match {
        case .all: return rule.conditions.allSatisfy { matches($0, event) }
        case .any: return rule.conditions.contains { matches($0, event) }
        }
    }

    public static func matches(_ condition: RuleCondition, _ event: SourceEvent) -> Bool {
        let needle = fold(condition.value)
        guard !needle.isEmpty else { return false }
        let haystack: String
        switch condition.field {
        case .title: haystack = fold(event.title)
        case .calendar: haystack = fold(event.calendarTitle)
        case .location: haystack = fold(event.location ?? "")
        case .notes: haystack = fold(event.notes ?? "")
        }
        switch condition.op {
        case .contains: return haystack.contains(needle)
        case .doesNotContain: return !haystack.contains(needle)
        case .is: return haystack == needle
        case .startsWith: return haystack.hasPrefix(needle)
        case .endsWith: return haystack.hasSuffix(needle)
        }
    }

    /// Case- and accent-insensitive, trimmed: "  SÉRC " matches "serc".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Who an event belongs to, after the rules and the built-in attribution.
public struct EventAssignment: Sendable, Equatable {
    public let people: [PersonID]
    public let attribution: Attribution
    public let hidden: Bool
    public let importance: Importance?
    /// Every rule that matched, including ones that only added people,
    /// hid the event or changed its importance.
    public let rules: [String]
}

/// One event a rule being edited matches: whose lane it's on now, and whose
/// it would be with the rule.
public struct RulePreviewMatch: Sendable, Equatable {
    public let event: SourceEvent
    public let before: EventAssignment?
    public let after: EventAssignment?
}

extension DayPlanner {
    /// Who `event` belongs to: a manual pick first, then assignment rules,
    /// then the built-in attribution for calendars the rules list. `nil` when
    /// nobody claims it (a calendar the rules don't list, and no rule
    /// assigns it). An event on a calendar that asks comes back with nobody
    /// and `.unassigned`.
    public func assignment(
        of event: SourceEvent, manual: ManualAssignments = ManualAssignments(), using engine: RuleEngine? = nil
    ) -> EventAssignment? {
        let outcome = (engine ?? ruleEngine).evaluate(event)
        if let pick = manual.entry(for: event, on: clock.localDate(of: event.start)) {
            return EventAssignment(people: pick.people, attribution: .manual, hidden: false,
                                   importance: outcome.importance, rules: outcome.matched)
        }
        let calendar = rules.calendars.first {
            $0.title.caseInsensitiveCompare(event.calendarTitle) == .orderedSame
        }
        var people: [PersonID]
        var attribution: Attribution
        if let assigned = outcome.assigned {
            people = assigned
            attribution = .rule(outcome.assigningRule ?? "")
        } else if let calendar {
            (people, attribution) = owners(of: event.title, on: calendar)
        } else if let rule = outcome.matched.last, !outcome.included.isEmpty || outcome.hidden {
            people = []
            attribution = .rule(rule)
        } else {
            return nil
        }
        for id in outcome.included where !people.contains(id) {
            people.append(id)
        }
        if !people.isEmpty, attribution == .unassigned {
            // A rule added people to an event that would otherwise wait for a pick.
            attribution = .rule(outcome.matched.last ?? "")
        }
        guard !people.isEmpty || outcome.hidden || attribution == .unassigned else { return nil }
        return EventAssignment(people: people, attribution: attribution, hidden: outcome.hidden,
                               importance: outcome.importance, rules: outcome.matched)
    }

    /// The events `rule` matches, for the rule editor's live preview: who
    /// each belongs to without the rule, and with it run first.
    public func preview(of rule: AssignmentRule, events: [SourceEvent]) -> [RulePreviewMatch] {
        var candidate = rule
        candidate.enabled = true
        let others = rules.assignmentRules.filter { $0.id != rule.id }
        let without = RuleEngine(rules: others)
        let with = RuleEngine(rules: [candidate] + others)
        return events
            .filter { RuleEngine.matches(candidate, $0) }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
            .map { RulePreviewMatch(event: $0, before: assignment(of: $0, using: without), after: assignment(of: $0, using: with)) }
    }
}
