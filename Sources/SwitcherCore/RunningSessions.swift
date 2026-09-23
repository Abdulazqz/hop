import Darwin
import Foundation

/// How many Claude Code terminal sessions this user is running. A hint for the menu, nothing more.
public enum RunningSessions {
    public static let processName = "claude"

    public static func count(processNames: [String]) -> Int {
        processNames.filter { $0 == processName }.count
    }

    public static func count() -> Int {
        let uid = getuid()
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), uid, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return 0 }
        let found = Int(bytes) / MemoryLayout<pid_t>.size
        var names: [String] = []
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for pid in pids.prefix(found) where pid > 0 {
            if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
                names.append(String(cString: buffer))
            }
        }
        return count(processNames: names)
    }
}
