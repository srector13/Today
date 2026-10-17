import Foundation
import TodayCore

// Prints day plans as text.
//
//   swift run today-plan                      the three seeded sample days
//   swift run today-plan 2026-11-26           a sample-household day
//   swift run today-plan --rules ../../Rules/household.json 2026-10-20
//                                             a real rules file (no calendar events)

var arguments = Array(CommandLine.arguments.dropFirst())
var rulesPath: String?
if let index = arguments.firstIndex(of: "--rules"), index + 1 < arguments.count {
    rulesPath = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
}

let rules: HouseholdRules
if let rulesPath {
    do {
        let loaded = try RulesLoader.load(contentsOf: URL(fileURLWithPath: rulesPath))
        for warning in loaded.warnings {
            FileHandle.standardError.write(Data("\(warning)\n".utf8))
        }
        rules = loaded.rules
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
} else {
    rules = SampleHousehold.rules
}

let dates: [LocalDate]
if arguments.isEmpty {
    dates = SampleHousehold.seededDays
} else {
    dates = arguments.map { argument in
        guard let date = LocalDate(iso: argument) else {
            FileHandle.standardError.write(Data("Not a date: \(argument) (use YYYY-MM-DD)\n".utf8))
            exit(2)
        }
        return date
    }
}

let planner = try DayPlanner(rules: rules)
for (index, date) in dates.enumerated() {
    // A real rules file has no events here; treat its calendars as present
    // but empty, so the output shows what the rules alone produce.
    let plan = rulesPath == nil
        ? planner.plan(for: date, events: SampleHousehold.events(on: date),
                       calendarsOnDevice: SampleHousehold.calendarsOnDevice(on: date))
        : planner.plan(for: date, events: [], calendarsOnDevice: Set(rules.calendars.map(\.title)))
    if index > 0 { print(String(repeating: "─", count: 72)) }
    print(PlanText.render(plan, planner: planner), terminator: "")
}
