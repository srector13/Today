import SwiftUI
import TodayCore
import TodaySources

/// What each calendar on the phone is to the household, which listed
/// calendars are missing, and which Reminders lists hold kids' needs.
struct CalendarsTab: View {
    @Environment(AppModel.self) private var model
    let planner: DayPlanner
    @State private var issues: [RulesIssue] = []

    private var rules: HouseholdRules { planner.rules }

    var body: some View {
        List {
            if model.calendarAccess != .granted {
                Section {
                    if model.calendarAccess == .notDetermined {
                        Button {
                            Task { await model.connectCalendars() }
                        } label: {
                            Label("Connect Calendars & Reminders", systemImage: "calendar.badge.plus")
                        }
                    } else {
                        Text("Calendar access is off. Turn it on in Settings › Privacy & Security › Calendars › Today.")
                            .font(.footnote)
                    }
                }
            }
            Section("On this iPhone") {
                ForEach(model.deviceCalendars) { calendar in
                    CalendarRow(calendar: calendar, planner: planner) { use in
                        update { $0.setUse(use, ofCalendar: calendar.title) }
                    }
                }
                if model.deviceCalendars.isEmpty {
                    Text("No calendars to show yet.")
                        .foregroundStyle(.secondary)
                }
            }
            let onDevice = Set(model.deviceCalendars.map { $0.title.lowercased() })
            let missing = rules.calendars.filter { !onDevice.contains($0.title.lowercased()) }
            if !missing.isEmpty {
                Section {
                    ForEach(missing, id: \.title) { calendar in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.warning)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(calendar.title).font(.headline)
                                Text(missingText(calendar))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("calendar.missing.\(calendar.title)")
                    }
                } header: {
                    Text("Not found")
                } footer: {
                    Text("To share a calendar to this iPhone: in Calendar on the phone that owns it, tap Calendars, tap ⓘ next to the calendar, then Add Person. Or sign in to the same account in Settings › Apps › Calendar › Calendar Accounts.")
                }
            }
            Section {
                ForEach(reminderListTitles, id: \.self) { title in
                    ReminderListRow(title: title, planner: planner) { change in update(change) }
                }
                if reminderListTitles.isEmpty {
                    Text("No Reminders lists to show yet.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Reminders lists")
            } footer: {
                Text("Open reminders in these lists show under What the kids need: by the names in their titles, or the list's owner.")
            }
            Section("Diagnostics") {
                NavigationLink("Today as text") {
                    PlanTextScreen()
                }
            }
        }
        .alert("Can't save", isPresented: Binding(get: { !issues.isEmpty }, set: { if !$0 { issues = [] } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(issues.map(\.message).joined(separator: "\n"))
        }
    }

    private var reminderListTitles: [String] {
        var titles = model.deviceReminderLists
        for list in rules.reminderLists where !titles.contains(where: { $0.caseInsensitiveCompare(list.title) == .orderedSame }) {
            titles.append(list.title)
        }
        return titles
    }

    private func missingText(_ calendar: CalendarRule) -> String {
        switch calendar.role {
        case .personal:
            let owner = calendar.owner.map { planner.names([$0]) } ?? "Its owner"
            return "\(DisplayFormat.possessive(owner)) calendar isn't shared to this iPhone, so \(DisplayFormat.possessive(owner)) lane shows “No data”, never a free day."
        case .shared:
            return "This shared calendar isn't on this iPhone, so every lane shows “No data” until it is."
        }
    }

    private func update(_ change: (inout HouseholdRules) -> Void) {
        guard var edited = model.rules else { return }
        change(&edited)
        issues = model.save(edited)
    }
}

private struct CalendarRow: View {
    let calendar: DeviceCalendar
    let planner: DayPlanner
    let onChange: (HouseholdRules.CalendarUse) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: calendar.colorHex) ?? .gray)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.title)
                Text(roleText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !calendar.isBirthdays {
                Menu {
                    Section("Shared: nobody named goes to") {
                        ForEach(planner.rules.people) { person in
                            Button(person.name) { onChange(.shared(defaultOwner: person.id)) }
                        }
                        Button("Nobody") { onChange(.shared(defaultOwner: nil)) }
                    }
                    Section("Someone's own calendar") {
                        ForEach(planner.rules.people) { person in
                            Button(person.name) { onChange(.personal(owner: person.id)) }
                        }
                    }
                    Button("Not Used", role: .destructive) { onChange(.ignored) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .accessibilityLabel("Change what \(calendar.title) is")
                .accessibilityIdentifier("calendar.menu.\(calendar.title)")
            }
        }
    }

    private var roleText: String {
        if calendar.isBirthdays { return "Birthdays card only" }
        switch planner.rules.use(ofCalendar: calendar.title) {
        case .ignored:
            return "Not used"
        case let .shared(owner):
            return owner.map { "Shared · nobody named → \(planner.names([$0]))" } ?? "Shared · events need a name"
        case let .personal(owner):
            return "\(DisplayFormat.possessive(planner.names([owner]))) calendar"
        }
    }
}

private struct ReminderListRow: View {
    let title: String
    let planner: DayPlanner
    let onChange: ((inout HouseholdRules) -> Void) -> Void

    private var listed: ReminderListRule? {
        planner.rules.reminderLists.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: Binding(
                get: { listed != nil },
                set: { on in
                    onChange { rules in
                        if on {
                            rules.reminderLists.append(ReminderListRule(title: title))
                        } else {
                            rules.reminderLists.removeAll { $0.title.caseInsensitiveCompare(title) == .orderedSame }
                        }
                    }
                }
            ))
            if let listed {
                Picker("Unnamed items go to", selection: Binding(
                    get: { listed.defaultOwner },
                    set: { owner in
                        onChange { rules in
                            if let index = rules.reminderLists.firstIndex(where: { $0.title == listed.title }) {
                                rules.reminderLists[index].defaultOwner = owner
                            }
                        }
                    }
                )) {
                    Text("Nobody").tag(PersonID?.none)
                    ForEach(planner.rules.people.filter { $0.group == .kids }) { person in
                        Text(person.name).tag(PersonID?.some(person.id))
                    }
                }
                .font(.footnote)
            }
        }
    }
}

/// The day as plain text (the same text the golden tests pin), for
/// checking what the rules did.
struct PlanTextScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            if let plan = model.plan, let planner = model.planner {
                Text(PlanText.render(plan, planner: planner))
                    .font(.system(size: 9, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("plan.text")
                    .padding()
            }
        }
        .navigationTitle("Today as text")
        .navigationBarTitleDisplayMode(.inline)
    }
}
