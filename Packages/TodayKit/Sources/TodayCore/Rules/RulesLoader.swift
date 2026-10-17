import Foundation

/// A problem in the rules file, located by its JSON path ("blocks[1].start").
public struct RulesIssue: Sendable, Equatable, CustomStringConvertible {
    public enum Severity: String, Sendable {
        /// The file can't be used; the app keeps the last good rules.
        case error
        /// The file works but is incomplete (placeholders, open todos).
        case warning
    }

    public let severity: Severity
    public let path: String
    public let message: String

    public init(_ severity: Severity, _ path: String, _ message: String) {
        self.severity = severity
        self.path = path
        self.message = message
    }

    public var description: String {
        path.isEmpty ? "\(severity.rawValue): \(message)" : "\(severity.rawValue): \(path): \(message)"
    }
}

public struct RulesError: Error, Sendable, CustomStringConvertible {
    public let issues: [RulesIssue]

    public var description: String {
        issues.map(\.description).joined(separator: "\n")
    }
}

public struct LoadedRules: Sendable {
    public let rules: HouseholdRules
    /// Warnings only; a file with errors doesn't load.
    public let warnings: [RulesIssue]
}

public enum RulesLoader {
    public static func load(_ data: Data) throws(RulesError) -> LoadedRules {
        let rules: HouseholdRules
        do {
            rules = try JSONDecoder().decode(HouseholdRules.self, from: data)
        } catch let error as DecodingError {
            throw RulesError(issues: [issue(for: error)])
        } catch {
            throw RulesError(issues: [RulesIssue(.error, "", "Couldn't read the rules: \(error)")])
        }
        let issues = RulesValidator.validate(rules)
        let errors = issues.filter { $0.severity == .error }
        guard errors.isEmpty else { throw RulesError(issues: errors) }
        return LoadedRules(rules: rules, warnings: issues)
    }

    public static func load(contentsOf url: URL) throws(RulesError) -> LoadedRules {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RulesError(issues: [RulesIssue(.error, "", "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)")])
        }
        return try load(data)
    }

    static func issue(for error: DecodingError) -> RulesIssue {
        switch error {
        case let .keyNotFound(key, context):
            return RulesIssue(.error, path(context.codingPath), "Missing \"\(key.stringValue)\".")
        case let .typeMismatch(type, context):
            return RulesIssue(.error, path(context.codingPath), "Expected \(describe(type)).")
        case let .valueNotFound(type, context):
            return RulesIssue(.error, path(context.codingPath), "Expected \(describe(type)), found null.")
        case let .dataCorrupted(context):
            var message = context.debugDescription
            if let underlying = context.underlyingError {
                message += " \(underlying)"
            }
            return RulesIssue(.error, path(context.codingPath), message)
        @unknown default:
            return RulesIssue(.error, "", "\(error)")
        }
    }

    /// "blocks[1].start" from a coding path.
    static func path(_ codingPath: [any CodingKey]) -> String {
        var result = ""
        for key in codingPath {
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return result
    }

    private static func describe(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: "text in quotes"
        case is Int.Type: "a whole number"
        case is Bool.Type: "true or false"
        case is [Any].Type: "a list [ ... ]"
        default:
            String(describing: type).hasPrefix("Array") ? "a list [ ... ]" : "an object { ... }"
        }
    }
}
