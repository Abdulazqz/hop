import Darwin
import Foundation

/// How many Claude Code terminal sessions this user is running. A hint for the menu, nothing more.
public enum RunningSessions {
    public static let processName = "claude"

    public static func isClaudeSession(name: String, path: String, argv: [String]) -> Bool {
        // Check if process name is "claude"
        if name == processName {
            return true
        }

        // Check if the last path component of argv[0] is "claude"
        if let firstArg = argv.first, (firstArg as NSString).lastPathComponent == processName {
            return true
        }

        // Check if path contains "/claude/versions/"
        if path.contains("/claude/versions/") {
            return true
        }

        // Check if any argv element contains "@anthropic-ai/claude-code/"
        if argv.contains(where: { $0.contains("@anthropic-ai/claude-code/") }) {
            return true
        }

        return false
    }

    public static func count(processes: [(name: String, path: String, argv: [String])]) -> Int {
        processes.filter { isClaudeSession(name: $0.name, path: $0.path, argv: $0.argv) }.count
    }

    public static func count() -> Int {
        let uid = getuid()
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), uid, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return 0 }
        let found = Int(bytes) / MemoryLayout<pid_t>.size
        var processes: [(name: String, path: String, argv: [String])] = []
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

        for pid in pids.prefix(found) where pid > 0 {
            let name = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 ? String(cString: nameBuffer) : ""
            let path = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 ? String(cString: pathBuffer) : ""
            let argv = ProcessArgs.argv(pid: pid) ?? []
            processes.append((name: name, path: path, argv: argv))
        }

        return count(processes: processes)
    }
}
