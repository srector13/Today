import Foundation

/// The spoken brief behind the ▶ button: a few sentences, different in the
/// morning, at midday and in the afternoon (the check-in times decide which).
///
/// It never calls any time "free": a lane whose calendar isn't on the phone
/// is named as unknown, and an empty evening is "nothing else I can see".
public struct BriefComposer: Sendable {
    public let planner: DayPlanner

    public init(planner: DayPlanner) {
        self.planner = planner
    }

    /// The brief for `time`: the latest check-in at or before it, else morning.
    public func kind(at time: LocalTime) -> CheckInKind {
        planner.rules.checkIns
            .filter { $0.at <= time }
            .max { $0.at < $1.at }?.kind ?? .morning
    }

    public func brief(
        _ plan: DayPlan, now: Date, weather: WeatherSnapshot?,
        doneNeeds: Set<String> = [], kind: CheckInKind? = nil
    ) -> String {
        let clock = plan.clock
        let isToday = clock.localDate(of: now) == plan.date
        let kind = kind ?? (isToday ? self.kind(at: clock.localTime(of: now)) : .morning)
        let names = planner.names
        var sentences: [String] = []

        switch kind {
        case .morning where !isToday:
            sentences.append("Here's \(DisplayFormat.weekdayName(plan.date.weekday)), \(DisplayFormat.monthDay(plan.date)).")
        case .morning:
            sentences.append("Good morning. It's \(DisplayFormat.weekdayName(plan.date.weekday)), \(DisplayFormat.monthDay(plan.date)).")
        case .midday:
            sentences.append("Here's the rest of \(DisplayFormat.weekdayName(plan.date.weekday)).")
        case .afternoon:
            sentences.append("Here's the rest of today.")
        }

        if kind == .morning {
            let sessions = plan.schools.compactMap { school -> String? in
                guard case let .inSession(start, end, early) = school.state else { return nil }
                return "\(names(school.people)) \(school.people.count > 1 ? "have" : "has") \(school.title.lowercased()) "
                    + "from \(DisplayFormat.compactTime(start)) to \(DisplayFormat.compactTime(end))"
                    + (early ? ", an early release" : "")
            }
            if !sessions.isEmpty { sentences.append(Self.sentence(Self.spokenList(sessions))) }
            for care in planner.rules.care where plan.items.contains(where: { $0.id == "care:\(care.id)" }) {
                sentences.append("\(names(care.caregivers)) \(care.caregivers.count > 1 ? "have" : "has") "
                    + "\(names(care.kids)) \(planner.careEnd(care.until)).")
            }
        }

        let everyLaneBlank = !plan.lanes.isEmpty && plan.lanes.allSatisfy { !$0.data.isKnown }
        for alert in plan.alerts where !(alert.kind == .missingCalendar && !everyLaneBlank) && !(isToday && alert.isOver(at: now)) {
            sentences.append(alert.message)
        }
        if plan.lanes.contains(where: { $0.data == .noCalendarsPicked }) {
            sentences.append("No calendars are picked for Today yet, so I can't see anyone's day.")
        }

        if let loop = plan.pickupLoop, clock.instant(plan.date, loop.end) > now || !isToday {
            sentences.append(loopSentence(loop, plan: plan, now: now, isToday: isToday))
            if let weather,
               let chance = weather.rainChance(from: clock.instant(plan.date, loop.start), through: clock.instant(plan.date, loop.end)),
               chance >= WeatherSnapshot.likely {
                sentences.append("Rain is likely at pickup, so grab the umbrella.")
            }
        }

        let upcoming = plan.items.filter {
            $0.kind == .appointment && !$0.isAllDay && $0.importance >= .normal && ($0.end > now || !isToday)
        }
        if !upcoming.isEmpty {
            let shown = upcoming.prefix(6).map { item -> String in
                let time = DisplayFormat.compactTime(clock.localTime(of: item.start))
                return item.people.isEmpty ? "\(item.title) at \(time)" : "\(item.title) at \(time) for \(names(item.people))"
            }
            let more = upcoming.count > shown.count ? ", and \(upcoming.count - shown.count) more" : ""
            sentences.append("\(kind == .afternoon ? "Still to come" : "Coming up"): \(shown.joined(separator: "; "))\(more).")
        } else {
            sentences.append("Nothing else is on the calendars I can see.")
        }
        if kind == .morning {
            let allDay = plan.items.filter(\.isAllDay)
            if !allDay.isEmpty {
                sentences.append("All day: " + allDay.map { item in
                    item.people.isEmpty ? item.title : "\(item.title) for \(names(item.people))"
                }.joined(separator: "; ") + ".")
            }
        }

        if !plan.unassigned.isEmpty {
            let waiting = plan.unassigned.map { item in
                item.isAllDay ? item.title : "\(item.title) at \(DisplayFormat.compactTime(clock.localTime(of: item.start)))"
            }
            sentences.append("\(waiting.count == 1 ? "One event needs" : "\(waiting.count) events need") a person: \(Self.spokenList(waiting)).")
        }

        let unknown = plan.lanes.filter { !$0.data.isKnown }
        if !unknown.isEmpty, !everyLaneBlank {
            let labels = unknown.map(\.label)
            let whose = DayPlanner.list(labels.map { DisplayFormat.possessive($0) })
            sentences.append("\(whose) calendar\(labels.count > 1 ? "s aren't" : " isn't") on this iPhone, "
                + "so I can't see \(labels.count > 1 ? "their days" : "\(DisplayFormat.possessive(labels[0])) day").")
        }

        if kind == .morning {
            for need in plan.needs {
                let items = need.items.filter { !doneNeeds.contains(KidNeed.key(people: need.people, item: $0)) }
                guard !items.isEmpty else { continue }
                sentences.append("\(names(need.people)) need\(need.people.count > 1 ? "" : "s") \(Self.spokenList(items)).")
            }
        }

        if let weather, !weather.isCurrent {
            sentences.append("The forecast: \(weather.condition.lowercased()), with a high of \(weather.high) and a low of \(weather.low).")
        } else if let weather {
            var text = "It's \(weather.temperature) degrees and \(weather.condition.lowercased())"
            if kind == .morning { text += ", with a high of \(weather.high)" }
            sentences.append(text + ".")
            let dayEnd = clock.instant(plan.date, plan.dayWindow.end)
            if let rain = weather.firstLikelyRain(after: now, before: dayEnd), plan.pickupLoop == nil || kind == .morning {
                sentences.append("Rain likely around \(DisplayFormat.compactTime(clock.localTime(of: rain.time))).")
            }
        }

        if kind == .morning {
            for birthday in plan.birthdays where birthday.daysAway <= 7 {
                let who = birthday.turning.map { "\(birthday.name) turn\(birthday.name.contains(" & ") ? "" : "s") \($0)" }
                switch birthday.daysAway {
                case 0:
                    sentences.append(who.map { "\($0) today. Happy birthday!" } ?? "It's \(DisplayFormat.possessive(birthday.name)) birthday today.")
                default:
                    let when = birthday.daysAway == 1 ? "tomorrow" : (birthday.daysAway == 7 ? "in a week" : "on \(DisplayFormat.weekdayName(birthday.date.weekday))")
                    sentences.append(who.map { "\($0) \(when)." } ?? "\(DisplayFormat.possessive(birthday.name)) birthday is \(when).")
                }
            }
        }
        return sentences.joined(separator: " ")
    }

