import SwiftUI
import TodayCore

struct RootView: View {
    @State private var model = AppModel()
    @State private var speaker = BriefSpeaker()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TodayScreen()
            .environment(model)
            .environment(speaker)
            .task { await model.load() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    model.tick()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, model.status == .ready {
                    Task { await model.refresh() }
                }
            }
    }
}

/// An item tapped on a day's page, for the "Why is this here?" sheet.
struct SelectedItem: Identifiable {
    let item: TimelineItem
    let date: LocalDate

    var id: String { "\(date.iso)/\(item.id)" }
}

/// The main screen: one page per day, swiped left and right. Each page has
/// the header with the ▶ brief, the day's chips and alerts, Up next, the
/// lanes, then weather, kids' needs and birthdays.
struct TodayScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showHousehold = false
    @State private var selected: SelectedItem?
    @State private var showWarnings = false

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.status {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .rulesError(message):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        DayHeader(date: model.today, showHousehold: $showHousehold)
                        RulesErrorCard(message: message)
                    }
                    .padding(.horizontal, 16)
                }
            case .ready:
                TabView(selection: $model.selectedDate) {
                    ForEach(model.pageDates, id: \.self) { date in
                        DayPage(date: date, selected: $selected, showHousehold: $showHousehold, showWarnings: $showWarnings)
                            .environment(\.isCurrentPage, date == model.selectedDate)
                            .tag(date)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showHousehold) {
            HouseholdScreen()
                .environment(model)
        }
        .sheet(item: $selected) { selection in
            EventSheet(item: selection.item, date: selection.date)
                .environment(model)
        }
        .sheet(isPresented: $showWarnings) {
            WarningsSheet(warnings: model.warnings)
        }
    }
}

extension EnvironmentValues {
    /// Whether this day's page is the one on screen. Neighbouring pages stay
    /// loaded, so the UI tests' identifiers are only given to this one.
    @Entry var isCurrentPage = true
}

/// An accessibility identifier that only the page on screen carries.
private struct PageIdentifier: ViewModifier {
    let id: String
    @Environment(\.isCurrentPage) private var isCurrentPage

    func body(content: Content) -> some View {
        content.accessibilityIdentifier(isCurrentPage ? id : "\(id)~offscreen")
    }
}

extension View {
    func pageIdentifier(_ id: String) -> some View {
        modifier(PageIdentifier(id: id))
    }
}

/// One day: its header, then the plan once it's loaded.
private struct DayPage: View {
    @Environment(AppModel.self) private var model
    @Environment(BriefSpeaker.self) private var speaker
    let date: LocalDate
    @Binding var selected: SelectedItem?
    @Binding var showHousehold: Bool
    @Binding var showWarnings: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DayHeader(date: date, showHousehold: $showHousehold)
                if let text = speaker.text, speaker.date == date {
                    BriefCard(text: text, isSpeaking: speaker.isSpeaking) { speaker.dismiss() }
                }
                if let plan = model.plan(on: date), let planner = model.planner {
                    DayContent(date: date, plan: plan, planner: planner, selected: $selected, showWarnings: $showWarnings)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .task(id: date) { await model.loadDay(date) }
    }
}

