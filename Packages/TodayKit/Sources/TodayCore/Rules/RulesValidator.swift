import Foundation

/// The checks a JSON Schema can't express: references between sections,
/// times that run forward, and a pickup loop that collects every kid the
/// care rules hand back to it.
public enum RulesValidator {
    public static func validate(_ rules: HouseholdRules) -> [RulesIssue] {
        var v = Validation(rules: rules)
        v.run()
        return v.issues
    }
}

private struct Validation {
    let rules: HouseholdRules
    var issues: [RulesIssue] = []

    init(rules: HouseholdRules) {
        self.rules = rules
    }

    private var personIDs: Set<PersonID> { Set(rules.people.map(\.id)) }
    private var blockIDs: Set<String> { Set(rules.blocks.map(\.id)) }

    mutating func run() {
        checkHeader()
        checkPeople()
        checkCalendars()
        checkBlocks()
        checkSchoolCalendars()
        checkCare()
        checkLoop()
        checkNeeds()
        checkReminderLists()
        checkAssignmentRules()
        checkCheckIns()
        for (index, item) in rules.todo.enumerated() {
            warn("todo[\(index)]", "Open question: \(item)")
        }
    }

    // MARK: Sections

    private mutating func checkHeader() {
        if !HouseholdRules.supportedSchemaVersions.contains(rules.schemaVersion) {
            let range = HouseholdRules.supportedSchemaVersions
            error("schemaVersion", "This app reads schema versions \(range.lowerBound)–\(range.upperBound), not \(rules.schemaVersion).")
        }
        if rules.birthdays.lookaheadDays < 1 || rules.birthdays.lookaheadDays > 366 {
            error("birthdays.lookaheadDays", "Use a number of days from 1 to 366.")
        }
        if TimeZone(identifier: rules.timeZone) == nil {
            error("timeZone", "\"\(rules.timeZone)\" is not a time zone. Use an IANA name like \"America/Chicago\".")
        }
        if rules.dayWindow.start >= rules.dayWindow.end {
            error("dayWindow", "start must be before end.")
        }
        if let home = rules.home {
            if !(-90...90).contains(home.latitude) {
                error("home.latitude", "Use a latitude from -90 to 90.")
            }
            if !(-180...180).contains(home.longitude) {
                error("home.longitude", "Use a longitude from -180 to 180.")
            }
        }
    }

    private mutating func checkPeople() {
        if rules.people.isEmpty {
            error("people", "List at least one person.")
        }
        var seen = Set<PersonID>()
        for (i, person) in rules.people.enumerated() {
            let path = "people[\(i)]"
            if person.id.trimmingCharacters(in: .whitespaces).isEmpty {
                error("\(path).id", "The id is empty.")
            } else if !seen.insert(person.id).inserted {
                error("\(path).id", "Duplicate id \"\(person.id)\".")
            }
            if person.name.trimmingCharacters(in: .whitespaces).isEmpty {
                error("\(path).name", "The name is empty.")
            }
            checkPlaceholder(person.name, at: "\(path).name")
            for (j, alias) in person.aliases.enumerated() {
                checkPlaceholder(alias, at: "\(path).aliases[\(j)]")
            }
            if let photo = person.photo,
               photo.isEmpty || photo.contains("/") || photo.contains("\\") || photo.hasPrefix(".") {
                error("\(path).photo", "\"\(photo)\" isn't a photo file name. Use a plain name like \"emma.jpg\".")
            }
        }
    }

    private mutating func checkReminderLists() {
        var titles = Set<String>()
        for (i, list) in rules.reminderLists.enumerated() {
            let path = "reminderLists[\(i)]"
            if !titles.insert(list.title.lowercased()).inserted {
                error("\(path).title", "Reminders list \"\(list.title)\" is listed twice.")
            }
            if let owner = list.defaultOwner {
                checkPerson(owner, at: "\(path).defaultOwner")
            }
        }
    }