    private func loopSentence(_ loop: PickupLoopPlan, plan: DayPlan, now: Date, isToday: Bool) -> String {
        let names = planner.names
        let home = DisplayFormat.compactTime(loop.end)
        if isToday, plan.clock.instant(plan.date, loop.start) <= now {
            return "The \(loop.title.lowercased()) is under way; home around \(home)."
        }
        var stops: [String] = []
        for (index, stop) in loop.stops.enumerated() {
            let who = names(stop.kids)
            stops.append(index == 0 ? "\(who) at \(stop.place)"
                : "then \(who) at \(stop.place) at \(DisplayFormat.compactTime(stop.time))")
        }
        return "\(names([loop.driver])) drives the \(loop.title.lowercased()) at \(DisplayFormat.compactTime(loop.start)): "
            + stops.joined(separator: ", ") + ". Home around \(home)."
    }

    /// "a, b, and c".
    static func spokenList(_ words: [String]) -> String {
        switch words.count {
        case 0: ""
        case 1: words[0]
        case 2: "\(words[0]) and \(words[1])"
        default: words.dropLast().joined(separator: ", ") + ", and " + words.last!
        }
    }

    private static func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst() + "."
    }
}

extension KidNeed {
    /// Identifies one checked-off item on one day's needs card.
    public static func key(people: [PersonID], item: String) -> String {
        people.joined(separator: ",") + "|" + item
    }
}
