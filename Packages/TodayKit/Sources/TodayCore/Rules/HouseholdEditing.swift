import Foundation

/// Changes the app's editors make. Each leaves the rules for
/// `RulesValidator` to check before the store saves them.
extension HouseholdRules {
    /// A lowercase, dash-separated id from `name` that isn't in `existing`:
    /// "SERC → Jess" → "serc-jess", then "serc-jess-2".
    public static func uniqueID(from name: String, existing: some Sequence<String>) -> String {
        let taken = Set(existing)
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var slug = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                slug.unicodeScalars.append(scalar)
            } else if !slug.isEmpty, !slug.hasSuffix("-") {
                slug += "-"
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        if slug.isEmpty { slug = "item" }
        guard taken.contains(slug) else { return slug }
        var n = 2
        while taken.contains("\(slug)-\(n)") { n += 1 }
        return "\(slug)-\(n)"
    }

    /// The first palette color nobody uses yet (or the next in turn).
    public var nextColor: LaneColor {
        let used = Set(people.indices.map { laneColor(of: people[$0].id) })
        return LaneColor.palette.first { !used.contains($0) } ?? LaneColor.palette[people.count % LaneColor.palette.count]
    }

    /// A new person with an unused color, ready for the person editor.
    public func newPerson(name: String = "", group: PersonGroup = .kids) -> Person {
        Person(id: Self.uniqueID(from: name.isEmpty ? "person" : name, existing: people.map(\.id)),
               name: name, group: group, color: nextColor)
    }

    /// Where `id` is used, in words, for "Remove from Household".
    public func references(to id: PersonID) -> [String] {
        var found: [String] = []
        for calendar in calendars {
            var named = false
            if case let .people(ids) = calendar.members, ids.contains(id) { named = true }
            if case let .people(ids) = calendar.ifNobodyNamed, ids.contains(id) { named = true }
            if named { found.append("the \(calendar.title) calendar") }
        }
        for block in blocks where block.who.contains(id) { found.append("the \(block.title) block") }
        for rule in care where rule.caregivers.contains(id) || rule.kids.contains(id) {
            found.append(rule.title.map { "\"\($0)\"" } ?? "a care rule")
        }
        if let loop = pickupLoop, loop.driver == id || loop.stops.contains(where: { $0.collect.contains(id) }) {
            found.append("the \(loop.title.lowercased())")
        }
        if needs.contains(where: { $0.who.contains(id) }) { found.append("kids' needs") }
        if reminderLists.contains(where: { $0.defaultOwner == id }) { found.append("a Reminders list") }
        for rule in assignmentRules where rule.actions.contains(where: { $0.people.contains(id) }) {
            found.append("the rule \"\(rule.name)\"")
        }
        return found
    }

    /// Removes the person and every mention of them. A rule left with no
    /// actions, a block or need left with nobody, and a calendar whose owner
    /// it was are removed too; a loop they drove stays for the validator to
    /// flag.
    public mutating func removePerson(_ id: PersonID) {
        people.removeAll { $0.id == id }
        calendars = calendars.compactMap { calendar in
            var c = calendar
            if case let .people(ids) = c.members {
                let rest = ids.filter { $0 != id }
                if rest.isEmpty { return nil }
                c.members = .people(rest)
            }
            if case let .people(ids) = c.ifNobodyNamed {
                let rest = ids.filter { $0 != id }
                c.ifNobodyNamed = rest.isEmpty ? .ask : .people(rest)
            }
            return c
        }
        blocks = blocks.compactMap { block in
            var b = block
            b.who.removeAll { $0 == id }
            return b.who.isEmpty ? nil : b
        }
        care = care.compactMap { rule in
            var c = rule
            c.caregivers.removeAll { $0 == id }
            c.kids.removeAll { $0 == id }
            return c.caregivers.isEmpty || c.kids.isEmpty ? nil : c
        }
        if var loop = pickupLoop {
            for index in loop.stops.indices { loop.stops[index].collect.removeAll { $0 == id } }
            pickupLoop = loop
        }
        needs = needs.compactMap { need in
            var n = need
            n.who.removeAll { $0 == id }
            return n.who.isEmpty ? nil : n
        }
        for index in reminderLists.indices where reminderLists[index].defaultOwner == id {
            reminderLists[index].defaultOwner = nil
        }
        assignmentRules = assignmentRules.compactMap { rule in
            var r = rule
            r.actions = r.actions.compactMap { $0.removing(id) }
            return r.actions.isEmpty ? nil : r
        }
    }

    // MARK: Rules from the event sheet

