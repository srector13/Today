import SwiftUI
import TodayCore
import TodaySources

/// What each calendar on the phone is to the household, which listed
/// calendars are missing, and which Reminders lists hold kids' needs.
struct CalendarsTab: View {
    @Environment(AppModel.self) private var model
    let planner: DayPlanner
    @State private var issues: [RulesIssue] = []
    @State private var editing: EditingCalendar?

    struct EditingCalendar: Identifiable {
        let title: String
        var id: String { title }
    }

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
                    CalendarRow(calendar: calendar, planner: planner) {
                        editing = EditingCalendar(title: calendar.title)
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
                        Button {
                            editing = EditingCalendar(title: calendar.title)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.warning)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(calendar.title).font(.headline).foregroundStyle(.primary)
                                    Text(missingText(calendar))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
        .sheet(item: $editing) { calendar in
            CalendarEditor(title: calendar.title, rule: rules.calendarRule(titled: calendar.title))
                .environment(model)
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
        switch calendar.members {
        case let .people(ids) where ids.count == 1:
            let owner = planner.names(ids)
            return "\(DisplayFormat.possessive(owner)) calendar isn't shared to this iPhone, so \(DisplayFormat.possessive(owner)) lane shows “No data”, never a free day."
        case let .people(ids):
            return "This calendar isn't on this iPhone, so \(planner.names(ids)) show “No data” until it is."
        case .everyone:
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
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: calendar.colorHex) ?? .gray)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.title).foregroundStyle(.primary)
                    Text(roleText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !calendar.isBirthdays {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(calendar.isBirthdays)
        .accessibilityIdentifier("calendar.\(calendar.title)")
    }

    private var roleText: String {
        if calendar.isBirthdays { return "Birthdays card only" }
        guard let rule = planner.rules.calendarRule(titled: calendar.title) else { return "Not used" }
        return HouseholdText(planner: planner).calendar(rule)
    }
}

/// One calendar: who it belongs to, and who gets an event whose title
/// names nobody.
struct CalendarEditor: View {
    enum Unnamed: Hashable {
        case members, ask, people
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State private var used: Bool
    @State private var everyone: Bool
    @State private var members: [PersonID]
    @State private var unnamed: Unnamed
    @State private var unnamedPeople: [PersonID]
    @State private var issues: [RulesIssue] = []

    init(title: String, rule: CalendarRule?) {
        self.title = title
        _used = State(initialValue: rule != nil)
        switch rule?.members {
        case .everyone?:
            _everyone = State(initialValue: true)
            _members = State(initialValue: [])
        case let .people(ids)?:
            _everyone = State(initialValue: false)
            _members = State(initialValue: ids)
        case nil:
            _everyone = State(initialValue: false)
            _members = State(initialValue: [])
        }
        switch rule?.ifNobodyNamed {
        case .ask?:
            _unnamed = State(initialValue: .ask)
            _unnamedPeople = State(initialValue: [])
        case let .people(ids)?:
            _unnamed = State(initialValue: .people)
            _unnamedPeople = State(initialValue: ids)
        case .members?, nil:
            _unnamed = State(initialValue: .members)
            _unnamedPeople = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            if let planner = model.planner {
                form(planner)
                    .editorChrome(title, issues: $issues) { save() }
            }
        }
    }

    private func form(_ planner: DayPlanner) -> some View {
        Form {
            Section {
                Toggle("Show on Today", isOn: $used)
                    .accessibilityIdentifier("calendar.used")
            } footer: {
                Text("Off: Today ignores this calendar's events.")
            }
            if used {
                Section {
                    Toggle("Everyone", isOn: $everyone)
                    if !everyone {
                        PeoplePicker(rules: planner.rules, selection: $members)
                            .accessibilityIdentifier("calendar.members")
                    }
                } header: {
                    Text("Belongs to")
                } footer: {
                    Text("One person makes it their own calendar. Pick several for a calendar you share, like one you and your wife both use.")
                }
                Section {
                    Picker("If the title names nobody", selection: $unnamed) {
                        Text(!everyone && members.count == 1 ? "\(planner.names(members))" : "Everyone it belongs to")
                            .tag(Unnamed.members)
                        Text("Ask me each time").tag(Unnamed.ask)
                        Text("Someone specific").tag(Unnamed.people)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if unnamed == .people {
                        PeoplePicker(rules: planner.rules, selection: $unnamedPeople)
                    }
                } header: {
                    Text("If the title names nobody")
                } footer: {
                    Text("A name in the title always wins (“Emma's dentist” goes to Emma). Your rules run first, and anything you assign by hand beats both. “Ask me” puts the event under Needs a person until you pick.")
                }
            }
        }
    }

    private func save() {
        guard var rules = model.rules else { return }
        var rule: CalendarRule?
        if used {
            let ifNobodyNamed: UnnamedEvents
            switch unnamed {
            case .members: ifNobodyNamed = .members
            case .ask: ifNobodyNamed = .ask
            case .people: ifNobodyNamed = .people(unnamedPeople)
            }
            rule = CalendarRule(title: title, members: everyone ? .everyone : .people(members), ifNobodyNamed: ifNobodyNamed)
        }
        rules.setCalendar(rule, titled: title)
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
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
            if let plan = model.plan(on: model.selectedDate), let planner = model.planner {
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
