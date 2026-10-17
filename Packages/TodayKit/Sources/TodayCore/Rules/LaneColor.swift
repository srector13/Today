import Foundation

/// A lane color, written "#RRGGBB" in the rules file.
public struct LaneColor: Hashable, Sendable, CustomStringConvertible {
    /// Uppercase "#RRGGBB".
    public let hex: String

    public init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespaces).uppercased()
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        self.hex = "#" + digits
    }

    /// 0...255 channels, for the UI layer to build its own color type.
    public var rgb: (red: Int, green: Int, blue: Int) {
        let value = Int(hex.dropFirst(), radix: 16)!
        return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

    public var description: String { hex }

    /// Colors tuned to read on the dark background, in the order new people
    /// get them.
    public static let palette: [LaneColor] = [
        "#5E9EFF", "#C58CFF", "#FF9F45", "#FF7AB6", "#3FD4C2", "#6AD07A",
        "#FFD34E", "#64C8FF", "#C9E265", "#FF6B5E", "#8E8CFF", "#C2A98A",
    ].map { LaneColor(hex: $0)! }

    public static let paletteNames = [
        "Blue", "Purple", "Orange", "Pink", "Teal", "Green",
        "Yellow", "Sky", "Lime", "Red", "Indigo", "Sand",
    ]
}

extension LaneColor: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let color = LaneColor(hex: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "\"\(raw)\" is not a color. Write it as \"#RRGGBB\", e.g. \"#5E9EFF\"."
            ))
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
