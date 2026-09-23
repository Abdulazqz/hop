import Darwin

public enum ProcessArgs {
    static let flag = "--user-data-dir="

    /// The --user-data-dir value in an argv, parsed the way Chromium does:
    /// only the `=` form, last one wins, nothing after `--`, argv[0] skipped.
    public static func userDataDir(from argv: [String]) -> String? {
        var result: String?
        for arg in argv.dropFirst() {
            if arg == "--" { break }
            if arg.hasPrefix(flag) {
                let value = String(arg.dropFirst(flag.count))
                result = value.isEmpty ? nil : value
            }
        }
        return result
    }

    /// Arguments that start Claude on `folder` (`nil`, empty, or whitespace-only = default profile).
    public static func launchArguments(folder: String?, home: String) -> [String] {
        guard !FolderPath.isBlank(folder), let folder else { return [] }
        return [flag + FolderPath.expand(folder, home: home)]
    }

    /// Parses a KERN_PROCARGS2 buffer: argc (Int32), exec path, NUL padding, argv, then env.
    public static func parseProcArgs2(_ bytes: [UInt8]) -> [String]? {
        guard bytes.count >= MemoryLayout<Int32>.size else { return nil }
        let argc = Int(bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        var i = MemoryLayout<Int32>.size
        while i < bytes.count, bytes[i] != 0 { i += 1 }   // exec path
        while i < bytes.count, bytes[i] == 0 { i += 1 }   // padding
        var args: [String] = []
        while args.count < argc, i < bytes.count {
            let start = i
            while i < bytes.count, bytes[i] != 0 { i += 1 }
            args.append(String(decoding: bytes[start..<i], as: UTF8.self))
            i += 1
        }
        return args.count == argc ? args : nil
    }

    /// argv of a running process owned by this user, or nil if it can't be read.
    public static func argv(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argmax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &argmax, &size, nil, 0) == 0, argmax > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(argmax))
        size = buffer.count
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseProcArgs2(Array(buffer[..<size]))
    }
}
