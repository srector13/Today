import Foundation

/// Finds the people a calendar title names: "Dentist - Emma", "Emma's
/// dentist", "Haircut (Nora & Leo)", "Papa golf".
///
/// Matching is on whole words, ignoring case and accents, so "Al" never
/// matches "Almond" and "Zoe" matches "Zoë". A name or alias of several words
/// ("Grandma Jo") must appear as that run of words. When two people share an
/// alias ("Twins"), the title names both.
public struct TitleAttributor: Sendable {
    private struct Pattern: Sendable {
        let words: [String]
        let people: [PersonID]
    }

    /// Longest first, so "Grandma Jo" wins over "Grandma" at the same spot.
    private let patterns: [Pattern]

    public init(people: [Person]) {
        var owners: [[String]: [PersonID]] = [:]
        var order: [[String]] = []
        for person in people {
            for name in [person.name] + person.aliases where !Self.isPlaceholder(name) {
                let words = Self.words(in: name)
                guard !words.isEmpty else { continue }
                if owners[words] == nil {
                    order.append(words)
                }
                if owners[words, default: []].contains(person.id) == false {
                    owners[words, default: []].append(person.id)
                }
            }
        }
        patterns = order.enumerated()
            .sorted { ($0.element.count, -$0.offset) > ($1.element.count, -$1.offset) }
            .map { Pattern(words: $0.element, people: owners[$0.element]!) }
    }

    /// The people named in `title`, in the order they first appear.
    public func people(namedIn title: String) -> [PersonID] {
        let words = Self.words(in: title)
        var found: [PersonID] = []
        var i = 0
        while i < words.count {
            let match = patterns.first { pattern in
                i + pattern.words.count <= words.count
                    && Array(words[i..<(i + pattern.words.count)]) == pattern.words
            }
            guard let match else {
                i += 1
                continue
            }
            for id in match.people where !found.contains(id) {
                found.append(id)
            }
            i += match.words.count
        }
        return found
    }

    /// Lowercased, accent-free words; apostrophes split, so "Emma's" holds "emma".
    static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    static func isPlaceholder(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("<") && trimmed.hasSuffix(">")
    }
}