/// "October 20 · 2:40 PM" / "Tomorrow · October 21", the weekday, ▶, and
/// the Today and Household buttons.
private struct DayHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(BriefSpeaker.self) private var speaker
    let date: LocalDate
    @Binding var showHousehold: Bool

    var body: some View {
        let speaking = speaker.isSpeaking && speaker.date == date
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                HStack(spacing: 10) {
                    Text(DisplayFormat.weekdayName(date.weekday))
                        .font(.largeTitle.bold())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                        .pageIdentifier("today.title")
                    Button {
                        if let text = model.briefText(on: date) { speaker.toggle(text, for: date) }
                    } label: {
                        Image(systemName: speaking ? "stop.fill" : "play.fill")
                            .font(.footnote.weight(.bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .disabled(model.plan(on: date) == nil)
                    .accessibilityLabel(speaking ? "Stop the brief" : "Play the brief")
                    .pageIdentifier("brief.play")
                }
            }
            Spacer()
            HStack(spacing: 8) {
                if date != model.today {
                    Button {
                        withAnimation { model.selectedDate = model.today }
                    } label: {
                        Text("Today")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 4)
                            .frame(height: 26)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Back to today")
                    .pageIdentifier("today.jump")
                }
                Button {
                    showHousehold = true
                } label: {
                    Image(systemName: "person.2.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Household: people, rules and schedule")
                .pageIdentifier("household.open")
            }
        }
        .padding(.top, 8)
    }

    private var dateLine: String {
        let offset = date.dayNumber - model.today.dayNumber
        switch offset {
        case 0: return "\(DisplayFormat.monthDay(date)) · \(model.clock.localTime(of: model.now).twelveHour)"
        case 1: return "Tomorrow · \(DisplayFormat.monthDay(date))"
        case -1: return "Yesterday · \(DisplayFormat.monthDay(date))"
        default: return DisplayFormat.monthDay(date)
        }
    }
}

/// Everything under the header once the day is planned.
private struct DayContent: View {
    @Environment(AppModel.self) private var model
    let date: LocalDate
    let plan: DayPlan
    let planner: DayPlanner
    @Binding var selected: SelectedItem?
    @Binding var showWarnings: Bool

    var body: some View {
        let now = model.now
        let today = model.today
        let window = TimelineWindow.restOfDay(plan, now: now)
        let select: (TimelineItem) -> Void = { selected = SelectedItem(item: $0, date: date) }
        VStack(alignment: .leading, spacing: 16) {
            if date == today {
                SetupBanners(showWarnings: $showWarnings)
            }
            StatusChips(plan: plan, planner: planner)
            if date >= today {
                ForEach(Array(plan.alerts.filter { !$0.isOver(at: now) }.enumerated()), id: \.offset) { index, alert in
                    AlertCard(alert: alert)
                        .pageIdentifier("alert.\(index)")
                }
            }
            if !plan.unassigned.isEmpty {
                NeedsPersonCard(date: date, plan: plan, planner: planner, onSelect: select)
            }
            if date == today {
                UpNextCard(plan: plan, planner: planner, now: now, title: "Up next", weather: model.weather(on: date),
                           onSelect: select)
            } else if date > today {
                UpNextCard(plan: plan, planner: planner, now: planner.clock.startOfDay(date), title: "First up",
                           weather: model.weather(on: date), onSelect: select)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(date != today ? DisplayFormat.weekdayShortDate(date) : window.isRestOfDay ? "Rest of today" : "Today")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(window.label)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            LanesCard(plan: plan, window: window, now: now, onSelect: select)

            if date >= today {
                WeatherCard(date: date)
            }
            if !plan.needs.isEmpty {
                NeedsCard(date: date, plan: plan, planner: planner)
            }
            if !plan.birthdays.isEmpty {
                BirthdaysCard(plan: plan)
            }
            if model.isSeeded {
                Text("Sample household · names are placeholders except Jess")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Calendar access, incomplete rules and recovered files, above the day.
private struct SetupBanners: View {
    @Environment(AppModel.self) private var model
    @Binding var showWarnings: Bool
    @State private var importIssues: [RulesIssue] = []

    var body: some View {
        VStack(spacing: 12) {
            switch model.calendarAccess {
            case .granted:
                EmptyView()
            case .notDetermined:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Calendars not connected yet, so every lane shows no data.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                    Button {
                        Task { await model.connectCalendars() }
                    } label: {
                        Label("Connect Calendars & Reminders", systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("connect.calendars")
                }
                .card()
            case .denied, .writeOnly:
                Text("Calendar access is off (Settings › Privacy & Security › Calendars), so calendar lanes show no data.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .card()
            }
            if let recovered = model.recoveredFrom {
                Text("The saved rules couldn't be read, so the last good copy is in use.\n\(recovered)")
                    .font(.footnote)
                    .foregroundStyle(Theme.warningText)
                    .card(Theme.warningCard)
            }
            if model.bundledUpdateAvailable {
                HStack {
                    Text("This build has a newer household.json than the one you've edited.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("Use It") { importIssues = model.importBundledRules() }
                        .buttonStyle(.glass)
                }
                .card()
            }
            if !model.warnings.isEmpty {
                Button {
                    showWarnings = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "list.bullet.clipboard")
                            .foregroundStyle(Theme.warning)
                        Text("Rules incomplete: \(model.warnings.count) to finish in Household")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.tertiary)
                    }
                    .card(padding: 14)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rules.warnings")
            }
        }
        .alert("Couldn't use the bundled rules", isPresented: Binding(
            get: { !importIssues.isEmpty }, set: { if !$0 { importIssues = [] } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importIssues.map(\.description).joined(separator: "\n"))
        }
    }
}

/// "School · 8:15–3:30", "Preschool · 9–11:30", "With the grandparents".
private struct StatusChips: View {
    let plan: DayPlan
    let planner: DayPlanner

    var body: some View {
        let chips = self.chips
        if !chips.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(chips, id: \.text) { chip in
                    TintChip(text: chip.text, color: chip.color)
                }
            }
        }
    }

    private var chips: [(text: String, color: Color)] {
        var result: [(text: String, color: Color)] = []
        for school in plan.schools {
            let color = Color(planner.rules.laneColor(of: school.people.first ?? ""))
            switch school.state {
            case let .inSession(start, end, early):
                result.append(("\(school.title) · \(DisplayFormat.span(start, end))\(early ? " early" : "")", color))
            case let .noSchool(label):
                result.append(("No \(school.title.lowercased())\(label.map { " · \($0)" } ?? "")", color))
            case .outOfTerm:
                break
            }
        }
        for care in planner.rules.care where plan.items.contains(where: { $0.id == "care:\(care.id)" }) {
            let color = Color(planner.rules.laneColor(of: care.caregivers.first ?? ""))
            result.append((care.title ?? "With \(planner.names(care.caregivers))", color))
        }
        if result.isEmpty, plan.isWeekend {
            result.append(("Weekend", Theme.secondary))
        }
        return result
    }
}

private struct AlertCard: View {
    let alert: PlanAlert

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.warning)
                .frame(width: 30, height: 30)
                .background(Theme.warning.opacity(0.22), in: Circle())
            Text(alert.message)
                .font(.subheadline)
                .foregroundStyle(Theme.warningText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(Theme.warningCard, padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// The brief's words: while it plays, and afterwards until closed.
private struct BriefCard: View {
    let text: String
    let isSpeaking: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, isActive: isSpeaking)
                .foregroundStyle(Theme.accentBlue)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.briefText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("brief.text")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.briefText.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close the brief")
        }
        .card(Theme.briefCard, padding: 14)
    }
}

private struct RulesErrorCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The household rules didn't load", systemImage: "exclamationmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.footnote.monospaced())
                .foregroundStyle(Theme.warningText)
                .accessibilityIdentifier("rules.error")
        }
        .card(Theme.warningCard)
    }
}

struct WarningsSheet: View {
    let warnings: [RulesIssue]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Array(warnings.enumerated()), id: \.offset) { _, issue in
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.message)
                    if !issue.path.isEmpty {
                        Text(issue.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Rules incomplete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Fill these in under Household, or edit Rules/household.json and import it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}

/// Lays children out in rows, wrapping as needed: the chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
