import Foundation

public struct ClaudeProcess: Equatable {
    public let pid: Int32
    public let argv: [String]

    public init(pid: Int32, argv: [String]) {
        self.pid = pid
        self.argv = argv
    }
}

public enum InstanceMatcher {
    /// Maps account id -> pid of the Claude instance using that account's folder.
    /// Processes on folders no account uses are ignored; if two share a folder, the first wins.
    public static func match(accounts: [Account], processes: [ClaudeProcess], home: String) -> [UUID: Int32] {
        var accountByFolder: [String: UUID] = [:]
        for account in accounts {
            accountByFolder[FolderPath.normalize(account.folder, home: home)] = account.id
        }
        var result: [UUID: Int32] = [:]
        for process in processes {
            let folder = FolderPath.normalize(ProcessArgs.userDataDir(from: process.argv), home: home)
            if let id = accountByFolder[folder], result[id] == nil {
                result[id] = process.pid
            }
        }
        return result
    }
}