    /// "Move to": events with exactly this title go to `people` from now on.
    /// Adds the rule at the top, or updates the one an earlier move made.
    @discardableResult
    public mutating func moveEvents(titled title: String, to people: [PersonID]) -> AssignmentRule {
        let condition = RuleCondition(field: .title, op: .is, value: title)
        let name = "\(title) → \(people.compactMap { person($0)?.laneLabel }.uniqued().joined(separator: " & "))"
        if let index = assignmentRules.firstIndex(where: { $0.conditions == [condition] && $0.match == .all && $0.isMove }) {
            assignmentRules[index].actions = [.assignTo(people)]
            assignmentRules[index].name = name
            assignmentRules[index].enabled = true
            return assignmentRules[index]
        }
        let rule = AssignmentRule(id: Self.uniqueID(from: "move \(title)", existing: assignmentRules.map(\.id)),
                                  name: name, conditions: [condition], actions: [.assignTo(people)])
        assignmentRules.insert(rule, at: 0)
        return rule
    }

    /// "Hide from Today": events with exactly this title on this calendar.
    @discardableResult
    public mutating func hideEvents(titled title: String, calendar: String?) -> AssignmentRule {
        var conditions = [RuleCondition(field: .title, op: .is, value: title)]
        if let calendar { conditions.append(RuleCondition(field: .calendar, op: .is, value: calendar)) }
        let rule = AssignmentRule(id: Self.uniqueID(from: "hide \(title)", existing: assignmentRules.map(\.id)),
                                  name: "Hide \(title)", conditions: conditions, actions: [.hide])
        assignmentRules.insert(rule, at: 0)
        return rule
    }

    /// "Make a rule": a draft for the editor, "Title contains <title>".
    public func draftRule(containing text: String = "", assignTo people: [PersonID] = []) -> AssignmentRule {
        let names = people.compactMap { person($0)?.laneLabel }.uniqued().joined(separator: " & ")
        let name = text.isEmpty ? "New rule" : (names.isEmpty ? text : "\(text) → \(names)")
        return AssignmentRule(
            id: Self.uniqueID(from: name, existing: assignmentRules.map(\.id)),
            name: name,
            conditions: [RuleCondition(field: .title, op: .contains, value: text)],
            actions: people.isEmpty ? [] : [.assignTo(people)]
        )
    }

    /// Adds `rule`, or replaces the rule with its id.
    public mutating func upsert(_ rule: AssignmentRule) {
        if let index = assignmentRules.firstIndex(where: { $0.id == rule.id }) {
            assignmentRules[index] = rule
        } else {
            assignmentRules.append(rule)
        }
    }

    // MARK: Calendars

    /// The rule for a device calendar, matched ignoring case.
    public func calendarRule(titled title: String) -> CalendarRule? {
        calendars.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    /// Replaces (or adds) the rule for a calendar; `nil` stops using it.
    public mutating func setCalendar(_ rule: CalendarRule?, titled title: String) {
        let index = calendars.firstIndex { $0.title.caseInsensitiveCompare(title) == .orderedSame }
        switch (index, rule) {
        case let (index?, rule?): calendars[index] = rule
        case let (index?, nil): calendars.remove(at: index)
        case let (nil, rule?): calendars.append(rule)
        case (nil, nil): break
        }
    }

    /// The person's own (one-member) calendar, if one is listed.
    public func personalCalendar(of id: PersonID) -> String? {
        calendars.first { $0.soleMember == id }?.title
    }

    /// Makes `title` the person's calendar, or none. A calendar several
    /// people share gains them as a member instead of losing the others.
    public mutating func setPersonalCalendar(_ title: String?, for id: PersonID) {
        calendars.removeAll { $0.soleMember == id && $0.title.caseInsensitiveCompare(title ?? "") != .orderedSame }
        guard let title else { return }
        if var rule = calendarRule(titled: title) {
            switch rule.members {
            case .everyone:
                return
            case let .people(ids):
                if ids.isEmpty || !ids.contains(id) { rule.members = .people(ids + [id]) }
            }
            setCalendar(rule, titled: title)
        } else {
            calendars.append(CalendarRule(title: title, members: .people([id])))
        }
    }
}

extension RuleAction {
    /// The people an action names.
    public var people: [PersonID] {
        switch self {
        case let .assignTo(people), let .alsoInclude(people): people
        case .hide, .importance: []
        }
    }

    /// The action without `id`; `nil` if nobody's left to assign.
    func removing(_ id: PersonID) -> RuleAction? {
        switch self {
        case let .assignTo(people):
            let rest = people.filter { $0 != id }
            return rest.isEmpty ? nil : .assignTo(rest)
        case let .alsoInclude(people):
            let rest = people.filter { $0 != id }
            return rest.isEmpty ? nil : .alsoInclude(rest)
        case .hide, .importance:
            return self
        }
    }
}

extension AssignmentRule {
    /// Made by "Move to": one exact-title condition, one assignment.
    var isMove: Bool {
        guard conditions.count == 1, conditions[0].field == .title, conditions[0].op == .is,
              actions.count == 1, case .assignTo = actions[0] else { return false }
        return true
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
