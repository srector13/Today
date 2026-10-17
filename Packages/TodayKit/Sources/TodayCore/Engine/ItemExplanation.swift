import Foundation

/// "Why is this here?": whose lane an item is on, and which rule put it
/// there, in words.
public struct ItemExplanation: Sendable, Equatable {
    /// "On Jess's lane".
    public let headline: String
    /// `Rule "SERC → Jess" · Title contains "SERC"`.
    public let reasons: [String]
    /// "Family calendar · Library annex", or "Household rules".
    public let source: String
    /// A calendar event, so "Move to" and "Make a rule" apply.
    public let isEvent: Bool
    /// The calendar it came from, for events.
    public let calendarTitle: String?
}

extension DayPlanner {
    public func explain(_ item: TimelineItem) -> ItemExplanation {
        let headline = lanesHeadline(item.people)
        switch item.origin {
        case let .calendar(title, attribution):
            var reasons: [String] = []
            var assigningRule: String?
            switch attribution {
            case let .rule(name):
                assigningRule = name
                let rule = rules.assignmentRules.first { $0.name == name }
                reasons.append("Rule \"\(name)\"" + (rule.map { " · \($0.conditionSummary)" } ?? ""))
            case .defaultOwner:
                let owner = item.people.first.map { names([$0]) } ?? "nobody"
                reasons.append("The title names nobody, so the \(title) calendar's default, \(owner), gets it.")
            case .namedInTitle:
                reasons.append("The title names \(names(attributor.people(namedIn: item.title))).")
            case .calendarOwner:
                let owner = item.people.first
                reasons.append("It's on \(DisplayFormat.possessive(owner.map { names([$0]) } ?? "its owner")) own calendar.")
                let named = attributor.people(namedIn: item.title).filter { $0 != owner }
                if !named.isEmpty {
                    reasons.append("The title also names \(names(named)).")
                }
            }
            for name in item.rules where name != assigningRule {
                let rule = rules.assignmentRules.first { $0.name == name }
                let effect = rule.map { r in r.actions.map { $0.summary(names: names) }.joined(separator: " · ") }
                reasons.append("Rule \"\(name)\"" + (effect.map { ": \($0)" } ?? ""))
            }
            var source = "\(title) calendar"
            if let place = item.detail, !place.isEmpty { source += " · \(place)" }
            return ItemExplanation(headline: headline, reasons: reasons, source: source,
                                   isEvent: true, calendarTitle: title)
        case let .rule(id):
            return ItemExplanation(headline: headline, reasons: [ruleReason(id)],
                                   source: "Household › Schedule", isEvent: false, calendarTitle: nil)
        }
    }

    /// "On Jess's lane", "On Sam's and Emma's lanes".
    func lanesHeadline(_ people: [PersonID]) -> String {
        var labels: [(label: String, plural: Bool)] = []
        for id in people {
            guard let person = rules.person(id) else { continue }
            let mates = person.lane.map { lane in rules.people.filter { $0.lane == lane }.count } ?? 1
            if !labels.contains(where: { $0.label == person.laneLabel }) {
                labels.append((person.laneLabel, mates > 1))
            }
        }
        guard !labels.isEmpty else { return "On no lane" }
        let owners = DayPlanner.list(labels.map { DisplayFormat.possessive($0.label, plural: $0.plural) })
        return "On \(owners) lane\(labels.count > 1 ? "s" : "")"
    }

    private func ruleReason(_ id: String) -> String {
        if let block = rules.blocks.first(where: { $0.id == id }) {
            var text = "The \(block.title) block: \(DisplayFormat.days(block.days)), \(DisplayFormat.twelveHourSpan(block.start, block.end))"
            if let calendar = block.schoolCalendar { text += ", minus the \(calendar) calendar's days off" }
            return text + "."
        }
        if let care = rules.care.first(where: { $0.id == id }) {
            return "Care: \(names(care.caregivers)) \(care.caregivers.count == 1 ? "has" : "have") \(names(care.kids)) "
                + "\(DisplayFormat.days(care.days)) from \(care.from.twelveHour) \(careEnd(care.until))."
        }
        if id == "pickupLoop", let loop = rules.pickupLoop {
            let stops = loop.stops.map(\.place).joined(separator: " → ")
            return "The \(loop.title.lowercased()): \(names([loop.driver])) drives \(stops) → home, \(loopStart(loop))."
        }
        return "Household rules."
    }

    func careEnd(_ end: CareEnd) -> String {
        switch end {
        case .pickupLoop: "until pickup"
        case let .time(time): "until \(time.twelveHour)"
        }
    }

    func loopStart(_ loop: PickupLoopRule) -> String {
        switch loop.startsAt {
        case let .blockEnd(id):
            let title = rules.blocks.first { $0.id == id }?.title.lowercased() ?? id
            return "when \(title) ends" + (loop.fallbackStart.map { " (\($0.twelveHour) without \(title))" } ?? "")
        case let .time(time):
            return "at \(time.twelveHour)"
        }
    }
}
