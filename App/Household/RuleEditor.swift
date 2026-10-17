import SwiftUI
import TodayCore

/// A Mail-style rule: name, all/any conditions, actions, stop, and a live
/// preview of the next two weeks' events it would move.
struct RuleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let original: AssignmentRule
    let isNew: Bool
    /// Made from an event: it goes first, so it applies to that event.
    let insertAtTop: Bool
    @State private var name: String
    @State private var match: AssignmentRule.Match
    @State private var conditions: [EditableCondition]
    @State private var actions: [EditableAction]
    @State private var stop: Bool
    @State private var enabled: Bool
    @State private var events: [SourceEvent]?
    @State private var issues: [RulesIssue] = []
    @State private var confirmDelete = false

    init(rule: AssignmentRule, isNew: Bool, insertAtTop: Bool) {
        original = rule
        self.isNew = isNew
        self.insertAtTop = insertAtTop
        _name = State(initialValue: rule.name)
        _match = State(initialValue: rule.match)
        _conditions = State(initialValue: rule.conditions.map { EditableCondition($0) })
        _actions = State(initialValue: rule.actions.isEmpty
            ? [EditableAction(kind: .assignTo)] : rule.actions.map { EditableAction($0) })
        _stop = State(initialValue: rule.stop)
        _enabled = State(initialValue: rule.enabled)
    }

    private var rule: AssignmentRule {
        AssignmentRule(id: original.id, name: name.trimmingCharacters(in: .whitespaces), enabled: enabled,
                       match: match, conditions: conditions.map(\.condition), actions: actions.map(\.action),
                       stop: stop)
    }

    var body: some View {
        NavigationStack {
            if let planner = model.planner {
                form(planner)
                    .editorChrome(isNew ? "New Rule" : "Edit Rule", issues: $issues) { save() }
            }
        }
        .task {
            if events == nil { events = await model.upcomingEvents() }
        }
    }

    private func form(_ planner: DayPlanner) -> some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("rule.name")
                Toggle("On", isOn: $enabled)
            }
            Section {
                ForEach($conditions) { $condition in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("Field", selection: $condition.field) {
                                ForEach(RuleCondition.Field.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            Picker("Comparison", selection: $condition.op) {
                                ForEach(RuleCondition.Op.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            Spacer(minLength: 0)
                        }
                        TextField("Text to match", text: $condition.value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityIdentifier("rule.value")
                    }
                }
                .onDelete { conditions.remove(atOffsets: $0) }
                Button {
                    conditions.append(EditableCondition(RuleCondition(field: .title, op: .contains, value: "")))
                } label: {
                    Label("Add Condition", systemImage: "plus.circle")
                }
            } header: {
                HStack(spacing: 4) {
                    Text("If")
                    Picker("Match", selection: $match) {
                        Text("all").tag(AssignmentRule.Match.all)
                        Text("any").tag(AssignmentRule.Match.any)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    Text("of these are true")
                }
                .textCase(nil)
            } footer: {
                Text("Ignores case and accents, so “serc” matches “SERC”.")
            }
            Section("Then") {
                ForEach($actions) { $action in
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Action", selection: $action.kind) {
                            ForEach(EditableAction.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        switch action.kind {
                        case .assignTo, .alsoInclude:
                            LaneChoice(rules: planner.rules, selection: $action.people)
                        case .importance:
                            Picker("Importance", selection: $action.importance) {
                                ForEach(Importance.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        case .hide:
                            EmptyView()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { actions.remove(atOffsets: $0) }
                Button {
                    actions.append(EditableAction(kind: .alsoInclude))
                } label: {
                    Label("Add Action", systemImage: "plus.circle")
                }
            }
            Section {
                Toggle(isOn: $stop) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stop here")
                        Text("Skip later rules when this one matches")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            RulePreviewSection(planner: planner, rule: rule, events: events)
            if !isNew {
                Section {
                    Button("Delete Rule", role: .destructive) { confirmDelete = true }
                        .frame(maxWidth: .infinity)
                }
                .confirmationDialog("Delete “\(original.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete Rule", role: .destructive, action: delete)
                }
            }
        }
    }

    private func save() {
        guard var rules = model.rules else { return }
        let edited = rule
        if let index = rules.assignmentRules.firstIndex(where: { $0.id == edited.id }) {
            rules.assignmentRules[index] = edited
        } else if insertAtTop {
            rules.assignmentRules.insert(edited, at: 0)
        } else {
            rules.assignmentRules.append(edited)
        }
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }

    private func delete() {
        guard var rules = model.rules else { return }
        rules.assignmentRules.removeAll { $0.id == original.id }
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }
}

/// "Matches 2 events": each with whose lane it's on now and with the rule.
private struct RulePreviewSection: View {
    let planner: DayPlanner
    let rule: AssignmentRule
    let events: [SourceEvent]?

    var body: some View {
        Section {
            if let events {
                let matches = planner.preview(of: rule, events: events)
                Text(matches.count == 1 ? "Matches 1 event" : "Matches \(matches.count) events")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("rule.preview.count")
                if matches.isEmpty {
                    Text("Nothing coming up matches yet. The rule still applies to future events.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(matches.enumerated()), id: \.offset) { _, match in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.event.title).lineLimit(1)
                            Text("\(when(match.event)) · \(match.event.calendarTitle)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(describe(match.before))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                        Text(describe(match.after))
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                    }
                }
            } else {
                ProgressView()
            }
        } header: {
            Text("Preview · next 14 days")
        }
    }

    private func when(_ event: SourceEvent) -> String {
        let date = DisplayFormat.shortDate(planner.clock.localDate(of: event.start))
        return event.isAllDay ? date : "\(date), \(planner.clock.localTime(of: event.start).twelveHour)"
    }

    private func describe(_ assignment: EventAssignment?) -> String {
        guard let assignment else { return "Nobody" }
        if assignment.hidden { return "Hidden" }
        var text = assignment.people.isEmpty ? "Nobody" : planner.names(assignment.people)
        if let importance = assignment.importance, importance != .normal { text += " · \(importance.label)" }
        return text
    }
}

struct EditableCondition: Identifiable {
    let id = UUID()
    var field: RuleCondition.Field
    var op: RuleCondition.Op
    var value: String

    init(_ condition: RuleCondition) {
        field = condition.field
        op = condition.op
        value = condition.value
    }

    var condition: RuleCondition {
        RuleCondition(field: field, op: op, value: value.trimmingCharacters(in: .whitespaces))
    }
}

struct EditableAction: Identifiable {
    enum Kind: CaseIterable {
        case assignTo, alsoInclude, hide, importance

        var label: String {
            switch self {
            case .assignTo: "Assign to"
            case .alsoInclude: "Also include"
            case .hide: "Hide from Today"
            case .importance: "Set importance"
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var people: [PersonID] = []
    var importance: Importance = .high

    init(kind: Kind) {
        self.kind = kind
    }

    init(_ action: RuleAction) {
        switch action {
        case let .assignTo(people):
            kind = .assignTo
            self.people = people
        case let .alsoInclude(people):
            kind = .alsoInclude
            self.people = people
        case .hide:
            kind = .hide
        case let .importance(level):
            kind = .importance
            importance = level
        }
    }

    var action: RuleAction {
        switch kind {
        case .assignTo: .assignTo(people)
        case .alsoInclude: .alsoInclude(people)
        case .hide: .hide
        case .importance: .importance(importance)
        }
    }
}
