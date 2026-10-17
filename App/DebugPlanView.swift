import SwiftUI
import TodayCore

/// M1's stand-in for the main screen: the day plan as text, the same
/// rendering the golden tests pin. M3 replaces it with the lanes UI.
struct DebugPlanView: View {
    struct Content {
        let title: String
        let text: String
        let isError: Bool

        static func forLaunch() -> Content {
            if let seed = AppLaunch.seedDate {
                return seeded(seed)
            }
            switch AppRules.load() {
            case let .success(loaded):
                guard let planner = try? DayPlanner(rules: loaded.rules) else {
                    return Content(title: "Rules error", text: "Unknown time zone \(loaded.rules.timeZone)", isError: true)
                }
                let today = planner.clock.localDate(of: AppLaunch.now)
                // Calendars arrive with EventKit in M2. Until then the app can
                // see none, so calendar-backed lanes honestly show "no data".
                let plan = planner.plan(for: today, events: [], calendarsOnDevice: [])
                var text = PlanText.render(plan, planner: planner)
                if !loaded.warnings.isEmpty {
                    let warnings = loaded.warnings.map { "  \($0)" }.joined(separator: "\n")
                    text = "Rules incomplete (\(loaded.warnings.count)):\n\(warnings)\n\n\(text)"
                }
                return Content(title: "Today", text: text, isError: false)
            case let .failure(error):
                return Content(title: "Rules error", text: error.description, isError: true)
            }
        }

        static func seeded(_ date: LocalDate) -> Content {
            guard let planner = try? DayPlanner(rules: SampleHousehold.rules) else {
                return Content(title: "Sample error", text: "The sample rules didn't load.", isError: true)
            }
            let text = PlanText.render(SampleHousehold.plan(for: date), planner: planner)
            return Content(title: "Sample \(date.iso)", text: text, isError: false)
        }
    }

    let content: Content

    var body: some View {
        NavigationStack {
            ScrollView([.vertical, .horizontal]) {
                Text(content.text)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(content.isError ? Color.red : Color.primary)
                    .padding()
                    .accessibilityIdentifier(content.isError ? "rules.error" : "plan.text")
            }
            .navigationTitle(content.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
