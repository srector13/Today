import SwiftUI
import TodayCore

/// M1–M2's stand-in for the main screen: the day plan as text, the same
/// rendering the golden tests pin. M3 replaces it with the lanes UI.
struct RootView: View {
    var body: some View {
        if let seed = AppLaunch.seedDate {
            SeededPlanView(date: seed)
        } else {
            LivePlanView()
        }
    }
}

/// A seeded sample day (`TODAY_SEED`), for screenshots and UI tests.
struct SeededPlanView: View {
    let date: LocalDate

    var body: some View {
        if let planner = try? DayPlanner(rules: SampleHousehold.rules) {
            PlanTextView(title: "Sample \(date.iso)", text: PlanText.render(SampleHousehold.plan(for: date), planner: planner), isError: false)
        } else {
            PlanTextView(title: "Sample error", text: "The sample rules didn't load.", isError: true)
        }
    }
}

/// Today from the household store and this device's calendars.
struct LivePlanView: View {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        PlanTextView(title: "Today", text: text, isError: isError) {
            if model.calendarAccess == .notDetermined {
                Button {
                    Task { await model.connectCalendars() }
                } label: {
                    Label("Connect Calendars & Reminders", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("connect.calendars")
            }
        }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }

    private var isError: Bool {
        if case .rulesError = model.status { return true }
        return false
    }

    private var text: String {
        switch model.status {
        case .loading:
            return "Loading…"
        case let .rulesError(message):
            return message
        case .ready:
            var lines: [String] = []
            switch model.calendarAccess {
            case .granted: break
            case .notDetermined: lines.append("Calendars not connected yet: every calendar lane shows no data.")
            case .denied, .writeOnly: lines.append("Calendar access is off (Settings › Privacy › Calendars): calendar lanes show no data.")
            }
            if let recovered = model.recoveredFrom {
                lines.append("The saved rules couldn't be read; using the last good copy.\n\(recovered)")
            }
            if model.bundledUpdateAvailable {
                lines.append("A newer bundled household.json is available to import.")
            }
            if !model.warnings.isEmpty {
                lines.append("Rules incomplete (\(model.warnings.count)):\n" + model.warnings.map { "  \($0)" }.joined(separator: "\n"))
            }
            if let plan = model.plan, let planner = model.planner {
                lines.append(PlanText.render(plan, planner: planner))
            }
            return lines.joined(separator: "\n\n")
        }
    }
}

struct PlanTextView<Header: View>: View {
    let title: String
    let text: String
    let isError: Bool
    let header: Header

    init(title: String, text: String, isError: Bool, @ViewBuilder header: () -> Header = { EmptyView() }) {
        self.title = title
        self.text = text
        self.isError = isError
        self.header = header()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Outside the scroll view, so it keeps the screen's width
                // instead of the widest line of text's.
                header
                    .padding(.horizontal)
                    .padding(.top, 8)
                ScrollView([.vertical, .horizontal]) {
                    Text(text)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(isError ? Color.red : Color.primary)
                        .accessibilityIdentifier(isError ? "rules.error" : "plan.text")
                        .padding()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
