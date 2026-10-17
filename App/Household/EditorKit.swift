import SwiftUI
import TodayCore

/// A wall-clock time picker in the household's zone, never the phone's.
struct TimeField: View {
    let title: String
    @Binding var time: LocalTime
    let clock: HouseholdClock

    /// Any fixed day works: only the hour and minute are read back.
    private static let anchor = LocalDate(year: 2026, month: 1, day: 5)!

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { clock.instant(Self.anchor, time) },
            set: { time = clock.localTime(of: $0) }
        ), displayedComponents: .hourAndMinute)
        .environment(\.timeZone, clock.timeZone)
        .environment(\.calendar, clock.calendar)
    }
}

/// A calendar date picker in the household's zone.
struct DateField: View {
    let title: String
    @Binding var date: LocalDate
    let clock: HouseholdClock

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { clock.instant(date, LocalTime(hour: 12, minute: 0)!) },
            set: { date = clock.localDate(of: $0) }
        ), displayedComponents: .date)
        .environment(\.timeZone, clock.timeZone)
        .environment(\.calendar, clock.calendar)
    }
}

/// Seven day toggles, Monday first.
struct DaysPicker: View {
    @Binding var days: DaySet

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    var set = days.days
                    if on { set.remove(day) } else { set.insert(day) }
                    if !set.isEmpty { days = DaySet(set) }
                } label: {
                    Text(String(day.shortName.prefix(2)))
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(on ? Theme.onLane : .white)
                        .background(on ? Color.white : Theme.inset, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DisplayFormat.weekdayName(day))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// People as avatar chips; tap to include or leave out.
struct PeoplePicker: View {
    let rules: HouseholdRules
    @Binding var selection: [PersonID]
    var only: [PersonGroup]? = nil

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(rules.people.filter { only?.contains($0.group) ?? true }) { person in
                let on = selection.contains(person.id)
                Button {
                    if on {
                        selection.removeAll { $0 == person.id }
                    } else {
                        // Keep the rules' order, so the file reads the same way.
                        let chosen = Set(selection + [person.id])
                        selection = rules.people.map(\.id).filter { chosen.contains($0) }
                    }
                } label: {
                    PersonChip(name: person.name, initials: String(person.name.prefix(1)).uppercased(),
                               color: rules.laneColor(of: person.id), selected: on)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Lanes as chips (the twins are one): for rule actions.
struct LaneChoice: View {
    let rules: HouseholdRules
    @Binding var selection: [PersonID]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(LaneOption.all(rules)) { lane in
                let on = Set(lane.people).isSubset(of: Set(selection))
                Button {
                    var chosen = Set(selection)
                    if on { chosen.subtract(lane.people) } else { chosen.formUnion(lane.people) }
                    selection = rules.people.map(\.id).filter { chosen.contains($0) }
                } label: {
                    PersonChip(name: lane.label, initials: lane.initials, color: lane.color, selected: on)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lane.choice.\(lane.id)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

struct PersonChip: View {
    let name: String
    let initials: String
    let color: LaneColor
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Avatar(initials: initials, color: color, size: 22)
            Text(name).font(.subheadline.weight(.semibold))
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(selected ? Theme.inset.opacity(1.6) : Theme.inset, in: Capsule())
        .overlay(Capsule().stroke(selected ? Color(color) : .clear, lineWidth: 2))
        .opacity(selected ? 1 : 0.7)
    }
}

/// Cancel / Save in the navigation bar and an alert listing what stopped a save.
struct EditorChrome: ViewModifier {
    let title: String
    @Binding var issues: [RulesIssue]
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                        .accessibilityIdentifier("editor.save")
                }
            }
            .alert("Can't save yet", isPresented: Binding(
                get: { !issues.isEmpty }, set: { if !$0 { issues = [] } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(issues.map(\.message).joined(separator: "\n"))
            }
    }
}

extension View {
    func editorChrome(_ title: String, issues: Binding<[RulesIssue]>, onSave: @escaping () -> Void) -> some View {
        modifier(EditorChrome(title: title, issues: issues, onSave: onSave))
    }
}

/// A list row: title over a dimmer detail line, with a color mark.
struct DetailRow: View {
    let title: String
    let detail: String
    var color: Color? = nil
    var detailColor: Color = .secondary

    var body: some View {
        HStack(spacing: 12) {
            if let color {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