    private mutating func checkAssignmentRules() {
        var ids = Set<String>()
        for (i, rule) in rules.assignmentRules.enumerated() {
            let path = "assignmentRules[\(i)]"
            if rule.id.trimmingCharacters(in: .whitespaces).isEmpty {
                error("\(path).id", "The id is empty.")
            } else if !ids.insert(rule.id).inserted {
                error("\(path).id", "Duplicate rule id \"\(rule.id)\".")
            }
            if rule.name.trimmingCharacters(in: .whitespaces).isEmpty {
                error("\(path).name", "Give the rule a name.")
            }
            if rule.conditions.isEmpty {
                error("\(path).conditions", "Add at least one condition.")
            }
            for (j, condition) in rule.conditions.enumerated()
            where condition.value.trimmingCharacters(in: .whitespaces).isEmpty {
                error("\(path).conditions[\(j)].value", "The text to match is empty.")
            }
            if rule.actions.isEmpty {
                error("\(path).actions", "Add at least one action.")
            }
            for (j, action) in rule.actions.enumerated() {
                switch action {
                case let .assignTo(people), let .alsoInclude(people):
                    if people.isEmpty {
                        error("\(path).actions[\(j)]", "Pick at least one person.")
                    }
                    for (k, id) in people.enumerated() {
                        checkPerson(id, at: "\(path).actions[\(j)][\(k)]")
                    }
                case .hide, .importance:
                    break
                }
            }
        }
    }

    private mutating func checkCalendars() {
        var titles = Set<String>()
        for (i, calendar) in rules.calendars.enumerated() {
            let path = "calendars[\(i)]"
            checkPlaceholder(calendar.title, at: "\(path).title")
            if !titles.insert(calendar.title.lowercased()).inserted {
                error("\(path).title", "Calendar \"\(calendar.title)\" is listed twice.")
            }
            switch calendar.role {
            case .shared:
                if let owner = calendar.defaultOwner {
                    checkPerson(owner, at: "\(path).defaultOwner")
                } else {
                    error(path, "A shared calendar needs a \"defaultOwner\": who an event belongs to when its title names nobody.")
                }
                if calendar.owner != nil {
                    error("\(path).owner", "A shared calendar has a \"defaultOwner\", not an \"owner\".")
                }
            case .personal:
                if let owner = calendar.owner {
                    checkPerson(owner, at: "\(path).owner")
                } else {
                    error(path, "A personal calendar needs an \"owner\".")
                }
                if calendar.defaultOwner != nil {
                    error("\(path).defaultOwner", "A personal calendar has an \"owner\", not a \"defaultOwner\".")
                }
            }
        }
    }

    private mutating func checkBlocks() {
        var seen = Set<String>()
        for (i, block) in rules.blocks.enumerated() {
            let path = "blocks[\(i)]"
            if !seen.insert(block.id).inserted {
                error("\(path).id", "Duplicate block id \"\(block.id)\".")
            }
            if block.start >= block.end {
                error(path, "start (\(block.start)) must be before end (\(block.end)).")
            }
            if block.who.isEmpty {
                error("\(path).who", "Name at least one person.")
            }
            for (j, id) in block.who.enumerated() {
                checkPerson(id, at: "\(path).who[\(j)]")
            }
            if let calendar = block.schoolCalendar, rules.schoolCalendars[calendar] == nil {
                error("\(path).schoolCalendar", "No school calendar \"\(calendar)\" in schoolCalendars.")
            }
        }
    }

    private mutating func checkSchoolCalendars() {
        for (id, calendar) in rules.schoolCalendars.sorted(by: { $0.key < $1.key }) {
            let path = "schoolCalendars.\(id)"
            if let first = calendar.firstDay, let last = calendar.lastDay, first > last {
                error(path, "firstDay (\(first)) is after lastDay (\(last)).")
            }
            for (i, entry) in calendar.noSchool.enumerated() where entry.from > entry.to {
                error("\(path).noSchool[\(i)]", "from (\(entry.from)) is after to (\(entry.to)).")
            }
            var dates = Set<LocalDate>()
            let blocks = rules.blocks.filter { $0.schoolCalendar == id }
            for (i, release) in calendar.earlyRelease.enumerated() {
                if !dates.insert(release.date).inserted {
                    error("\(path).earlyRelease[\(i)]", "\(release.date) is listed twice.")
                }
                if !blocks.isEmpty, !blocks.contains(where: { $0.start < release.end && release.end < $0.end }) {
                    warn("\(path).earlyRelease[\(i)]", "\(release.end) is outside every block that uses this calendar, so it changes nothing.")
                }
            }
        }
    }

