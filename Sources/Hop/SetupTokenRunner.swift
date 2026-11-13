import AppKit
import Darwin
import SwitcherCore

/// Runs `claude setup-token` the way a person would in Terminal, and catches the token it prints.
///
/// The command needs a terminal (it draws an interactive screen, and without one it assumes it can't open a
/// browser), so it runs on a pseudo-terminal wide enough that the token is never wrapped. `$BROWSER` points at
/// a small script that opens the sign-in page in this account's own browser profile; once the token is caught,
/// Hop closes that browser. The profile (and its claude.ai sign-in) is kept, so the next renewal for this
/// account is just "Authorize"; it goes when the account is removed. The token only ever lives in
/// memory here: it is not shown on screen, logged, or written to a file.
@MainActor
final class SetupTokenRunner {
    enum Failure: LocalizedError {
        case claudeNotFound
        case couldNotStart(String)
        case endedWithoutToken(String?)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .claudeNotFound:
                return "Hop couldn't find the claude command. Install Claude Code, or paste a token instead."
            case .couldNotStart(let reason):
                return "Couldn't start claude setup-token: \(reason)"
            case .endedWithoutToken(let lastLine):
                return "claude setup-token ended without a token" + (lastLine.map { ": \u{201c}\($0)\u{201d}" } ?? ".")
            case .timedOut:
                return "Nothing came back from the browser for 15 minutes, so Hop stopped waiting."
            }
        }
    }

    /// The browser the sign-in page opens in, or nil when Hop fell back to the default browser.
    let browser: PrivateBrowser?
    private let onToken: (String) -> Void
    private let onFailure: (Failure) -> Void
    private var process: Process?
    private var reader: TerminalReader?
    private var workDirectory: URL?
    /// This account's browser profile; kept between runs.
    private let profileDirectory: URL
    private var timeout: DispatchWorkItem?
    private var finished = false

    static let timeoutSeconds: TimeInterval = 15 * 60

    /// True when this account's browser profile already exists, so it has probably signed in there before.
    var hasSignedInBefore: Bool { FileManager.default.fileExists(atPath: profileDirectory.path) }

    init(profileDirectory: URL, onToken: @escaping (String) -> Void, onFailure: @escaping (Failure) -> Void) {
        self.profileDirectory = profileDirectory
        self.browser = AccountBrowser.choose()
        self.onToken = onToken
        self.onFailure = onFailure
    }

    func start() {
        guard let claude = ClaudeCLI.locate() else { return fail(.claudeNotFound) }
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("hop-token-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            workDirectory = work

            var environment = ProcessInfo.processInfo.environment
            environment["TERM"] = "xterm-256color"
            environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
            if let browser, let appURL = AccountBrowser.appURL(browser) {
                let profile = profileDirectory
                try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let opener = work.appendingPathComponent("open-browser.sh")
                let script = PrivateBrowser.openerScript(appPath: appURL.path, profileDirectory: profile.path)
                try AtomicFile.write(Data(script.utf8), to: opener, permissions: 0o700)
                environment["BROWSER"] = opener.path
            } else {
                environment["BROWSER"] = nil   // the default browser, via macOS `open`
            }

            var master: Int32 = -1, slave: Int32 = -1
            var size = winsize(ws_row: 50, ws_col: 400, ws_xpixel: 0, ws_ypixel: 0)
            guard openpty(&master, &slave, nil, nil, &size) == 0 else {
                throw Failure.couldNotStart(String(cString: strerror(errno)))
            }
            let terminal = FileHandle(fileDescriptor: slave, closeOnDealloc: true)

            let process = Process()
            process.executableURL = claude
            process.arguments = ["setup-token"]
            process.environment = environment
            process.currentDirectoryURL = work
            process.standardInput = terminal
            process.standardOutput = terminal
            process.standardError = terminal
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor in self?.processEnded() }
            }

            let reader = TerminalReader(fd: master) { [weak self] token in
                Task { @MainActor in self?.caught(token) }
            }
            self.reader = reader
            try process.run()
            try? terminal.close()   // the child holds its own copy
            self.process = process
            reader.start()

            let timeout = DispatchWorkItem { [weak self] in self?.fail(.timedOut) }
            self.timeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeoutSeconds, execute: timeout)
        } catch let failure as Failure {
            fail(failure)
        } catch {
            fail(.couldNotStart(error.localizedDescription))
        }
    }

    /// Stops the command and closes the account's browser window. Safe to call more than once.
    func cancel() {
        guard !finished else { return }
        finished = true
        cleanUp()
    }

    private func caught(_ token: String) {
        guard !finished else { return }
        finished = true
        cleanUp()
        onToken(token)
    }

    private func processEnded() {
        guard !finished else { return }
        // The output can arrive just after the exit: give the reader a moment before calling it a failure.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.finished else { return }
            if let token = self.reader?.tokenSoFar() { return self.caught(token) }
            self.fail(.endedWithoutToken(self.reader?.lastLine()))
        }
    }

    private func fail(_ failure: Failure) {
        guard !finished else { return }
        finished = true
        cleanUp()
        onFailure(failure)
    }

    private func cleanUp() {
        timeout?.cancel()
        if let process, process.isRunning { process.terminate() }
        reader?.stop()
        let work = workDirectory, profile = profileDirectory, browser = browser
        workDirectory = nil
        // Close the account's browser window; its profile stays for next time.
        Task { @MainActor in
            if let browser { await AccountBrowser.close(browser, profileDirectory: profile.path) }
            if let work { try? FileManager.default.removeItem(at: work) }
        }
    }
}

