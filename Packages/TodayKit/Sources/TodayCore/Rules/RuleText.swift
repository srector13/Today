import Foundation

/// The words the rules editor and the "why is this here?" sheet use.
extension RuleCondition.Field {
    public var label: String {
        switch self {
        case .title: "Title"
        case .calendar: "Calendar"
        case .location: "Location"
        case .notes: "Notes"
        }
    }
}

extension RuleCondition.Op {
    public var label: String {
        switch self {
        case .contains: "contains"
        case .doesNotContain: "doesn't contain"
        case .is: "is"
        case .startsWith: "starts with"
        case .endsWith: "ends with"
        }
    }
}

extension RuleCondition {
    /// `Title contains "SERC"`.
    public var summary: String {
        "\(field.label) \(op.label) \"\(value)\""
    }
}

extension Importance {
    public var label: String {
        switch self {
        case .background: "Background"
        case .low: "Low"
        case .normal: "Normal"
        case .high: "Important"
        }
    }
}

extension RuleAction {
    /// "Assign to Jess", "Hide from Today".
    public func summary(names: (([PersonID]) -> String)) -> String {
        switch self {
        case let .assignTo(people): "Assign to \(names(people))"
        case let .alsoInclude(people): "Also include \(names(people))"
        case .hide: "Hide from Today"
        case let .importance(level): level == .high ? "Mark important" : "Mark \(level.label.lowercased())"
        }
    }
}

extension AssignmentRule {
    /// The conditions: `Title is "Busy" and Calendar is "Sam"`.
    public var conditionSummary: String {
        conditions.map(\.summary).joined(separator: match == .all ? " and " : " or ")
    }

    /// `If Title contains "SERC" → Assign to Jess`.
    public func summary(names: (([PersonID]) -> String)) -> String {
        let then = actions.map { $0.summary(names: names) }.joined(separator: " · ")
        return "If \(conditions.isEmpty ? "(no conditions)" : conditionSummary) → \(then.isEmpty ? "(no actions)" : then)"
    }
}

/// The attribution that runs after the household's rules, for the Rules
/// list's "Built in · always last" section.
public struct BuiltInRule: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String

    public static func all(_ planner: DayPlanner) -> [BuiltInRule] {
        var result = [
            BuiltInRule(id: "names", name: "Names in titles",
                        summary: "People named in a title get the event, on any calendar the rules list."),
            BuiltInRule(id: "personal", name: "Personal calendars",
                        summary: "Events on someone's own calendar are theirs, plus anyone the title names."),
        ]
        for calendar in planner.rules.calendars where calendar.role == .shared {
            let owner = calendar.defaultOwner.map { planner.names([$0]) }
            result.append(BuiltInRule(
                id: "default:\(calendar.title)", name: "\(calendar.title) calendar default",
                summary: owner.map { "Anything on \(calendar.title) that names nobody goes to \($0)." }
                    ?? "Events on \(calendar.title) that name nobody aren't on any lane."
            ))
        }
        return result
    }
}
