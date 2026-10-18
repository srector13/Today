import SwiftUI
import TodayCore

/// "Why is this here?": whose lane an item is on and what put it there.
/// For calendar events: pick who it's for (just this event, every repeat,
/// or every event with its title), Make a Rule, Hide from Today, Open in
/// Calendar.
struct EventSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let item: TimelineItem
    let date: LocalDate
    @State private var chosen: Set<PersonID> = []
    @State private var scope: AppModel.PickScope = .thisEvent
    @State private var started = false
    @State private var message: String?
    @State private var draft: AssignmentRule?
    @State private var issues: [RulesIssue] = []

    var body: some View {
        NavigationStack {
            if let planner = model.planner {
                content(planner)
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard !started else { return }
            started = true
            chosen = Set(item.people)
        }
        .sheet(item: $draft) { rule in
            RuleEditor(rule: rule, isNew: true, insertAtTop: true)
                .environment(model)
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { !issues.isEmpty }, set: { if !$0 { issues = [] } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(issues.map(\.message).joined(separator: "\n"))
        }
    }

    /// The item as the plan has it now, so the sheet follows a pick.
    private var current: TimelineItem {
        guard let plan = model.plan(on: date) else { return item }
        return plan.items.first { $0.id == item.id }
            ?? plan.hiddenItems.first { $0.id == item.id }
            ?? plan.unassigned.first { $0.id == item.id }
            ?? item
    }

    private func content(_ planner: DayPlanner) -> some View {
        let item = current
        let why = planner.explain(item)
        let lanes = LaneOption.all(planner.rules)
        let pick = model.pick(for: item)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.title2.bold())
                    Text(when(planner, item))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(why.source)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            Section {
                HStack(spacing: 12) {
                    HStack(spacing: -6) {
                        ForEach(lanes.filter { !Set($0.people).isDisjoint(with: item.people) }) { lane in
                            Avatar(initials: lane.initials, color: lane.color, photo: model.photoURL(lane.photo), size: 32)
                                .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                        }
                    }
                    Text(why.headline)
                        .font(.headline)
                        .accessibilityIdentifier("why.headline")
                }
                ForEach(why.reasons, id: \.self) { reason in
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("why.reason")
                }
            }
            if why.isEvent, let event = item.event {
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(lanes) { lane in
                            let on = Set(lane.people).isSubset(of: chosen)
                            Button {
                                if on { chosen.subtract(lane.people) } else { chosen.formUnion(lane.people) }
                                message = nil
                            } label: {
                                PersonChip(name: lane.label, initials: lane.initials, color: lane.color, selected: on)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                            .accessibilityIdentifier("why.pick.\(lane.id)")
                        }
                    }
                    .padding(.vertical, 4)
                    Picker("For", selection: $scope) {
                        Text("Just this event").tag(AppModel.PickScope.thisEvent)
                        if event.isRecurring {
                            Text("Every repeat").tag(AppModel.PickScope.everyRepeat)
                        }
                        Text("Every “\(event.title)”").tag(AppModel.PickScope.everyTitled)
                    }
                    .accessibilityIdentifier("why.scope")
                    Button {
                        assign(item)
                    } label: {
                        Label("Assign", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(chosen.isEmpty)
                    .accessibilityIdentifier("why.assign")
                    if pick != nil {
                        Button("Clear My Pick", role: .destructive) {
                            model.clearPick(for: item)
                            chosen = Set(current.people)
                            message = "Back to the rules for this event."
                        }
                        .accessibilityIdentifier("why.clear")
                    }
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(item.people.isEmpty ? "Who's it for?" : "Assign to")
                } footer: {
                    Text("“Just this event” and “Every repeat” are your picks; they beat every rule. “Every …” adds a rule at the top of Household › Rules.")
                }
                Section {
                    Button {
                        draft = planner.rules.draftRule(containing: item.title, assignTo: Array(chosen.isEmpty ? Set(item.people) : chosen))
                    } label: {
                        Label("Make a Rule…", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    Button {
                        hide(why.calendarTitle)
                    } label: {
                        Label("Hide from Today", systemImage: "eye.slash")
                    }
                    Button {
                        let seconds = item.start.timeIntervalSinceReferenceDate
                        if let url = URL(string: "calshow:\(Int(seconds))") { openURL(url) }
                    } label: {
                        Label("Open in Calendar", systemImage: "calendar")
                    }
                }
            }
        }
        .navigationTitle("Why is this here?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func when(_ planner: DayPlanner, _ item: TimelineItem) -> String {
        let clock = planner.clock
        let day = DisplayFormat.weekdayShortDate(clock.localDate(of: item.start))
        if item.isAllDay { return "\(day) · all day" }
        return "\(day) · \(DisplayFormat.twelveHourSpan(clock.localTime(of: item.start), clock.localTime(of: item.end)))"
    }

    private func assign(_ item: TimelineItem) {
        guard let rules = model.rules else { return }
        let people = rules.people.map(\.id).filter { chosen.contains($0) }
        issues = model.assign(item, to: people, scope: scope)
        guard issues.isEmpty else { return }
        let names = model.planner?.names(people) ?? ""
        switch scope {
        case .thisEvent: message = "This event is \(DisplayFormat.possessive(names)) now."
        case .everyRepeat: message = "Every repeat is \(DisplayFormat.possessive(names)) now."
        case .everyTitled: message = "Events titled “\(item.title)” now go to \(names)."
        }
    }

    private func hide(_ calendar: String?) {
        guard var rules = model.rules else { return }
        rules.hideEvents(titled: item.title, calendar: calendar)
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }
}

/// A lane as the editors offer it: the twins are one choice.
struct LaneOption: Identifiable, Equatable {
    let id: String
    let label: String
    let people: [PersonID]
    let color: LaneColor
    let initials: String
    let photo: String?

    static func all(_ rules: HouseholdRules) -> [LaneOption] {
        var options: [LaneOption] = []
        for person in rules.people {
            if let lane = person.lane, let index = options.firstIndex(where: { $0.id == "lane:\(lane)" }) {
                let o = options[index]
                options[index] = LaneOption(id: o.id, label: o.label, people: o.people + [person.id],
                                            color: o.color, initials: o.initials, photo: nil)
                continue
            }
            options.append(LaneOption(
                id: person.lane.map { "lane:\($0)" } ?? person.id,
                label: person.laneLabel,
                people: [person.id],
                color: rules.laneColor(of: person.id),
                initials: person.initials,
                photo: person.photo
            ))
        }
        return options
    }
}
