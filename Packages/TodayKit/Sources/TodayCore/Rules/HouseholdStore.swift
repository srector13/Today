import Foundation

/// The household's rules as a file the app owns, in the App Group container
/// so the widget reads the same rules the app edits.
///
/// - The bundled `Rules/household.json` seeds it the first time.
/// - A newer bundled file (you edited the repo and rebuilt) is adopted
///   automatically if nobody edited the rules in the app since the last
///   seed; otherwise the in-app version stays and `bundledUpdateAvailable`
///   says the new bundled file can be imported.
/// - Every good load or save also writes a last-good copy. If the saved file
///   is ever unusable, the last good copy loads instead and says why.
/// - Import validates before replacing anything.
public struct HouseholdStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var rulesURL: URL { directory.appendingPathComponent("household.json") }
    var lastGoodURL: URL { directory.appendingPathComponent("household.last-good.json") }
    /// The bundled file as it was when it last seeded the store.
    var seedURL: URL { directory.appendingPathComponent("household.seed.json") }
    public var photosDirectory: URL { directory.appendingPathComponent("Photos", isDirectory: true) }

    public struct Loaded: Sendable {
        public let rules: HouseholdRules
        public let warnings: [RulesIssue]
        /// The saved file was unusable; these rules are the last good copy.
        public let recoveredFrom: RulesError?
        /// The bundled file changed, but the rules were edited in the app, so
        /// the bundled version wasn't adopted. Offer to import it.
        public let bundledUpdateAvailable: Bool
    }

    /// The saved rules, seeding or upgrading from `bundled` as described above.
    public func load(bundled: Data) throws(RulesError) -> Loaded {
        try ensureDirectory()
        let fm = FileManager.default
        guard fm.fileExists(atPath: rulesURL.path) else {
            let loaded = try RulesLoader.load(bundled)
            try write(bundled, to: rulesURL)
            try write(bundled, to: seedURL)
            try write(bundled, to: lastGoodURL)
            return Loaded(rules: loaded.rules, warnings: loaded.warnings, recoveredFrom: nil, bundledUpdateAvailable: false)
        }

        let current = try read(rulesURL)
        let lastSeed = fm.fileExists(atPath: seedURL.path) ? try read(seedURL) : nil
        var bundledUpdateAvailable = false
        if bundled != lastSeed {
            if current == lastSeed, (try? RulesLoader.load(bundled)) != nil {
                // Untouched since the last seed: take the new bundled rules.
                try write(bundled, to: rulesURL)
                try write(bundled, to: seedURL)
                return try loadSaved()
            }
            bundledUpdateAvailable = current != bundled
        }
        let saved = try loadSaved()
        return Loaded(rules: saved.rules, warnings: saved.warnings, recoveredFrom: saved.recoveredFrom,
                      bundledUpdateAvailable: bundledUpdateAvailable)
    }

    /// Saves rules edited in the app. Rules with errors are refused.
    public func save(_ rules: HouseholdRules) throws(RulesError) {
        let errors = RulesValidator.validate(rules).filter { $0.severity == .error }
        guard errors.isEmpty else { throw RulesError(issues: errors) }
        let data = RulesWriter.data(rules)
        try ensureDirectory()
        try write(data, to: rulesURL)
        try write(data, to: lastGoodURL)
    }

    /// Replaces the rules with an edited file, only if it loads cleanly.
    @discardableResult
    public func importRules(_ data: Data, bundled: Data? = nil) throws(RulesError) -> LoadedRules {
        let loaded = try RulesLoader.load(data)
        try ensureDirectory()
        try write(data, to: rulesURL)
        try write(data, to: lastGoodURL)
        if let bundled, bundled == data {
            try write(bundled, to: seedURL)
        }
        return loaded
    }

    /// The rules file as saved, for the share sheet.
    public func exportData() throws(RulesError) -> Data {
        try read(rulesURL)
    }

    // MARK: Photos

    /// Saves a person's photo (already cropped and compressed by the app)
    /// and returns the file name to put in their `photo`.
    public func savePhoto(_ jpeg: Data, for person: PersonID) throws(RulesError) -> String {
        let safe = String(person.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" ? Character(scalar) : "_"
        })
        let name = "\(safe).jpg"
        do {
            try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        } catch {
            throw Self.failure("Couldn't create the Photos folder: \(error.localizedDescription)")
        }
        try write(jpeg, to: photoURL(named: name))
        return name
    }

    public func photoURL(named name: String) -> URL {
        photosDirectory.appendingPathComponent(name)
    }

    public func deletePhoto(named name: String) {
        try? FileManager.default.removeItem(at: photoURL(named: name))
    }

    // MARK: Files

    private func loadSaved() throws(RulesError) -> Loaded {
        do {
            let loaded = try RulesLoader.load(read(rulesURL))
            try write(read(rulesURL), to: lastGoodURL)
            return Loaded(rules: loaded.rules, warnings: loaded.warnings, recoveredFrom: nil, bundledUpdateAvailable: false)
        } catch {
            guard let fallback = try? RulesLoader.load(read(lastGoodURL)) else { throw error }
            return Loaded(rules: fallback.rules, warnings: fallback.warnings, recoveredFrom: error, bundledUpdateAvailable: false)
        }
    }

    private func ensureDirectory() throws(RulesError) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw Self.failure("Couldn't create \(directory.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func read(_ url: URL) throws(RulesError) -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw Self.failure("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func write(_ data: Data, to url: URL) throws(RulesError) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw Self.failure("Couldn't save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func failure(_ message: String) -> RulesError {
        RulesError(issues: [RulesIssue(.error, "", message)])
    }
}
