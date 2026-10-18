import Foundation

/// A JSON value whose objects keep their key order. Foundation's
/// `JSONEncoder` doesn't promise any order (on Linux it scrambles it), and a
/// file people hand-edit should come back from the app's editors in the same
/// shape they wrote it.
public indirect enum JSONValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([JSONMember])
}

public struct JSONMember: Equatable, Sendable {
    public let key: String
    public let value: JSONValue

    public init(_ key: String, _ value: JSONValue) {
        self.key = key
        self.value = value
    }
}

/// Writes `HouseholdRules` back to the rules-file format: what the app's
/// editors save and what Export shares. `RulesLoader` reads it back to an
/// equal value (the tests round-trip both the sample and the real file).
public enum RulesWriter {
    public static let schemaPointer = "./household.schema.json"

    public static func data(_ rules: HouseholdRules) -> Data {
        Data(text(rules).utf8)
    }

    public static func text(_ rules: HouseholdRules) -> String {
        JSONPrinter.print(json(rules), topLevelBlankLines: true) + "\n"
    }

    public static func json(_ rules: HouseholdRules) -> JSONValue {
        var m: [JSONMember] = [
            .init("$schema", .string(schemaPointer)),
            .init("schemaVersion", .int(HouseholdRules.currentSchemaVersion)),
            .init("timeZone", .string(rules.timeZone)),
        ]
        if !rules.todo.isEmpty {
            m.append(.init("todo", .array(rules.todo.map(JSONValue.string))))
        }
        m.append(.init("dayWindow", .object([
            .init("start", time(rules.dayWindow.start)), .init("end", time(rules.dayWindow.end)),
        ])))
        if let home = rules.home {
            var h: [JSONMember] = [.init("latitude", .number(home.latitude)), .init("longitude", .number(home.longitude))]
            if let label = home.label { h.append(.init("label", .string(label))) }
            m.append(.init("home", .object(h)))
        }
        m.append(.init("people", .array(rules.people.map(person))))
        m.append(.init("calendars", .array(rules.calendars.map(calendar))))
        m.append(.init("blocks", .array(rules.blocks.map(block))))
        m.append(.init("schoolCalendars", .object(rules.schoolCalendars.keys.sorted().map {
            .init($0, schoolCalendar(rules.schoolCalendars[$0]!))
        })))
        m.append(.init("care", .array(rules.care.map(care))))
        if let loop = rules.pickupLoop {
            m.append(.init("pickupLoop", pickupLoop(loop)))
        }
        m.append(.init("needs", .array(rules.needs.map(need))))
        m.append(.init("reminderLists", .array(rules.reminderLists.map(reminderList))))
        m.append(.init("assignmentRules", .array(rules.assignmentRules.map(assignmentRule))))
        m.append(.init("birthdays", .object([.init("lookaheadDays", .int(rules.birthdays.lookaheadDays))])))
        m.append(.init("checkIns", .array(rules.checkIns.map(checkIn))))
        m.append(.init("importance", .object(ItemKind.allCases.compactMap { kind in
            rules.importance[kind].map { .init(kind.rawValue, .string($0.rawValue)) }
        })))
        return .object(m)
    }

    // MARK: Sections

    static func person(_ p: Person) -> JSONValue {
        var m: [JSONMember] = [.init("id", .string(p.id)), .init("name", .string(p.name)), .init("group", .string(p.group.rawValue))]
        if !p.aliases.isEmpty { m.append(.init("aliases", strings(p.aliases))) }
        if let lane = p.lane { m.append(.init("lane", .string(lane))) }
        if let birthDate = p.birthDate { m.append(.init("birthDate", .string(birthDate.iso))) }
        if let color = p.color { m.append(.init("color", .string(color.hex))) }
        if let photo = p.photo { m.append(.init("photo", .string(photo))) }
        return .object(m)
    }

    static func calendar(_ c: CalendarRule) -> JSONValue {
        var m: [JSONMember] = [.init("title", .string(c.title))]
        switch c.members {
        case .everyone: m.append(.init("members", .string("everyone")))
        case let .people(ids): m.append(.init("members", strings(ids)))
        }
        switch c.ifNobodyNamed {
        case .members: break
        case .ask: m.append(.init("ifNobodyNamed", .string("ask")))
        case let .people(ids): m.append(.init("ifNobodyNamed", strings(ids)))
        }
        return .object(m)
    }

