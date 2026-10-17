import SwiftUI
import TodayCore

/// The Today look: black background, dark cards, lane colors. Glass is for
/// controls only (the ▶ and Household buttons, the tab picker), per the
/// Liquid Glass guidance MyTeams' GlassUI follows.
enum Theme {
    static let background = Color.black
    static let card = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    static let inset = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    static let track = Color(red: 36 / 255, green: 36 / 255, blue: 38 / 255)
    static let secondary = Color(red: 161 / 255, green: 161 / 255, blue: 166 / 255)
    static let tertiary = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    /// Dark text on a lane-colored avatar or block.
    static let onLane = Color(red: 11 / 255, green: 11 / 255, blue: 12 / 255)
    static let nowLine = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    static let warning = Color(red: 1, green: 159 / 255, blue: 69 / 255)
    static let warningCard = Color(red: 42 / 255, green: 30 / 255, blue: 16 / 255)
    static let warningText = Color(red: 1, green: 226 / 255, blue: 196 / 255)
    static let briefCard = Color(red: 21 / 255, green: 35 / 255, blue: 58 / 255)
    static let briefText = Color(red: 220 / 255, green: 232 / 255, blue: 1)
    static let accentBlue = Color(red: 100 / 255, green: 168 / 255, blue: 1)
    static let rain = Color(red: 143 / 255, green: 203 / 255, blue: 1)
}

extension Color {
    init(_ lane: LaneColor) {
        let rgb = lane.rgb
        self.init(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }

    init?(hex: String?) {
        guard let hex, let lane = LaneColor(hex: hex) else { return nil }
        self.init(lane)
    }
}

/// A rounded dark card.
struct CardBackground: ViewModifier {
    var color: Color = Theme.card
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension View {
    func card(_ color: Color = Theme.card, padding: CGFloat = 16) -> some View {
        modifier(CardBackground(color: color, padding: padding))
    }
}

/// The small uppercase label over a card: "UP NEXT".
struct Eyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.7)
            .foregroundStyle(Theme.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A person's photo, or their initial on their lane color.
struct Avatar: View {
    let initials: String
    let color: LaneColor
    var photo: URL? = nil
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(Color(color))
            Text(initials)
                .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.onLane)
            if let photo, let image = UIImage(contentsOfFile: photo.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A capsule label tinted with a color: the day's status chips.
struct TintChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.16), in: Capsule())
    }
}
