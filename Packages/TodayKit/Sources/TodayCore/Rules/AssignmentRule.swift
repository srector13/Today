import Foundation

/// A Mail-style rule the household writes: "If Title contains SERC, assign
/// to Jess". Rules run in order before the built-in attribution (names in
/// titles, calendar owners), so an explicit rule always beats a guess.
public struct AssignmentRule: Sendable, Equatable, Identifiable {
    public enum Match: String, Codable, Sendable, CaseIterable {
        /// Every condition must hold.
        case all
        /// One condition is enough.
        case any
    }

    public var id: String
    public var name: String
    public var enabled: Bool
    public var match: Match
    public var conditions: [RuleCondition]
    public var actions: [RuleAction]
    /// Later rules don't run for an event this rule matched.
    public var stop: Bool

    public init(
        id: String, name: String, enabled: Bool = true, match: Match = .all,
        conditions: [RuleCondition], actions: [RuleAction], stop: Bool = true
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.match = match
        self.conditions = conditions
        self.actions = actions
        self.stop = stop
    }
}

public struct RuleCondition: Sendable, Equatable {
    public enum Field: String, Codable, Sendable, CaseIterable {
        case title, calendar, location, notes
    }

    public enum Op: String, Codable, Sendable, CaseIterable {
        case contains, doesNotContain, `is`, startsWith, endsWith
    }

    public var field: Field
    public var op: Op
    /// Compared ignoring case and accents.
    public var value: String

    public init(field: Field, op: Op, value: String) {
        self.field = field
        self.op = op
        self.value = value
    }
}

public enum RuleAction: Sendable, Equatable {
    /// The event belongs to these people instead of whoever the built-in
    /// attribution would pick.
    case assignTo([PersonID])
    /// Add these people to whoever the event belongs to.
    case alsoInclude([PersonID])
    /// Keep the event off Today entirely.
    case hide
    /// Override how much the event matters (e.g. for "next up").
    case importance(Importance)
}

// MARK: - Decoding

extension AssignmentRule: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, enabled, match, conditions, actions, stop
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        match = try c.decodeIfPresent(Match.self, forKey: .match) ?? .all
        conditions = try c.decode([RuleCondition].self, forKey: .conditions)
        actions = try c.decode([RuleAction].self, forKey: .actions)
        stop = try c.decodeIfPresent(Bool.self, forKey: .stop) ?? true
    }
}

extension RuleCondition: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case field, op, value
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        field = try c.decode(Field.self, forKey: .field)
        op = try c.decode(Op.self, forKey: .op)
        value = try c.decode(String.self, forKey: .value)
    }
}

extension RuleAction: Decodable {
    /// Each action is an object with exactly one key:
    /// `{"assignTo": ["jess"]}`, `{"alsoInclude": [...]}`, `{"hide": true}`,
    /// `{"importance": "high"}`.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case assignTo, alsoInclude, hide, importance
    }

    public init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let present = CodingKeys.allCases.filter { c.contains($0) }
        guard present.count == 1, let key = present.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "An action has exactly one of: assignTo, alsoInclude, hide, importance."
            ))
        }
        switch key {
        case .assignTo:
            self = .assignTo(try c.decode([PersonID].self, forKey: .assignTo))
        case .alsoInclude:
            self = .alsoInclude(try c.decode([PersonID].self, forKey: .alsoInclude))
        case .hide:
            guard try c.decode(Bool.self, forKey: .hide) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath + [CodingKeys.hide],
                    debugDescription: "Write \"hide\": true, or remove the action."
                ))
            }
            self = .hide
        case .importance:
            self = .importance(try c.decode(Importance.self, forKey: .importance))
        }
    }
}
