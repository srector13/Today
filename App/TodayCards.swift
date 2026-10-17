import SwiftUI
import TodayCore

// MARK: - Up next

struct UpNextCard: View {
    @Environment(AppModel.self) private var model
    let plan: DayPlan
    let planner: DayPlanner
    let now: Date
    let weather: WeatherSnapshot?
    let onSelect: (TimelineItem) -> Void

    var body: some View {
        if let next = NextUp.find(in: plan, now: now) {
            Button {
                onSelect(next.item)
            } label: {
                content(next)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Up next")
                Text("Nothing else on the calendars this iPhone can see.")
                    .font(.headline)
                    .accessibilityIdentifier("upnext.title")
            }
            .card(padding: 16)
        }
    }

    private func content(_ next: NextUp) -> some View {
        let color = planner.rules.laneColor(of: next.loop?.driver ?? next.item.people.first ?? "")
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow("Up next")
                Spacer()
                if let hint = rainHint(next) {
                    Label(hint, systemImage: "cloud.rain.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.rain)
                }
            }
            HStack(spacing: 12) {
                Image(systemName: Self.symbol(for: next.item))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.onLane)
                    .frame(width: 44, height: 44)
                    .background(Color(color), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.item.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("upnext.title")
                    Text(next.subtitle(planner: planner, now: now))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
            }
            if let loop = next.loop {
                LoopStops(loop: loop, plan: plan)
            }
        }
        .card(padding: 16)
        .contentShape(Rectangle())
    }

    private func rainHint(_ next: NextUp) -> String? {
        guard let weather,
              let chance = weather.rainChance(from: next.item.start, through: next.item.end),
              chance >= WeatherSnapshot.likely else { return nil }
        return next.loop != nil ? "Rain likely at pickup" : "Rain likely"
    }

    static func symbol(for item: TimelineItem) -> String {
        switch item.kind {
        case .pickupLoop: "car.fill"
        case .school: "backpack.fill"
        case .work: "briefcase.fill"
        case .care: "house.fill"
        case .activity: "figure.run"
        case .appointment: "calendar"
        }
    }
}

/// The loop's stops in order, then home: "3:30 School (E)", "3:45 Grandparents' (N T)", "~4:00 Home".
private struct LoopStops: View {
    let loop: PickupLoopPlan
    let plan: DayPlan

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(loop.stops.enumerated()), id: \.offset) { _, stop in
                tile(time: stop.time.short, place: stop.place) {
                    HStack(spacing: 4) {
                        ForEach(lanes(for: stop.kids)) { lane in
                            Avatar(initials: lane.initials, color: lane.color, size: 24)
                        }
                    }
                }
            }
            tile(time: "~\(loop.end.short)", place: "Home") {
                Image(systemName: "house")
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
                    .frame(height: 24)
            }
        }
    }

    private func tile(time: String, place: String, @ViewBuilder who: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(time).font(.footnote.bold()).foregroundStyle(.white)
            Text(place).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
            who()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// One avatar per lane: the twins are one "T".
    private func lanes(for kids: [PersonID]) -> [Lane] {
        plan.lanes.filter { !Set($0.people).isDisjoint(with: kids) }
    }
}

// MARK: - Lanes

struct LanesCard: View {
    @Environment(AppModel.self) private var model
    let plan: DayPlan
    let window: TimelineWindow
    let now: Date
    let onSelect: (TimelineItem) -> Void

    static let labelWidth: CGFloat = 60
    static let barHeight: CGFloat = 44

    var body: some View {
        let marks = window.hourMarks(clock: plan.clock)
        let nowFraction: Double? = window.contains(now) ? window.fraction(now) : nil
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.labelWidth, height: 1)
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        // Marks under the "now" pill would collide with it.
                        ForEach(marks.filter { mark in
                            nowFraction.map { abs($0 - mark.fraction) * geo.size.width > 26 } ?? true
                        }) { mark in
                            Text(mark.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.tertiary)
                                .fixedSize()
                                .position(x: geo.size.width * mark.fraction, y: 11)
                        }
                        if let nowFraction {
                            Text(plan.clock.localTime(of: now).short)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.nowLine, in: Capsule())
                                .fixedSize()
                                .position(x: geo.size.width * nowFraction, y: 11)
                        }
                    }
                }
                .frame(height: 22)
            }
            .accessibilityHidden(true)

            ForEach(plan.laneGroups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.group.title.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.secondary)
                        .padding(.leading, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.lanes) { lane in
                        LaneRow(lane: lane, window: window, marks: marks, nowFraction: nowFraction,
                                photo: model.photoURL(lane.photo), clock: plan.clock, onSelect: onSelect)
                    }
                }
                .padding(.top, 10)
            }

            let allDay = plan.items.filter(\.isAllDay)
            if !allDay.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(allDay) { item in
                        Button { onSelect(item) } label: {
                            TintChip(text: "All day · \(item.title)", color: Color(laneColor(item)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
            }
            if !plan.hiddenItems.isEmpty {
                HiddenItemsLink(items: plan.hiddenItems, onSelect: onSelect)
                    .padding(.top, 10)
            }
        }
        .card(padding: 12)
    }

    private func laneColor(_ item: TimelineItem) -> LaneColor {
        plan.lanes.first { !Set($0.people).isDisjoint(with: item.people) }?.color ?? LaneColor.palette[0]
    }
}