    static func block(_ b: BlockRule) -> JSONValue {
        var m: [JSONMember] = [
            .init("id", .string(b.id)), .init("title", .string(b.title)), .init("kind", .string(b.kind.rawValue)),
            .init("who", strings(b.who)), .init("days", days(b.days)),
            .init("start", time(b.start)), .init("end", time(b.end)),
        ]
        if let calendar = b.schoolCalendar { m.append(.init("schoolCalendar", .string(calendar))) }
        return .object(m)
    }

    static func schoolCalendar(_ c: SchoolCalendar) -> JSONValue {
        var m: [JSONMember] = []
        if let first = c.firstDay { m.append(.init("firstDay", .string(first.iso))) }
        if let last = c.lastDay { m.append(.init("lastDay", .string(last.iso))) }
        m.append(.init("noSchool", .array(c.noSchool.map { entry in
            if entry.from == entry.to, entry.label == nil { return .string(entry.from.iso) }
            var e: [JSONMember] = entry.from == entry.to
                ? [.init("date", .string(entry.from.iso))]
                : [.init("from", .string(entry.from.iso)), .init("to", .string(entry.to.iso))]
            if let label = entry.label { e.append(.init("label", .string(label))) }
            return .object(e)
        })))
        m.append(.init("earlyRelease", .array(c.earlyRelease.map { release in
            var e: [JSONMember] = [.init("date", .string(release.date.iso)), .init("end", time(release.end))]
            if let label = release.label { e.append(.init("label", .string(label))) }
            return .object(e)
        })))
        return .object(m)
    }

    static func care(_ c: CareRule) -> JSONValue {
        var m: [JSONMember] = [.init("id", .string(c.id))]
        if let title = c.title { m.append(.init("title", .string(title))) }
        let until: JSONValue
        switch c.until {
        case .pickupLoop: until = .string("pickupLoop")
        case let .time(t): until = time(t)
        }
        m += [
            .init("caregivers", strings(c.caregivers)), .init("kids", strings(c.kids)),
            .init("days", days(c.days)), .init("from", time(c.from)), .init("until", until),
        ]
        return .object(m)
    }

    static func pickupLoop(_ l: PickupLoopRule) -> JSONValue {
        let start: JSONValue
        switch l.startsAt {
        case let .blockEnd(block): start = .string("\(block).end")
        case let .time(t): start = time(t)
        }
        var m: [JSONMember] = [
            .init("title", .string(l.title)), .init("driver", .string(l.driver)),
            .init("days", days(l.days)), .init("startsAt", start),
        ]
        if let fallback = l.fallbackStart { m.append(.init("fallbackStart", time(fallback))) }
        m += [
            .init("minutesBetweenStops", .int(l.minutesBetweenStops)),
            .init("minutesToHome", .int(l.minutesToHome)),
            .init("stops", .array(l.stops.map { stop in
                var s: [JSONMember] = [.init("place", .string(stop.place)), .init("collect", strings(stop.collect))]
                if let only = stop.onlyWhen { s.append(.init("onlyWhen", .string(only))) }
                return .object(s)
            })),
        ]
        return .object(m)
    }

    static func need(_ n: NeedRule) -> JSONValue {
        var m: [JSONMember] = [.init("who", strings(n.who))]
        if let d = n.days { m.append(.init("days", days(d))) }
        if let block = n.onDaysOf { m.append(.init("onDaysOf", .string(block))) }
        m.append(.init("items", strings(n.items)))
        return .object(m)
    }

    static func reminderList(_ r: ReminderListRule) -> JSONValue {
        var m: [JSONMember] = [.init("title", .string(r.title))]
        if let owner = r.defaultOwner { m.append(.init("defaultOwner", .string(owner))) }
        return .object(m)
    }

