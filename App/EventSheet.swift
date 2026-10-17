import SwiftUI
import TodayCore

/// "Why is this here?": whose lane an item is on and the rule that put it
/// there. For calendar events: Move to (a rule for events with this exact
/// title), Make a rule, Hide from Today, Open in Calendar.
struct EventSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let item: TimelineItem
    @State private var moved: String?
    @State private var draft: AssignmentRule?
    @State private var issues: [RulesIssue] = []

    var body: some View {
        NavigationStack {
            if let planner = model.planner {
                content(planner)
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $draft) { rule in
            RuleEditor(rule: rule, isNew: true, insertAtTop: true)
                .environment(model)
        }
        .alert("Couldn't save the rule", isPresented: Binding(
            get: { !issues.isEmpty }, set: { if !$0 { issues = [] } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(issues.map(\.message).joined(separator: "\n"))
        }
    }

    /// The item as the plan has it now, so the sheet follows a move.
    private var current: TimelineItem {
        model.plan?.items.first { $0.id == item.id } ?? model.plan?.hiddenItems.first { $0.id == item.id } ?? item
    }

    private func content(_ planner: DayPlanner) -> some View {
        let item = current
        let why = planner.explain(item)
        let lanes = LaneOption.all(planner.rules)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.title2.bold())
                    Text(when(planner))
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
                }
            }
            if why.isEvent {
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(lanes) { lane in
                                Button {
                                    move(to: lane)
                                } label: {
                                    HStack(spacing: 6) {
                                        Avatar(initials: lane.initials, color: lane.color, photo: model.photoURL(lane.photo), size: 22)
                                        Text(lane.label).font(.subheadline.weight(.semibold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Theme.inset, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("why.move.\(lane.id)")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    if let moved {
                        Text(moved)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Move to")
                } footer: {
                    Text("Adds a rule at the top of Household › Rules for events titled “\(item.title)”.")
                }
                Section {
                    Button {
                        draft = planner.rules.draftRule(containing: item.title, assignTo: item.people)
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

    private func when(_ planner: DayPlanner) -> String {
        let clock = planner.clock
        let date = DisplayFormat.weekdayShortDate(clock.localDate(of: item.start))
        if item.isAllDay { return "\(date) · all day" }
        return "\(date) · \(DisplayFormat.twelveHourSpan(clock.localTime(of: item.start), clock.localTime(of: item.end)))"
    }

    private func move(to lane: LaneOption) {
        guard var rules = model.rules else { return }
        let rule = rules.moveEvents(titled: item.title, to: lane.people)
        issues = model.save(rules)
        if issues.isEmpty {
            moved = "Events titled “\(item.title)” now go to \(lane.label) (rule “\(rule.name)”)."
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