private struct LaneRow: View {
    let lane: Lane
    let window: TimelineWindow
    let marks: [TimelineWindow.HourMark]
    let nowFraction: Double?
    let photo: URL?
    let clock: HouseholdClock
    let onSelect: (TimelineItem) -> Void

    var body: some View {
        let blocks = LaneLayout.blocks(for: lane, in: window)
        let color = Color(lane.color)
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Avatar(initials: lane.initials, color: lane.color, photo: photo, size: 28)
                Text(lane.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(white: 0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: LanesCard.labelWidth)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(lane.data.isKnown ? lane.label : "\(lane.label), no data")

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.track)
                    ForEach(marks.dropFirst().dropLast()) { mark in
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 1, height: LanesCard.barHeight)
                            .offset(x: width * mark.fraction)
                    }
                    if case .noData = lane.data {
                        Hatch()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        if blocks.isEmpty {
                            Text("No data · calendar not on this iPhone")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(white: 0.78))
                                .frame(width: width, height: LanesCard.barHeight)
                                .accessibilityIdentifier("lane.nodata.\(lane.label)")
                        } else if blocks.allSatisfy({ $0.style == .background }) {
                            // Work or school from the rules is still known; say
                            // "no data" after it rather than over it.
                            Text("No data")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(white: 0.78))
                                .padding(.trailing, 10)
                                .frame(width: width, height: LanesCard.barHeight, alignment: .trailing)
                                .accessibilityIdentifier("lane.nodata.\(lane.label)")
                        }
                    }
                    ForEach(blocks) { block in
                        BlockView(block: block, color: color, width: width, laneLabel: lane.label, clock: clock)
                            .onTapGesture { onSelect(block.item) }
                    }
                    if let nowFraction {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.nowLine)
                            .frame(width: 2, height: LanesCard.barHeight + 6)
                            .offset(x: width * nowFraction - 1, y: -3)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(height: LanesCard.barHeight)
        }
        .frame(height: 48)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lane.\(lane.label)")
    }
}

private struct BlockView: View {
    let block: LaneBlock
    let color: Color
    let width: CGFloat
    let laneLabel: String
    let clock: HouseholdClock

    var body: some View {
        let x = width * block.start
        let w = max(width * (block.end - block.start), 4)
        let size = frame
        Text(w >= 28 ? label : "")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(width: w, height: size.height, alignment: .leading)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: block.style == .background ? 10 : 8, style: .continuous))
            .clipped()
            .contentShape(Rectangle())
            .offset(x: x, y: size.y)
            .accessibilityElement()
            .accessibilityLabel("\(laneLabel): \(block.item.title), \(clock.localTime(of: block.item.start).twelveHour) to \(clock.localTime(of: block.item.end).twelveHour)")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("block.\(block.item.id)")
    }

    private var frame: (y: CGFloat, height: CGFloat) {
        switch (block.style, block.rows) {
        case (.background, _): return (0, LanesCard.barHeight)
        case (_, 1): return (6, 32)
        default:
            let rows = CGFloat(block.rows)
            let height = (36 - (rows - 1) * 2) / rows
            return (4 + CGFloat(block.row) * (height + 2), height)
        }
    }

    private var label: String {
        if block.item.id.hasPrefix("loop:") { return "Ride" }
        return block.item.title
    }

    private var background: Color {
        switch block.style {
        case .background: color.opacity(0.15)
        case .normal: color.opacity(0.38)
        case .high: color
        }
    }

    private var foreground: Color {
        switch block.style {
        case .background: color
        case .normal: .white
        case .high: Theme.onLane
        }
    }
}

/// Diagonal stripes: "we can't see this lane", never "free".
private struct Hatch: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 11
            }
            context.stroke(path, with: .color(.white.opacity(0.09)), lineWidth: 5)
        }
        .accessibilityHidden(true)
    }
}