    static func assignmentRule(_ r: AssignmentRule) -> JSONValue {
        .object([
            .init("id", .string(r.id)),
            .init("name", .string(r.name)),
            .init("enabled", .bool(r.enabled)),
            .init("match", .string(r.match.rawValue)),
            .init("conditions", .array(r.conditions.map { c in
                .object([.init("field", .string(c.field.rawValue)), .init("op", .string(c.op.rawValue)), .init("value", .string(c.value))])
            })),
            .init("actions", .array(r.actions.map { action in
                switch action {
                case let .assignTo(people): .object([.init("assignTo", strings(people))])
                case let .alsoInclude(people): .object([.init("alsoInclude", strings(people))])
                case .hide: .object([.init("hide", .bool(true))])
                case let .importance(level): .object([.init("importance", .string(level.rawValue))])
                }
            })),
            .init("stop", .bool(r.stop)),
        ])
    }

    static func checkIn(_ c: CheckInRule) -> JSONValue {
        var m: [JSONMember] = [.init("kind", .string(c.kind.rawValue)), .init("at", time(c.at))]
        if c.timeSensitive { m.append(.init("timeSensitive", .bool(true))) }
        return .object(m)
    }

    // MARK: Scalars

    static func time(_ t: LocalTime) -> JSONValue { .string(t.hhmm) }

    static func strings(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }

    static func days(_ d: DaySet) -> JSONValue {
        switch d {
        case .daily: .string("daily")
        case .weekdays: .string("weekdays")
        case .weekends: .string("weekends")
        default: strings(d.days.sorted().map(\.rawValue))
        }
    }
}

/// Pretty-prints `JSONValue` the way the rules file is hand-written: two-space
/// indent, short objects and lists on one line, long ones broken up.
enum JSONPrinter {
    static let lineWidth = 100

    static func print(_ value: JSONValue, topLevelBlankLines: Bool = false) -> String {
        render(value, indent: 0, topLevel: topLevelBlankLines)
    }

    private static func render(_ value: JSONValue, indent: Int, topLevel: Bool = false) -> String {
        if !topLevel, let line = inline(value), indent + line.count <= lineWidth {
            return line
        }
        let pad = String(repeating: " ", count: indent + 2)
        let close = String(repeating: " ", count: indent)
        switch value {
        case let .array(items):
            if items.isEmpty { return "[]" }
            let body = items.map { pad + render($0, indent: indent + 2) }.joined(separator: ",\n")
            return "[\n\(body)\n\(close)]"
        case let .object(members):
            if members.isEmpty { return "{}" }
            var body = ""
            for (index, member) in members.enumerated() {
                if index > 0 {
                    // At the top level, sections get a blank line between them;
                    // the scalar header keys stay together.
                    let bothScalars = isScalar(members[index - 1].value) && isScalar(member.value)
                    body += topLevel && !bothScalars ? ",\n\n" : ",\n"
                }
                body += pad + quote(member.key) + ": " + render(member.value, indent: indent + 2)
            }
            return "{\n\(body)\n\(close)}"
        default:
            return inline(value)!
        }
    }

    private static func isScalar(_ value: JSONValue) -> Bool {
        switch value {
        case .array, .object: false
        default: true
        }
    }

    /// The one-line form; `nil` for a list or object too nested to read inline.
    private static func inline(_ value: JSONValue, depth: Int = 0) -> String? {
        switch value {
        case let .string(s): return quote(s)
        case let .int(i): return String(i)
        case let .number(n): return number(n)
        case let .bool(b): return b ? "true" : "false"
        case .null: return "null"
        case let .array(items):
            guard depth < 3 else { return nil }
            let parts = items.map { inline($0, depth: depth + 1) }
            guard parts.allSatisfy({ $0 != nil }) else { return nil }
            return "[" + parts.map { $0! }.joined(separator: ", ") + "]"
        case let .object(members):
            guard depth < 3 else { return nil }
            if members.isEmpty { return "{}" }
            let parts = members.map { member in inline(member.value, depth: depth + 1).map { quote(member.key) + ": " + $0 } }
            guard parts.allSatisfy({ $0 != nil }) else { return nil }
            return "{ " + parts.map { $0! }.joined(separator: ", ") + " }"
        }
    }

    /// The shortest text that reads back as the same Double ("41.878").
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return "\(value)"
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20:
                out += String(format: "\\u%04x", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