    private mutating func checkCare() {
        for (i, care) in rules.care.enumerated() {
            let path = "care[\(i)]"
            for (j, id) in care.caregivers.enumerated() {
                checkPerson(id, at: "\(path).caregivers[\(j)]")
            }
            for (j, id) in care.kids.enumerated() {
                checkPerson(id, at: "\(path).kids[\(j)]")
            }
            switch care.until {
            case let .time(end):
                if care.from >= end {
                    error(path, "from (\(care.from)) must be before until (\(end)).")
                }
            case .pickupLoop:
                guard let loop = rules.pickupLoop else {
                    error("\(path).until", "Care runs until the pickup loop, but there is no pickupLoop.")
                    continue
                }
                let missingDays = loop.days.missing(from: care.days)
                if !missingDays.isEmpty {
                    error("\(path).until", "Care runs until the pickup loop on \(missingDays.map(\.rawValue).joined(separator: ", ")), but the loop doesn't run then.")
                }
                let collected = Set(loop.stops.flatMap(\.collect))
                for kid in care.kids where !collected.contains(kid) {
                    error("\(path).kids", "\"\(kid)\" is in care until the pickup loop, but no loop stop collects them.")
                }
            }
        }
    }

    private mutating func checkLoop() {
        guard let loop = rules.pickupLoop else { return }
        let path = "pickupLoop"
        checkPerson(loop.driver, at: "\(path).driver")
        if case let .blockEnd(block) = loop.startsAt {
            if !blockIDs.contains(block) {
                error("\(path).startsAt", "No block \"\(block)\". Use a block id from blocks, like \"school.end\".")
            } else if loop.fallbackStart == nil {
                warn("\(path).fallbackStart", "Without a fallbackStart, there's no loop on days \"\(block)\" doesn't run.")
            }
        }
        if loop.stops.isEmpty {
            error("\(path).stops", "List at least one stop.")
        }
        if loop.minutesBetweenStops < 0 || loop.minutesToHome < 0 {
            error(path, "Minutes can't be negative.")
        }
        var collected = Set<PersonID>()
        for (i, stop) in loop.stops.enumerated() {
            for (j, kid) in stop.collect.enumerated() {
                checkPerson(kid, at: "\(path).stops[\(i)].collect[\(j)]")
                if !collected.insert(kid).inserted {
                    error("\(path).stops[\(i)].collect[\(j)]", "\"\(kid)\" is collected at two stops.")
                }
            }
            if let block = stop.onlyWhen, !blockIDs.contains(block) {
                error("\(path).stops[\(i)].onlyWhen", "No block \"\(block)\".")
            }
        }
    }

    private mutating func checkNeeds() {
        for (i, need) in rules.needs.enumerated() {
            let path = "needs[\(i)]"
            for (j, id) in need.who.enumerated() {
                checkPerson(id, at: "\(path).who[\(j)]")
            }
            if need.days == nil && need.onDaysOf == nil {
                error(path, "Say when: \"days\", \"onDaysOf\" (a block id), or both.")
            }
            if let block = need.onDaysOf, !blockIDs.contains(block) {
                error("\(path).onDaysOf", "No block \"\(block)\".")
            }
            if need.items.isEmpty {
                error("\(path).items", "List at least one item.")
            }
        }
    }

    private mutating func checkCheckIns() {
        var kinds = Set<CheckInKind>()
        for (i, checkIn) in rules.checkIns.enumerated() where !kinds.insert(checkIn.kind).inserted {
            error("checkIns[\(i)].kind", "\"\(checkIn.kind.rawValue)\" is listed twice.")
        }
    }

    // MARK: Helpers

    private mutating func checkPerson(_ id: PersonID, at path: String) {
        guard !personIDs.contains(id) else { return }
        var message = "No person \"\(id)\"."
        if let guess = closestMatch(to: id, in: personIDs) {
            message += " Did you mean \"\(guess)\"?"
        }
        error(path, message)
    }

    /// `<...>` marks a value the household still has to fill in.
    private mutating func checkPlaceholder(_ value: String, at path: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<") && trimmed.hasSuffix(">") {
            warn(path, "Placeholder \(trimmed): replace it with the real value.")
        }
    }

    private mutating func error(_ path: String, _ message: String) {
        issues.append(RulesIssue(.error, path, message))
    }

    private mutating func warn(_ path: String, _ message: String) {
        issues.append(RulesIssue(.warning, path, message))
    }
}
