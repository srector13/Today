import SwiftUI
import TodayCore
import WidgetKit

@main
struct TodayWidgets: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
    }
}

/// M1 placeholder. It proves the extension builds, is embedded in the app,
/// links TodayCore and reads the bundled rules. M6 replaces it with the real
/// Lock Screen "next up" and Home Screen lanes widgets.
struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextUp", provider: NextUpProvider()) { entry in
            Text(entry.line)
                .font(.headline)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Next up")
        .description("The next thing that matters today.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct NextUpEntry: TimelineEntry {
    let date: Date
    let line: String
}

struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry {
        NextUpEntry(date: .now, line: "Pickup loop 3:30")
    }

    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        completion(Timeline(entries: [entry(at: .now)], policy: .after(Date(timeIntervalSinceNow: 3600))))
    }

    private func entry(at date: Date) -> NextUpEntry {
        guard let url = Bundle.main.url(forResource: "household", withExtension: "json"),
              let loaded = try? RulesLoader.load(contentsOf: url),
              let planner = try? DayPlanner(rules: loaded.rules) else {
            return NextUpEntry(date: date, line: "Rules unavailable")
        }
        let plan = planner.plan(for: planner.clock.localDate(of: date), events: [], calendarsOnDevice: [])
        guard let loop = plan.pickupLoop else {
            return NextUpEntry(date: date, line: "No pickup today")
        }
        return NextUpEntry(date: date, line: "\(loop.title) \(loop.start.short)")
    }
}
