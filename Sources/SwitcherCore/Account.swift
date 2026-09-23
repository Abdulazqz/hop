import Foundation

public enum AccountColor: String, Codable, CaseIterable {
    case purple, teal, coral, pink, blue, green, amber, red, gray
}

public struct Account: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: AccountColor
    /// Claude profile folder passed as --user-data-dir, stored with "~". `nil` = default profile.
    public var folder: String?

    public init(id: UUID = UUID(), name: String, color: AccountColor, folder: String?) {
        self.id = id
        self.name = name
        self.color = color
        self.folder = folder
    }
}

public enum AccountValidationError: Error, Equatable, LocalizedError {
    case emptyName
    case duplicateName(String)
    case duplicateFolder(String)
    case relativeFolder(String)
    case overlappingFolders(String, String)

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for every account."
        case .duplicateName(let name): return "Another account is already called \u{201c}\(name)\u{201d}."
        case .duplicateFolder(let folder): return "Two accounts use the same folder (\(folder)). Each account needs its own."
        case .relativeFolder(let folder): return "Use a full path for the folder (\(folder))."
        case .overlappingFolders(let a, let b):
            return "\u{201c}\(a)\u{201d} and \u{201c}\(b)\u{201d} are inside each other. Each account needs its own separate folder."
        }
    }
}

public enum AccountValidation {
    /// Names must be non-empty and unique (case-insensitive, trimmed); folders must be unique after
    /// normalization, absolute, and not nested inside one another.
    public static func validate(_ accounts: [Account], home: String) throws {
        var names = Set<String>()
        var folders = Set<String>()
        var seen: [(stored: String, normalized: String)] = []
        for account in accounts {
            let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw AccountValidationError.emptyName }
            guard names.insert(name.lowercased()).inserted else {
                throw AccountValidationError.duplicateName(name)
            }
            let normalized = FolderPath.normalize(account.folder, home: home)
            guard folders.insert(normalized).inserted else {
                throw AccountValidationError.duplicateFolder(account.folder ?? FolderPath.defaultProfile)
            }
            if !FolderPath.isBlank(account.folder), !FolderPath.expand(account.folder!, home: home).hasPrefix("/") {
                throw AccountValidationError.relativeFolder(account.folder!)
            }
            let stored = account.folder ?? FolderPath.defaultProfile
            for other in seen where isNestedPath(other.normalized, normalized) {
                throw AccountValidationError.overlappingFolders(other.stored, stored)
            }
            seen.append((stored: stored, normalized: normalized))
        }
    }

    /// Compares two normalized paths by path components: true when one is an ancestor of the other.
    /// Equal paths (already rejected as duplicates) are not considered nested.
    private static func isNestedPath(_ a: String, _ b: String) -> Bool {
        let aComponents = URL(fileURLWithPath: a).pathComponents
        let bComponents = URL(fileURLWithPath: b).pathComponents
        guard aComponents.count != bComponents.count else { return false }
        let (shorter, longer) = aComponents.count < bComponents.count ? (aComponents, bComponents) : (bComponents, aComponents)
        return Array(longer.prefix(shorter.count)) == shorter
    }
}