private struct HiddenItemsLink: View {
    let items: [TimelineItem]
    let onSelect: (TimelineItem) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                Label("\(items.count) event\(items.count == 1 ? "" : "s") hidden by rules",
                      systemImage: expanded ? "eye" : "eye.slash")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hidden.toggle")
            if expanded {
                ForEach(items) { item in
                    Button { onSelect(item) } label: {
                        Text(item.title)
                            .font(.footnote)
                            .foregroundStyle(Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Weather

struct WeatherCard: View {
    @Environment(AppModel.self) private var model
    @State private var locating = false
    @State private var locationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Weather")
            if let weather = model.weather, let planner = model.planner {
                HStack {
                    HStack(spacing: 12) {
                        Text("\(weather.temperature)°")
                            .font(.system(size: 48, weight: .light))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(weather.condition).font(.headline)
                            Text("H \(weather.high)°  L \(weather.low)°")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: weather.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 36))
                        .accessibilityHidden(true)
                }
                HStack(spacing: 6) {
                    ForEach(weather.hours(from: model.now, count: 5)) { hour in
                        let wet = hour.precipitationChance >= WeatherSnapshot.likely
                        VStack(spacing: 4) {
                            Text(DisplayFormat.hourMark(planner.clock.localTime(of: hour.time).hour, first: true))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.secondary)
                            Text("\(hour.temperature)°")
                                .font(.callout.weight(.semibold))
                            Text(WeatherSnapshot.percent(hour.precipitationChance))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(wet ? Theme.rain : Theme.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(wet ? Theme.rain.opacity(0.14) : Theme.track,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
                HStack(spacing: 4) {
                    Text("\u{F8FF} Weather ·")
                    Link("Data sources", destination: model.weatherLegalPage ?? WeatherLoader.fallbackLegalPage)
                }
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
            } else {
                switch model.weatherState {
                case .needsHome:
                    Text("Add your home location to see the forecast here and in the brief.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                    Button {
                        locating = true
                        Task {
                            locationError = await model.useCurrentLocationForHome()
                            locating = false
                        }
                    } label: {
                        Label(locating ? "Finding this iPhone…" : "Use Current Location", systemImage: "location.fill")
                    }
                    .buttonStyle(.glass)
                    .disabled(locating)
                    if let locationError {
                        Text(locationError).font(.footnote).foregroundStyle(Theme.warning)
                    }
                case let .unavailable(reason):
                    Text("Weather isn't available right now.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                default:
                    ProgressView()
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weather.card")
    }
}

// MARK: - Needs and birthdays

struct NeedsCard: View {
    @Environment(AppModel.self) private var model
    let plan: DayPlan
    let planner: DayPlanner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("What the kids need")
            ForEach(Array(plan.needs.enumerated()), id: \.offset) { _, need in
                let lane = plan.lanes.first { !Set($0.people).isDisjoint(with: need.people) }
                let color = lane?.color ?? planner.rules.laneColor(of: need.people.first ?? "")
                HStack(alignment: .top, spacing: 12) {
                    Avatar(initials: lane?.initials ?? "?", color: color, photo: model.photoURL(lane?.photo), size: 32)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(planner.names(need.people))
                            .font(.subheadline.weight(.semibold))
                        FlowLayout(spacing: 6) {
                            ForEach(need.items, id: \.self) { item in
                                NeedChip(item: item, key: KidNeed.key(people: need.people, item: item), color: Color(color))
                            }
                        }
                    }
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("needs.card")
    }
}

private struct NeedChip: View {
    @Environment(AppModel.self) private var model
    let item: String
    let key: String
    let color: Color

    var body: some View {
        let done = model.doneNeeds.contains(key)
        Button {
            model.toggleNeed(key)
        } label: {
            HStack(spacing: 6) {
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.heavy))
                }
                Text(item)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(done ? color : .white)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(done ? color.opacity(0.22) : Theme.inset, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(done ? .isSelected : [])
    }
}

struct BirthdaysCard: View {
    @Environment(AppModel.self) private var model
    let plan: DayPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Birthdays")
            ForEach(Array(plan.birthdays.enumerated()), id: \.offset) { index, birthday in
                if index > 0 {
                    Divider()
                }
                HStack(spacing: 12) {
                    icon(birthday)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(birthday.turning.map { "\(birthday.name) turn\(birthday.name.contains(" & ") ? "" : "s") \($0)" } ?? birthday.name)
                            .font(.subheadline.weight(.semibold))
                        Text(DisplayFormat.weekdayShortDate(birthday.date))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Text(DisplayFormat.relativeDays(birthday.daysAway))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(birthday.daysAway <= 7 ? Color(LaneColor(hex: "#FF9CC8")!) : Theme.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("birthdays.card")
    }

    @ViewBuilder
    private func icon(_ birthday: UpcomingBirthday) -> some View {
        if let id = birthday.person, let lane = plan.lanes.first(where: { $0.people.contains(id) }) {
            Avatar(initials: lane.initials, color: lane.color, photo: model.photoURL(lane.photo), size: 36)
        } else {
            let pink = Color(LaneColor(hex: "#FF7AB6")!)
            Image(systemName: "gift.fill")
                .foregroundStyle(pink)
                .frame(width: 36, height: 36)
                .background(pink.opacity(0.18), in: Circle())
                .accessibilityHidden(true)
        }
    }
}
