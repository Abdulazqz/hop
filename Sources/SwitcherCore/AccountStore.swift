import Foundation

public struct AccountsFile: Codable, Equatable {
    public var version: Int
    public var accounts: [Account]
}

public enum AccountStore {
    public static let currentVersion = 1

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hop/accounts.json")
    }

    /// First-run accounts: the default Claude profile plus two more, each in its own folder.
    public static func seed() -> [Account] {
        [
            Account(name: "Account 1", color: .purple, folder: nil),
            Account(name: "Account 2", color: .teal, folder: "~/Library/Application Support/Claude-acct2"),
            Account(name: "Account 3", color: .coral, folder: "~/Library/Application Support/Claude-acct3"),
        ]
    }

    public static func load(from url: URL) throws -> [Account] {
        try JSONDecoder().decode(AccountsFile.self, from: Data(contentsOf: url)).accounts
    }

    public static func save(_ accounts: [Account], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(AccountsFile(version: currentVersion, accounts: accounts)).write(to: url, options: .atomic)
    }

    /// Loads accounts, seeding on first run. A file that can't be read or fails
    /// validation is kept as `<name>.bad` and replaced with the seed.
    public static func loadOrSeed(from url: URL, home: String) -> (accounts: [Account], recovered: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            let seeded = seed()
            try? save(seeded, to: url)
            return (seeded, false)
        }
        if let accounts = try? load(from: url), (try? AccountValidation.validate(accounts, home: home)) != nil {
            return (accounts, false)
        }
        let bad = url.appendingPathExtension("bad")
        try? fm.removeItem(at: bad)
        try? fm.moveItem(at: url, to: bad)
        let seeded = seed()
        try? save(seeded, to: url)
        return (seeded, true)
    }
}
