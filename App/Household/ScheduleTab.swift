import SwiftUI
import TodayCore
import UniformTypeIdentifiers

/// Blocks, school calendars, care, the pickup loop, check-ins and the day's
/// settings, plus import and export of household.json.
struct ScheduleTab: View {
    enum Sheet: Identifiable {
        case block(BlockRule, isNew: Bool)
        case school(id: String, SchoolCalendar, isNew: Bool)
        case care(CareRule, isNew: Bool)
        case loop(PickupLoopRule, isNew: Bool)
        case checkIns
        case day

        var id: String {
            switch self {
            case let .block(block, _): "block:\(block.id)"
            case let .school(id, _, _): "school:\(id)"
            case let .care(care, _): "care:\(care.id)"
            case .loop: "loop"
            case .checkIns: "checkIns"
            case .day: "day"
            }
        }
    }

    @Environment(AppModel.self) private var model
    let planner: DayPlanner
    @State private var sheet: Sheet?
    @State private var importing = false
    @State private var issues: [RulesIssue] = []

    private var rules: HouseholdRules { planner.rules }

    var body: some View {
        let text = HouseholdText(planner: planner)
        List {
            Section("Blocks") {
                ForEach(rules.blocks) { block in
                    row(block.title, text.block(block), color: block.who.first) { sheet = .block(block, isNew: false) }
                        .accessibilityIdentifier("schedule.block.\(block.id)")
                }
                addButton("Add Block") {
                    let id = HouseholdRules.uniqueID(from: "block", existing: rules.blocks.map(\.id))
                    sheet = .block(BlockRule(id: id, title: "", kind: .activity, who: [], days: .weekdays,
                                             start: LocalTime(hour: 9, minute: 0)!, end: LocalTime(hour: 10, minute: 0)!),
                                   isNew: true)
                }
            }
            Section("School calendars") {
                ForEach(rules.schoolCalendars.keys.sorted(), id: \.self) { id in
                    let calendar = rules.schoolCalendars[id]!
                    let empty = calendar.noSchool.isEmpty && calendar.earlyRelease.isEmpty
                    row(id.capitalized, text.schoolCalendar(calendar),
                        color: rules.blocks.first { $0.schoolCalendar == id }?.who.first,
                        detailColor: empty ? Theme.warning : .secondary) {
                        sheet = .school(id: id, calendar, isNew: false)
                    }
                }
                addButton("Add School Calendar") {
                    sheet = .school(id: "", SchoolCalendar(), isNew: true)
                }
            }
            Section("Care") {
                ForEach(rules.care) { care in
                    row(care.title ?? "Care", text.care(care), color: care.caregivers.first) {
                        sheet = .care(care, isNew: false)
                    }
                }
                addButton("Add Care") {
                    let id = HouseholdRules.uniqueID(from: "care", existing: rules.care.map(\.id))
                    sheet = .care(CareRule(id: id, caregivers: [], kids: [], days: .weekdays,
                                           from: LocalTime(hour: 8, minute: 0)!, until: .pickupLoop), isNew: true)
                }
            }
            Section("Pickup loop") {
                if let loop = rules.pickupLoop {
                    row(loop.title, text.loop(loop), color: loop.driver) { sheet = .loop(loop, isNew: false) }
                        .accessibilityIdentifier("schedule.loop")
                } else {
                    addButton("Add Pickup Loop") {
                        sheet = .loop(PickupLoopRule(driver: rules.people.first?.id ?? "", days: .weekdays,
                                                     startsAt: .time(LocalTime(hour: 15, minute: 30)!), stops: []),
                                      isNew: true)
                    }
                }
            }
            Section {
                row("Morning · Midday · Pickup", text.checkIns(rules.checkIns), color: nil) { sheet = .checkIns }
                row("Day & home", dayDetail, color: nil) { sheet = .day }
                    .accessibilityIdentifier("schedule.day")
            } header: {
                Text("Check-ins & day")
            }
            Section {
                if let url = model.exportURL() {
                    ShareLink(item: url) {
                        Label("Export household.json", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    importing = true
                } label: {
                    Label("Import household.json…", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Household file")
            } footer: {
                Text("Every change here is saved to household.json. Export sends the file; Import checks it before replacing anything.")
            }
        }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case let .block(block, isNew): BlockEditor(block: block, isNew: isNew)
                case let .school(id, calendar, isNew): SchoolCalendarEditor(id: id, calendar: calendar, isNew: isNew)
                case let .care(care, isNew): CareEditor(care: care, isNew: isNew)
                case let .loop(loop, isNew): LoopEditor(loop: loop, isNew: isNew)
                case .checkIns: CheckInsEditor(checkIns: rules.checkIns)
                case .day: DaySettingsEditor(rules: rules)
                }
            }
            .environment(model)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result {
                issues = model.importRules(from: url)
            }
        }
        .alert("Couldn't import", isPresented: Binding(get: { !issues.isEmpty }, set: { if !$0 { issues = [] } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(issues.map(\.description).joined(separator: "\n"))
        }
    }

    private var dayDetail: String {
        var parts = ["Lanes \(rules.dayWindow.start.twelveHour)–\(rules.dayWindow.end.twelveHour)"]
        parts.append(rules.home.map { "weather for \($0.label ?? "home")" } ?? "no home location for weather")
        parts.append("birthdays \(rules.birthdays.lookaheadDays) days ahead")
        return parts.joined(separator: " · ")
    }

    private func row(_ title: String, _ detail: String, color person: PersonID?, detailColor: Color = .secondary,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                DetailRow(title: title.isEmpty ? "Untitled" : title, detail: detail,
                          color: person.map { Color(rules.laneColor(of: $0)) } ?? Color(white: 0.4),
                          detailColor: detailColor)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus.circle.fill")
        }
    }
}

// MARK: - Editors

struct BlockEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var block: BlockRule
    let isNew: Bool
    @State private var issues: [RulesIssue] = []

    var body: some View {
        NavigationStack {
            if let planner = model.planner {
                Form {
                    Section {
                        TextField("Title", text: $block.title)
                        Picker("Kind", selection: $block.kind) {
                            Text("Work").tag(BlockKind.work)
                            Text("School").tag(BlockKind.school)
                            Text("Activity").tag(BlockKind.activity)
                        }
                    }
                    Section("Who") {
                        PeoplePicker(rules: planner.rules, selection: $block.who)
                    }
                    Section("When") {
                        DaysPicker(days: $block.days)
                        TimeField(title: "Starts", time: $block.start, clock: planner.clock)
                        TimeField(title: "Ends", time: $block.end, clock: planner.clock)
                    }
                    if block.kind == .school {
                        Section {
                            Picker("School calendar", selection: $block.schoolCalendar) {
                                Text("None").tag(String?.none)
                                ForEach(planner.rules.schoolCalendars.keys.sorted(), id: \.self) { id in
                                    Text(id.capitalized).tag(String?.some(id))
                                }
                            }
                        } footer: {
                            Text("Days off, breaks and early releases come from this calendar. A school day is never a free afternoon.")
                        }
                    }
                    if !isNew {
                        Section {
                            Button("Delete Block", role: .destructive) { delete() }
                                .frame(maxWidth: .infinity)
                        } footer: {
                            Text("Rules that use this block (the pickup loop's start, needs) must change first.")
                        }
                    }
                }
                .editorChrome(isNew ? "New Block" : "Edit Block", issues: $issues) { save() }
            }
        }
    }

    private func save() {
        guard var rules = model.rules else { return }
        var edited = block
        edited.title = edited.title.trimmingCharacters(in: .whitespaces)
        if edited.kind != .school { edited.schoolCalendar = nil }
        if let index = rules.blocks.firstIndex(where: { $0.id == block.id }) {
            rules.blocks[index] = edited
        } else {
            rules.blocks.append(edited)
        }
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }

    private func delete() {
        guard var rules = model.rules else { return }
        rules.blocks.removeAll { $0.id == block.id }
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }
}

struct SchoolCalendarEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var id: String
    @State var calendar: SchoolCalendar
    let isNew: Bool
    @State private var issues: [RulesIssue] = []
    @State private var offFrom = LocalDate(year: 2026, month: 11, day: 26)!
    @State private var offTo = LocalDate(year: 2026, month: 11, day: 26)!
    @State private var offLabel = ""
    @State private var earlyDate = LocalDate(year: 2026, month: 12, day: 18)!
    @State private var earlyEnd = LocalTime(hour: 12, minute: 30)!
    @State private var earlyLabel = ""

