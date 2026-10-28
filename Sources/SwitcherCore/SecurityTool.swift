import Foundation

/// Apple's `security` tool, driven the way Claude Code drives it for its own Keychain item.
///
/// Why not the Security framework: a framework write re-stamps the item's partition list with the
/// writer, after which `security` (and so every Claude Code session, which reads its login through it)
/// is stopped by a Keychain dialog. Writes made by `security` itself keep the item open to `security`.
public enum SecurityTool {
    public static let path = "/usr/bin/security"
    /// `security` reports errSecItemNotFound as this exit status.
    public static let notFoundExit: Int32 = 44
    /// `security -i` splits longer lines at 4096 bytes and runs the first part, storing a truncated value.
    public static let stdinLineLimit = 4000

    public struct Invocation: Equatable {
        public let arguments: [String]
        /// Commands for `security -i`; keeps the value out of the process arguments.
        public let stdin: String?
    }

    public struct Failure: LocalizedError, Equatable {
        public let exit: Int32
        public let message: String
        public var errorDescription: String? { "security exited \(exit): \(message)" }
    }

    public static func read(service: String, account: String) -> Invocation {
        Invocation(arguments: ["find-generic-password", "-a", account, "-w", "-s", service], stdin: nil)
    }

    /// A write the tool could only take on its command line, where `ps` shows it to every process of the user.
    public struct Unwritable: LocalizedError, Equatable {
        public let bytes: Int
        public let reason: String
        public var errorDescription: String? { "can't hand \(bytes) bytes to security without putting them on its command line: \(reason)" }
    }

    /// One `security -i` line. Hex (`-X`) carries any bytes but doubles the size; quoted text (`-w`) carries
    /// anything but control characters at its own size, which is how a login the size of Claude Code's fits.
    /// A value that fits neither way is refused: the arguments are never used for it.
    public static func write(_ data: Data, service: String, account: String) throws -> Invocation {
        guard let quotedAccount = quoted(Data(account.utf8)), let quotedService = quoted(Data(service.utf8)) else {
            throw Unwritable(bytes: data.count, reason: "the account or service name has a control character")
        }
        let prefix = "add-generic-password -U -a \(quotedAccount) -s \(quotedService) "
        let hexLine = prefix + "-X \"" + data.map { String(format: "%02x", $0) }.joined() + "\"\n"
        if hexLine.utf8.count <= stdinLineLimit { return Invocation(arguments: ["-i"], stdin: hexLine) }
        guard let quotedValue = quoted(data) else {
            throw Unwritable(bytes: data.count, reason: "it has a control character, and as hex it exceeds the \(stdinLineLimit)-byte line")
        }
        let textLine = prefix + "-w " + quotedValue + "\n"
        guard textLine.utf8.count <= stdinLineLimit else {
            throw Unwritable(bytes: data.count, reason: "it exceeds the \(stdinLineLimit)-byte line")
        }
        return Invocation(arguments: ["-i"], stdin: textLine)
    }

    public static func delete(service: String, account: String) -> Invocation {
        Invocation(arguments: ["delete-generic-password", "-a", account, "-s", service], stdin: nil)
    }

    /// The value a read produced; nil when the item doesn't exist. `-w` appends one newline.
    public static func value(exit: Int32, stdout: Data, stderr: String) throws -> Data? {
        if exit == notFoundExit { return nil }
        guard exit == 0 else { throw Failure(exit: exit, message: trimmed(stderr)) }
        var value = stdout
        if value.last == UInt8(ascii: "\n") { value.removeLast() }
        // An item that exists but yields no data must not read as "missing": rollback would then delete it.
        guard !value.isEmpty else { throw Failure(exit: exit, message: "the item has no data") }
        return value
    }

    public static func checkDelete(exit: Int32, stderr: String) throws {
        guard exit == 0 || exit == notFoundExit else { throw Failure(exit: exit, message: trimmed(stderr)) }
    }

    /// Double-quoted for the `-i` line reader, which honours `\"` and `\\` inside quotes and passes tabs, DEL and
    /// UTF-8 through; line terminators and NUL can't be carried, nor can bytes that aren't UTF-8.
    static func quoted(_ bytes: Data) -> String? {
        guard bytes.allSatisfy({ $0 >= 0x20 }), let text = String(data: bytes, encoding: .utf8) else { return nil }
        return "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// One generic-password item, read and written through `security`.
public struct SecurityToolItem {
    public let service: String
    public let account: String
    /// A Keychain dialog would hold the tool open; past this the tool is killed and the call fails.
    public let timeout: TimeInterval

    public init(service: String, account: String, timeout: TimeInterval = 20) {
        self.service = service
        self.account = account
        self.timeout = timeout
    }

    public func read() throws -> Data? {
        let result = try run(SecurityTool.read(service: service, account: account))
        return try SecurityTool.value(exit: result.exit, stdout: result.stdout, stderr: result.stderr)
    }

    public func write(_ data: Data) throws {
        let result = try run(SecurityTool.write(data, service: service, account: account))
        guard result.exit == 0 else {
            throw SecurityTool.Failure(exit: result.exit, message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func delete() throws {
        let result = try run(SecurityTool.delete(service: service, account: account))
        try SecurityTool.checkDelete(exit: result.exit, stderr: result.stderr)
    }

    private struct Output {
        let exit: Int32
        let stdout: Data
        let stderr: String
    }

    private func run(_ invocation: SecurityTool.Invocation) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: SecurityTool.path)
        process.arguments = invocation.arguments
        let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = invocation.stdin == nil ? FileHandle.nullDevice : stdin
        try process.run()
        if let text = invocation.stdin {
            stdin.fileHandleForWriting.write(Data(text.utf8))
            try? stdin.fileHandleForWriting.close()
        }
        var out = Data(), err = Data()
        let done = DispatchGroup()
        done.enter()
        DispatchQueue.global().async { out = stdout.fileHandleForReading.readDataToEndOfFile(); done.leave() }
        done.enter()
        DispatchQueue.global().async { err = stderr.fileHandleForReading.readDataToEndOfFile(); done.leave() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 2)
            process.waitUntilExit()
            throw SecurityTool.Failure(exit: process.terminationStatus,
                                       message: "security didn't answer within \(Int(timeout))s; a Keychain dialog may be waiting")
        }
        process.waitUntilExit()
        return Output(exit: process.terminationStatus, stdout: out, stderr: String(decoding: err, as: UTF8.self))
    }
}
