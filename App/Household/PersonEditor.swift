import PhotosUI
import SwiftUI
import TodayCore

/// A person: photo, name, lane color, group, the other names titles use
/// for them, a shared lane, birthday and their own calendar.
struct PersonEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var person: Person
    let isNew: Bool
    @State private var issues: [RulesIssue] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var newPhoto: Data?
    @State private var photoRemoved = false
    @State private var newAlias = ""
    @State private var calendar: String?
    @State private var originalCalendar: String?
    @State private var started = false
    @State private var confirmRemove = false

    init(person: Person, isNew: Bool) {
        _person = State(initialValue: person)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            if let planner = model.planner {
                form(planner)
                    .editorChrome(isNew ? "New Person" : "Edit Person", issues: $issues) { save() }
            }
        }
        .task {
            guard !started else { return }
            started = true
            calendar = model.rules?.personalCalendar(of: person.id)
            originalCalendar = calendar
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let jpeg = Self.squareJPEG(data) {
                    newPhoto = jpeg
                    photoRemoved = false
                }
            }
        }
    }

    private func form(_ planner: DayPlanner) -> some View {
        let color = person.color ?? planner.rules.laneColor(of: person.id)
        let initials = String(person.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        return Form {
            Section {
                VStack(spacing: 12) {
                    photoView(initials: initials.isEmpty ? "?" : initials, color: color)
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(hasPhoto ? "Change Photo" : "Choose Photo")
                        }
                        .buttonStyle(.glass)
                        if hasPhoto {
                            Button("Remove", role: .destructive) {
                                newPhoto = nil
                                photoRemoved = true
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                TextField("Name", text: $person.name)
                    .textContentType(.name)
                    .accessibilityIdentifier("person.name")
            } footer: {
                Text("Shown on their lane, and matched in calendar titles.")
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                    ForEach(Array(LaneColor.palette.enumerated()), id: \.offset) { index, swatch in
                        let selected = swatch == color
                        Button {
                            person.color = swatch
                        } label: {
                            Circle()
                                .fill(Color(swatch))
                                .frame(width: 34, height: 34)
                                .padding(3)
                                .overlay(Circle().stroke(selected ? Color(swatch) : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LaneColor.paletteNames[index] + (selected ? ", selected" : ""))
                    }
                }
                .padding(.vertical, 6)
                LanePreview(name: person.laneLabel.isEmpty ? "Name" : person.laneLabel, initials: initials, color: color)
            } header: {
                Text("Lane color")
            } footer: {
                Text("A preview of their lane. The colors are tuned to stay readable on the dark background.")
            }
            Section("Group") {
                Picker("Group", selection: $person.group) {
                    ForEach(PersonGroup.allCases, id: \.self) { group in
                        Text(group.title).tag(group)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section {
                ForEach(person.aliases, id: \.self) { alias in
                    Text(alias)
                }
                .onDelete { person.aliases.remove(atOffsets: $0) }
                HStack {
                    TextField("Add a name", text: $newAlias)
                        .onSubmit(addAlias)
                    Button("Add", action: addAlias)
                        .disabled(newAlias.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Also matches in titles")
            } footer: {
                Text("“\(person.aliases.first ?? "Em")'s dentist” on a shared calendar lands on this lane. Whole words only.")
            }
            Section {
                TextField("Shares a lane named", text: Binding(
                    get: { person.lane ?? "" },
                    set: { person.lane = $0.isEmpty ? nil : $0 }
                ))
                Toggle("Birthday", isOn: Binding(
                    get: { person.birthDate != nil },
                    set: { person.birthDate = $0 ? (person.birthDate ?? planner.clock.localDate(of: model.now)) : nil }
                ))
                if let birthDate = person.birthDate {
                    DateField(title: "Born", date: Binding(get: { birthDate }, set: { person.birthDate = $0 }),
                              clock: planner.clock)
                }
                Picker("Their calendar", selection: $calendar) {
                    Text("None").tag(String?.none)
                    ForEach(calendarChoices(planner), id: \.self) { title in
                        Text(title).tag(String?.some(title))
                    }
                }
            } footer: {
                Text("People with the same lane name share one row, like the twins. Events on their own calendar are theirs. Calendars several people share are set up under Calendars.")
            }
            if !isNew {
                Section {
                    Button("Remove from Household", role: .destructive) { confirmRemove = true }
                        .frame(maxWidth: .infinity)
                }
                .confirmationDialog(removeMessage(planner), isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button("Remove \(person.name)", role: .destructive, action: remove)
                }
            }
        }
    }

    private var hasPhoto: Bool {
        newPhoto != nil || (person.photo != nil && !photoRemoved)
    }

    @ViewBuilder
    private func photoView(initials: String, color: LaneColor) -> some View {
        if let newPhoto, let image = UIImage(data: newPhoto) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
        } else {
            Avatar(initials: initials, color: color,
                   photo: photoRemoved ? nil : model.photoURL(person.photo), size: 96)
        }
    }

    private func calendarChoices(_ planner: DayPlanner) -> [String] {
        var titles = model.deviceCalendars.filter { !$0.isBirthdays }.map(\.title)
        if let calendar, !titles.contains(calendar) { titles.append(calendar) }
        return titles
    }

    private func removeMessage(_ planner: DayPlanner) -> String {
        let refs = planner.rules.references(to: person.id)
        guard !refs.isEmpty else { return "Remove \(person.name) from the household?" }
        return "\(person.name) is also in \(DayPlanner.list(refs)). Removing them takes them out of those too."
    }

    private func addAlias() {
        let alias = newAlias.trimmingCharacters(in: .whitespaces)
        guard !alias.isEmpty, !person.aliases.contains(alias) else { return }
        person.aliases.append(alias)
        newAlias = ""
    }

    private func save() {
        guard var rules = model.rules else { return }
        var edited = person
        edited.name = edited.name.trimmingCharacters(in: .whitespaces)
        edited.lane = edited.lane?.trimmingCharacters(in: .whitespaces)
        if edited.lane?.isEmpty == true { edited.lane = nil }
        if isNew {
            edited.id = HouseholdRules.uniqueID(from: edited.name, existing: rules.people.map(\.id))
        }
        if let newPhoto, let file = model.savePhoto(newPhoto, for: edited.id) {
            edited.photo = file
        } else if photoRemoved {
            edited.photo = nil
        }
        if isNew {
            rules.people.append(edited)
        } else if let index = rules.people.firstIndex(where: { $0.id == person.id }) {
            rules.people[index] = edited
        }
        if calendar != originalCalendar || isNew {
            rules.setPersonalCalendar(calendar, for: edited.id)
        }
        issues = model.save(rules)
        if issues.isEmpty { dismiss() }
    }

    private func remove() {
        guard var rules = model.rules else { return }
        rules.removePerson(person.id)
        issues = model.save(rules)
        guard issues.isEmpty else { return }
        model.forgetPicks(of: person.id)
        dismiss()
    }

    /// A centered square crop, 512 px, as JPEG.
    static func squareJPEG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let side: CGFloat = 512
        let scale = side / min(image.size.width, image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }
        return square.jpegData(compressionQuality: 0.85)
    }
}

/// A sample lane in the chosen color: backdrop, normal and important blocks.
private struct LanePreview: View {
    let name: String
    let initials: String
    let color: LaneColor

    var body: some View {
        let tint = Color(color)
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Avatar(initials: initials.isEmpty ? "?" : initials, color: color, size: 28)
                Text(name).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .frame(width: 56)
            HStack(spacing: 4) {
                Text("School")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 7)
                    .foregroundStyle(tint)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                Text("Ride")
                    .frame(width: 54, height: 32, alignment: .leading)
                    .padding(.horizontal, 7)
                    .foregroundStyle(.white)
                    .background(tint.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
                Text("Swim")
                    .frame(width: 54, height: 32, alignment: .leading)
                    .padding(.horizontal, 7)
                    .foregroundStyle(Theme.onLane)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8))
            }
            .font(.caption.weight(.semibold))
            .frame(height: 44)
            .padding(4)
            .background(Theme.track, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityHidden(true)
    }
}