    var body: some View {
        NavigationStack {
            if let planner = model.planner {
                form(planner.clock)
                    .editorChrome(isNew ? "New School Calendar" : id.capitalized, issues: $issues) { save() }
            }
        }
    }

    private func form(_ clock: HouseholdClock) -> some View {
        Form {
            if isNew {
                Section {
                    TextField("Name, e.g. district", text: $id)
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("School blocks pick a calendar by this name.")
                }
            }
            Section("Term") {
                optionalDate("First day", $calendar.firstDay, clock: clock)
                optionalDate("Last day", $calendar.lastDay, clock: clock)
            }
            Section {
                ForEach(Array(calendar.noSchool.enumerated()), id: \.offset) { _, entry in
                    DetailRow(title: entry.label ?? "Day off", detail: range(entry))
                }
                .onDelete { calendar.noSchool.remove(atOffsets: $0) }
                DateField(title: "From", date: $offFrom, clock: clock)
                DateField(title: "To", date: $offTo, clock: clock)
                TextField("Label (optional)", text: $offLabel)
                Button("Add Days Off") {
                    let to = max(offFrom, offTo)
                    calendar.noSchool.append(NoSchoolDays(from: offFrom, to: to, label: offLabel.isEmpty ? nil : offLabel))
                    calendar.noSchool.sort { $0.from < $1.from }
                    offLabel = ""
                }
            } header: {
                Text("Days off")
            } footer: {
                Text("Holidays, in-service days and breaks. On these days the school block doesn't run and the pickup loop skips the school stop.")
            }
            Section("Early releases") {
                ForEach(Array(calendar.earlyRelease.enumerated()), id: \.offset) { _, release in
                    DetailRow(title: release.label ?? "Early release",
                              detail: "\(DisplayFormat.weekdayShortDate(release.date)) · out at \(release.end.twelveHour)")
                }
                .onDelete { calendar.earlyRelease.remove(atOffsets: $0) }
                DateField(title: "Date", date: $earlyDate, clock: clock)
                TimeField(title: "Lets out", time: $earlyEnd, clock: clock)
                TextField("Label (optional)", text: $earlyLabel)
                Button("Add Early Release") {
                    calendar.earlyRelease.append(EarlyRelease(date: earlyDate, end: earlyEnd,
                                                              label: earlyLabel.isEmpty ? nil : earlyLabel))
                    calendar.earlyRelease.sort { $0.date < $1.date }
                    earlyLabel = ""
                }
            }
            if !isNew {
                Section {
                    Button("Delete School Calendar", role: .destructive) { delete() }
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func optionalDate(_ title: String, _ value: Binding<LocalDate?>, clock: HouseholdClock) -> some View {
        Group {
            Toggle(title, isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { value.wrappedValue = $0 ? (value.wrappedValue ?? clock.localDate(of: model.now)) : nil }
            ))
            if let date = value.wrappedValue {
                DateField(title: "", date: Binding(get: { date }, set: { value.wrappedValue = $0 }), clock: clock)
            }
        }
    }

    private func range(_ entry: NoSchoolDays) -> String {
        entry.from == entry.to
            ? DisplayFormat.weekdayShortDate(entry.from)
            : "\(DisplayFormat.weekdayShortDate(entry.from)) – \(DisplayFormat.weekdayShortDate(entry.to))"
    }

    private func save() {
        guard var rules = model.rules else { return }
        let key = id.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            issues = [RulesIssue(.error, "schoolCalendars", "Give the calendar a name.")]
            return
        }
        if isNew, rules.schoolCalendars[key] != nil {
            issues = [RulesIssue(.error, "schoolCalendars", "There's already a calendar named \(key).")]
            return
        }
        rules.schoolCalendars[key] = calendar
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }

    private func delete() {
        guard var rules = model.rules else { return }
        rules.schoolCalendars[id] = nil
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }
}

struct CareEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var care: CareRule
    let isNew: Bool
    @State private var issues: [RulesIssue] = []

    var body: some View {
        NavigationStack {
            if let planner = model.planner {
                Form {
                    Section {
                        TextField("Title, e.g. With the grandparents", text: Binding(
                            get: { care.title ?? "" },
                            set: { care.title = $0.isEmpty ? nil : $0 }
                        ))
                    }
                    Section("Caregivers") {
                        PeoplePicker(rules: planner.rules, selection: $care.caregivers)
                    }
                    Section("Kids") {
                        PeoplePicker(rules: planner.rules, selection: $care.kids, only: [.kids])
                    }
                    Section {
                        DaysPicker(days: $care.days)
                        TimeField(title: "From", time: $care.from, clock: planner.clock)
                        Picker("Until", selection: Binding(
                            get: { care.until == .pickupLoop },
                            set: { care.until = $0 ? .pickupLoop : .time(LocalTime(hour: 17, minute: 0)!) }
                        )) {
                            Text("The pickup loop").tag(true)
                            Text("A set time").tag(false)
                        }
                        if case let .time(time) = care.until {
                            TimeField(title: "Ends", time: Binding(get: { time }, set: { care.until = .time($0) }),
                                      clock: planner.clock)
                        }
                    } header: {
                        Text("When")
                    } footer: {
                        Text("A kid at school or preschool during these hours is with the school, not the caregivers.")
                    }
                    if !isNew {
                        Section {
                            Button("Delete Care", role: .destructive) { delete() }
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .editorChrome(isNew ? "New Care" : "Edit Care", issues: $issues) { save() }
            }
        }
    }

    private func save() {
        guard var rules = model.rules else { return }
        if let index = rules.care.firstIndex(where: { $0.id == care.id }) {
            rules.care[index] = care
        } else {
            rules.care.append(care)
        }
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }

    private func delete() {
        guard var rules = model.rules else { return }
        rules.care.removeAll { $0.id == care.id }
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }
}

struct LoopEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var loop: PickupLoopRule
    let isNew: Bool
    @State private var stops: [EditableStop] = []
    @State private var started = false
    @State private var issues: [RulesIssue] = []

    var body: some View {
        NavigationStack {
            if let planner = model.planner {
                form(planner)
                    .editorChrome(isNew ? "New Pickup Loop" : "Pickup Loop", issues: $issues) { save() }
            }
        }
        .task {
            guard !started else { return }
            started = true
            stops = loop.stops.map { EditableStop($0) }
        }
    }

    private func form(_ planner: DayPlanner) -> some View {
        let rules = planner.rules
        return Form {
            Section {
                TextField("Title", text: $loop.title)
                Picker("Driver", selection: $loop.driver) {
                    ForEach(rules.people) { person in
                        Text(person.name).tag(person.id)
                    }
                }
                DaysPicker(days: $loop.days)
            }
            Section {
                Picker("Starts", selection: Binding(
                    get: { if case .blockEnd = loop.startsAt { true } else { false } },
                    set: { usesBlock in
                        loop.startsAt = usesBlock
                            ? .blockEnd(rules.blocks.first { $0.kind == .school }?.id ?? rules.blocks.first?.id ?? "")
                            : .time(LocalTime(hour: 15, minute: 30)!)
                    }
                )) {
                    Text("When a block ends").tag(true)
                    Text("At a set time").tag(false)
                }
                switch loop.startsAt {
                case let .blockEnd(id):
                    Picker("Block", selection: Binding(get: { id }, set: { loop.startsAt = .blockEnd($0) })) {
                        ForEach(rules.blocks) { block in
                            Text(block.title).tag(block.id)
                        }
                    }
                    Toggle("Start time without it", isOn: Binding(
                        get: { loop.fallbackStart != nil },
                        set: { loop.fallbackStart = $0 ? (loop.fallbackStart ?? LocalTime(hour: 17, minute: 0)!) : nil }
                    ))
                    if let fallback = loop.fallbackStart {
                        TimeField(title: "On days off", time: Binding(get: { fallback }, set: { loop.fallbackStart = $0 }),
                                  clock: planner.clock)
                    }
                case let .time(time):
                    TimeField(title: "At", time: Binding(get: { time }, set: { loop.startsAt = .time($0) }),
                              clock: planner.clock)
                }
                Stepper("\(loop.minutesBetweenStops) min between stops", value: $loop.minutesBetweenStops, in: 0...90, step: 5)
                Stepper("\(loop.minutesToHome) min to home", value: $loop.minutesToHome, in: 0...90, step: 5)
            } header: {
                Text("Timing")
            } footer: {
                Text("Drive times are estimates; Today doesn't look up traffic.")
            }
            ForEach($stops) { $stop in
                Section {
                    TextField("Place", text: $stop.place)
                    PeoplePicker(rules: rules, selection: $stop.collect, only: [.kids])
                    Picker("Only when", selection: $stop.onlyWhen) {
                        Text("Every loop").tag(String?.none)
                        ForEach(rules.blocks) { block in
                            Text("\(block.title) runs").tag(String?.some(block.id))
                        }
                    }
                    Button("Remove Stop", role: .destructive) {
                        stops.removeAll { $0.id == stop.id }
                    }
                } header: {
                    Text("Stop")
                }
            }
            Section {
                Button {
                    stops.append(EditableStop(LoopStop(place: "", collect: [])))
                } label: {
                    Label("Add Stop", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Stops run in order, then home. A stop that only happens when school runs is skipped on days off.")
            }
            if !isNew {
                Section {
                    Button("Remove Pickup Loop", role: .destructive) { remove() }
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func save() {
        guard var rules = model.rules else { return }
        var edited = loop
        edited.stops = stops.map(\.stop)
        rules.pickupLoop = edited
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }

    private func remove() {
        guard var rules = model.rules else { return }
        rules.pickupLoop = nil
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }
}

struct EditableStop: Identifiable {
    let id = UUID()
    var place: String
    var collect: [PersonID]
    var onlyWhen: String?

    init(_ stop: LoopStop) {
        place = stop.place
        collect = stop.collect
        onlyWhen = stop.onlyWhen
    }

    var stop: LoopStop {
        LoopStop(place: place.trimmingCharacters(in: .whitespaces), collect: collect, onlyWhen: onlyWhen)
    }
}

struct CheckInsEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var checkIns: [CheckInRule]
    @State private var issues: [RulesIssue] = []

    var body: some View {
        NavigationStack {
            if let planner = model.planner {
                Form {
                    ForEach(CheckInKind.allCases, id: \.self) { kind in
                        Section(title(kind)) {
                            TimeField(title: "At", time: binding(kind).at, clock: planner.clock)
                            Toggle("Time Sensitive", isOn: binding(kind).timeSensitive)
                        }
                    }
                    Section {
                    } footer: {
                        Text("These times pick which brief ▶ reads (morning, midday or pickup). The check-in notifications themselves arrive in a later update.")
                    }
                }
                .editorChrome("Check-ins", issues: $issues) { save() }
            }
        }
    }

    private func title(_ kind: CheckInKind) -> String {
        switch kind {
        case .morning: "Morning"
        case .midday: "Midday"
        case .afternoon: "Pickup"
        }
    }

    private func binding(_ kind: CheckInKind) -> Binding<CheckInRule> {
        Binding(
            get: {
                checkIns.first { $0.kind == kind }
                    ?? CheckInRule.defaults.first { $0.kind == kind }!
            },
            set: { value in
                if let index = checkIns.firstIndex(where: { $0.kind == kind }) {
                    checkIns[index] = value
                } else {
                    checkIns.append(value)
                    checkIns.sort { $0.at < $1.at }
                }
            }
        )
    }

    private func save() {
        guard var rules = model.rules else { return }
        rules.checkIns = CheckInKind.allCases.compactMap { kind in checkIns.first { $0.kind == kind } }
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }
}

struct DaySettingsEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var rules: HouseholdRules
    @State private var issues: [RulesIssue] = []
    @State private var locating = false
    @State private var locationError: String?

    var body: some View {
        NavigationStack {
            if let planner = model.planner {
                Form {
                    Section {
                        TimeField(title: "Lanes start", time: $rules.dayWindow.start, clock: planner.clock)
                        TimeField(title: "Lanes end", time: $rules.dayWindow.end, clock: planner.clock)
                    } footer: {
                        Text("The hours the lanes draw. Times are always \(rules.timeZone) time.")
                    }
                    Section {
                        if let home = rules.home {
                            LabeledContent(home.label ?? "Home",
                                           value: String(format: "%.3f, %.3f", home.latitude, home.longitude))
                        }
                        Button {
                            locate()
                        } label: {
                            Label(locating ? "Finding this iPhone…" : "Use Current Location", systemImage: "location.fill")
                        }
                        .disabled(locating)
                        if rules.home != nil {
                            Button("Remove Home Location", role: .destructive) { rules.home = nil }
                        }
                        if let locationError {
                            Text(locationError).font(.footnote).foregroundStyle(Theme.warning)
                        }
                    } header: {
                        Text("Home, for the weather")
                    } footer: {
                        Text("Rounded to about 100 m and kept only in household.json, for the forecast.")
                    }
                    Section("Birthdays") {
                        Stepper("Look \(rules.birthdays.lookaheadDays) days ahead",
                                value: $rules.birthdays.lookaheadDays, in: 1...366)
                    }
                }
                .editorChrome("Day & Home", issues: $issues) { save() }
            }
        }
    }

    private func locate() {
        locating = true
        locationError = nil
        Task {
            do {
                let fix = try await LocationFinder.current()
                rules.home = .rounded(latitude: fix.latitude, longitude: fix.longitude, label: "Home")
            } catch {
                locationError = error.localizedDescription
            }
            locating = false
        }
    }

    private func save() {
        guard var current = model.rules else { return }
        current.dayWindow = rules.dayWindow
        current.home = rules.home
        current.birthdays = rules.birthdays
        issues = model.save(current)
        if issues.isEmpty { dismiss() }
    }
}
