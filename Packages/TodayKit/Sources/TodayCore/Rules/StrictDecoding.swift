import Foundation

/// A coding key for any string, used to see every key an object holds.
struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Decoder {
    /// Throws when the object holds a key the type doesn't define.
    ///
    /// `Decodable` ignores unknown keys, so a misspelt optional key
    /// ("fallbakStart") would silently fall back to its default. The rules
    /// file is hand-edited, so every rules type calls this first.
    func rejectUnknownKeys<Keys: CodingKey & CaseIterable>(_: Keys.Type, also extra: Set<String> = []) throws {
        let container = try container(keyedBy: AnyCodingKey.self)
        let known = Set(Keys.allCases.map(\.stringValue)).union(extra)
        let unknown = container.allKeys.map(\.stringValue).sorted().first { !known.contains($0) }
        guard let unknown else { return }
        var message = "Unknown key \"\(unknown)\"."
        if let guess = closestMatch(to: unknown, in: known) {
            message += " Did you mean \"\(guess)\"?"
        } else {
            message += " Known keys: \(known.sorted().joined(separator: ", "))."
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: codingPath + [AnyCodingKey(stringValue: unknown)],
            debugDescription: message
        ))
    }
}

/// The known key nearest `word` by edit distance, when it's a plausible typo.
func closestMatch(to word: String, in candidates: Set<String>) -> String? {
    let scored = candidates.map { ($0, editDistance(word.lowercased(), $0.lowercased())) }
    guard let best = scored.min(by: { ($0.1, $0.0) < ($1.1, $1.0) }) else { return nil }
    return best.1 <= max(2, word.count / 3) ? best.0 : nil
}

func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    guard !a.isEmpty else { return b.count }
    guard !b.isEmpty else { return a.count }
    var previous = Array(0...b.count)
    for i in 1...a.count {
        var current = [i] + Array(repeating: 0, count: b.count)
        for j in 1...b.count {
            current[j] = min(
                previous[j] + 1,
                current[j - 1] + 1,
                previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
            )
        }
        previous = current
    }
    return previous[b.count]
}
