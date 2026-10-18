import Foundation
import Testing
@testable import TodayCore

/// The real `Rules/household.json` the app ships. These checks are about the
/// file staying usable after hand edits, not about its exact times: change
/// the hours freely, and these still pass as long as the file is coherent.
@Suite("Bundled household.json")
struct BundledRulesTests {
    static let url = repositoryRoot.appendingPathComponent("Rules/household.json")

    @Test func loadsWithoutErrors() throws {
        let loaded = try RulesLoader.load(contentsOf: Self.url)
        #expect(loaded.rules.timeZone == "America/Chicago")
        // Warnings are expected until the placeholders and todos are filled in.
        #expect(loaded.warnings.allSatisfy { $0.severity == .warning })
    }

    @Test func everyDayOfTheComingYearPlans() throws {
        let rules = try RulesLoader.load(contentsOf: Self.url).rules
        let planner = try DayPlanner(rules: rules)
        let first = LocalDate(iso: "2026-10-01")!
        let calendars = Set(rules.calendars.map(\.title))
        for offset in 0..<400 {
            let date = first.adding(days: offset)
            let plan = planner.plan(for: date, events: [], calendarsOnDevice: calendars)
            #expect(!plan.lanes.isEmpty)
            for item in plan.items {
                #expect(item.start <= item.end, "\(date): \(item.title)")
            }
            if let loop = plan.pickupLoop {
                #expect(loop.start <= loop.end, "\(date)")
            }
        }
    }

    @Test func sharedCalendarDefaultsToAGrandparent() throws {
        let rules = try RulesLoader.load(contentsOf: Self.url).rules
        for calendar in rules.calendars where calendar.members == .everyone {
            guard case let .people(ids) = calendar.ifNobodyNamed else {
                Issue.record("\(calendar.title) should name a default person")
                continue
            }
            for id in ids {
                #expect(try #require(rules.person(id)).group == .grandparents)
            }
        }
    }

    @Test func schemaFileIsValidJSON() throws {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("Rules/household.schema.json"))
        #expect(throws: Never.self) { try JSONSerialization.jsonObject(with: data) }
    }
}

/// "All date logic in America/Chicago, explicitly": no Swift source may reach
/// for the device's calendar or time zone. Everything goes through
/// `HouseholdClock`.
@Suite("Time-zone discipline")
struct TimeZoneDisciplineTests {
    static let forbidden = [
        "Calendar.current", "TimeZone.current", "NSCalendar.current",
        "NSTimeZone.local", "NSTimeZone.system", "NSTimeZone.default",
        "autoupdatingCurrent",
        // Inferred-type spellings of the same thing.
        "timeZone: .current", "timeZone = .current",
        "calendar: .current", "calendar = .current",
    ]

    /// Source folders only: CI builds into the checkout (dd/), and generated
    /// files there aren't ours to police.
    static let sourceRoots = [
        "App", "Widgets", "TodayTests", "TodayUITests",
        "Packages/TodayKit/Sources", "Packages/TodayKit/Tests",
    ]

    @Test func noSourceUsesTheDeviceCalendarOrZone() throws {
        let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL.path
        var offenders: [String] = []
        var scanned = 0
        let urls = Self.sourceRoots.flatMap { root -> [URL] in
            let enumerator = FileManager.default.enumerator(
                at: repositoryRoot.appendingPathComponent(root), includingPropertiesForKeys: nil)
            return (enumerator?.allObjects as? [URL]) ?? []
        }
        for url in urls {
            let path = url.standardizedFileURL.path
            guard url.pathExtension == "swift", path != thisFile else { continue }
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                let code = line.components(separatedBy: "//").first ?? line
                for pattern in Self.forbidden where code.contains(pattern) {
                    offenders.append("\(path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")):\(number + 1): \(pattern)")
                }
            }
        }
        #expect(scanned > 10, "The scan found too few sources; are the roots right?")
        #expect(offenders.isEmpty, "Use HouseholdClock instead:\n\(offenders.joined(separator: "\n"))")
    }
}
