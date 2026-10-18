import SwiftUI
import TodayCore

/// People, Rules, Schedule and Calendars: everything in household.json,
/// edited in the app. Each editor validates before it saves.
struct HouseholdScreen: View {
    enum Tab: String, CaseIterable, Identifiable {
        case people = "People"
        case rules = "Rules"
        case schedule = "Schedule"
        case calendars = "Calendars"

        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab

    init(tab: Tab = .people) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let planner = model.planner {
                    switch tab {
                    case .people: PeopleTab(planner: planner)
                    case .rules: RulesTab(planner: planner)
                    case .schedule: ScheduleTab(planner: planner)
                    case .calendars: CalendarsTab(planner: planner)
                    }
                } else {
                    ContentUnavailableView("Rules didn't load", systemImage: "exclamationmark.triangle",
                                           description: Text("Fix household.json and import it again."))
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityIdentifier("household.tabs")
            }
            .navigationTitle("Household")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("household.done")
                }
                if tab == .rules {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
            }
        }
    }
}

// MARK: - People

struct PeopleTab: View {
    @Environment(AppModel.self) private var model
    let planner: DayPlanner
    @State private var editing: Person?
    @State private var isNew = false

    var body: some View {
        let text = HouseholdText(planner: planner)
        List {
            ForEach(PersonGroup.allCases, id: \.self) { group in
                let people = planner.rules.people.filter { $0.group == group }
                if !people.isEmpty {
                    Section(group.title) {
                        ForEach(people) { person in
                            Button {
                                isNew = false
                                editing = person
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(initials: String(person.name.prefix(1)).uppercased(),
                                           color: planner.rules.laneColor(of: person.id),
                                           photo: model.photoURL(person.photo), size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.name).foregroundStyle(.primary)
                                        Text(text.person(person))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("person.\(person.id)")
                        }
                    }
                }
            }
            Section {
                Button {
                    isNew = true
                    editing = planner.rules.newPerson()
                } label: {
                    Label("Add Person", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("person.add")
            } footer: {
                Text("Each person's color paints their lane, their avatar and their widget blocks. People with the same lane name (the twins) share one lane.")
            }
        }
        .sheet(item: $editing) { person in
            PersonEditor(person: person, isNew: isNew)
                .environment(model)
        }
    }
}

// MARK: - Rules

struct RulesTab: View {
    @Environment(AppModel.self) private var model
    let planner: DayPlanner
    @State private var editing: AssignmentRule?
    @State private var isNew = false

    var body: some View {
        let names = planner.names
        List {
            Section {
                ForEach(planner.rules.assignmentRules) { rule in
                    HStack(spacing: 12) {
                        Button {
                            isNew = false
                            editing = rule
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name).foregroundStyle(.primary)
                                Text(rule.summary(names: names))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("rule.\(rule.id)")
                        Toggle(rule.enabled ? "Turn off \(rule.name)" : "Turn on \(rule.name)", isOn: Binding(
                            get: { rule.enabled },
                            set: { on in update { rules in
                                if let index = rules.assignmentRules.firstIndex(where: { $0.id == rule.id }) {
                                    rules.assignmentRules[index].enabled = on
                                }
                            } }
                        ))
                        .labelsHidden()
                    }
                    .opacity(rule.enabled ? 1 : 0.5)
                }
                .onMove { from, to in
                    update { $0.assignmentRules.move(fromOffsets: from, toOffset: to) }
                }
                .onDelete { offsets in
                    update { $0.assignmentRules.remove(atOffsets: offsets) }
                }
                Button {
                    isNew = true
                    editing = planner.rules.draftRule()
                } label: {
                    Label("New Rule", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("rule.new")
            } header: {
                Text("Your rules")
            } footer: {
                Text("Rules run top to bottom, like Mail. The first rule that matches an event decides whose lane it's on, unless it says to keep going. Tap Edit to reorder.")
            }
            Section("Built in · always last") {
                ForEach(Array(BuiltInRule.all(planner).enumerated()), id: \.offset) { index, rule in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.bold))
                            .frame(width: 22, height: 22)
                            .background(Theme.inset, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
                            Text(rule.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, isNew: isNew, insertAtTop: false)
                .environment(model)
        }
    }

    private func update(_ change: (inout HouseholdRules) -> Void) {
        guard var rules = model.rules else { return }
        change(&rules)
        model.save(rules)
    }
}