/// Reads the pseudo-terminal on a background queue and reports the token once it has been printed in full.
private final class TerminalReader: @unchecked Sendable {
    private let fd: Int32
    private let queue = DispatchQueue(label: "local.hop.setup-token")
    private let onToken: @Sendable (String) -> Void
    private var source: DispatchSourceRead?
    private var output = Data()
    private var reported = false
    /// The command prints a few screens; anything past this is noise and not worth holding.
    private static let limit = 4 << 20

    init(fd: Int32, onToken: @escaping @Sendable (String) -> Void) {
        self.fd = fd
        self.onToken = onToken
    }

    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [fd] in close(fd) }
        self.source = source
        source.resume()
    }

    func stop() {
        queue.async { [weak self] in
            self?.source?.cancel()
            self?.source = nil
        }
    }

    func tokenSoFar() -> String? { queue.sync { SetupTokenOutput.token(in: text) } }
    func lastLine() -> String? { queue.sync { SetupTokenOutput.lastLine(of: text) } }

    private var text: String { String(decoding: output, as: UTF8.self) }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else {
            // EIO once the command has exited and the terminal has no writer left.
            source?.cancel()
            source = nil
            return
        }
        if output.count < Self.limit { output.append(contentsOf: buffer[..<count]) }
        if !reported, let token = SetupTokenOutput.token(in: text) {
            reported = true
            onToken(token)
        }
    }
}

/// Where the `claude` command is. A Mac app doesn't get the user's shell PATH, so look in the usual
/// install locations first, then ask a login shell.
enum ClaudeCLI {
    static func locate() -> URL? {
        let home = NSHomeDirectory()
        let candidates = [
            home + "/.local/bin/claude",
            home + "/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: found)
        }
        return fromLoginShell()
    }

    private static func fromLoginShell() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate(); return nil }
        let path = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}

/// Picks, and later closes, the browser instance the sign-in page opens in (on the account's own profile).
@MainActor
enum AccountBrowser {
    static func choose() -> PrivateBrowser? {
        let installed = Set(PrivateBrowser.known.map(\.bundleID).filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        })
        let defaultBrowser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://claude.ai")!)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
        return PrivateBrowser.choose(defaultBundleID: defaultBrowser, installed: installed)
    }

    static func appURL(_ browser: PrivateBrowser) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID)
    }

    /// Quits the browser instance running on `profileDirectory`, waiting up to a few seconds for it to go.
    static func close(_ browser: PrivateBrowser, profileDirectory: String) async {
        let instances = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier == browser.bundleID
                && (ProcessArgs.argv(pid: app.processIdentifier).map {
                    PrivateBrowser.isInstance(argv: $0, profileDirectory: profileDirectory)
                } ?? false)
        }
        for app in instances { app.terminate() }
        for _ in 0..<50 where instances.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        for app in instances where !app.isTerminated { app.forceTerminate() }
    }
}
