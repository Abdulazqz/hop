import AppKit
import SwitcherCore

/// Knows which account each running Claude instance belongs to. Event-driven, no timers.
@MainActor
final class InstanceTracker {
    var accountsProvider: () -> [Account] = { [] }
    var onChange: (() -> Void)?
    private(set) var running: [UUID: NSRunningApplication] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == ClaudeApp.bundleID else { return }
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func isRunning(_ account: Account) -> Bool { running[account.id] != nil }

    func refresh() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == ClaudeApp.bundleID && !$0.isTerminated
        }
        let processes = apps.compactMap { app in
            ProcessArgs.argv(pid: app.processIdentifier).map { ClaudeProcess(pid: app.processIdentifier, argv: $0) }
        }
        let pids = InstanceMatcher.match(accounts: accountsProvider(), processes: processes, home: NSHomeDirectory())
        let appsByPID = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        running = pids.compactMapValues { appsByPID[$0] }
        onChange?()
    }
}
