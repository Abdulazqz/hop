import AppKit
import SwitcherCore

@MainActor
final class Launcher {
    private let model: AppModel
    private let onError: (String, String) -> Void
    private var launching: Set<UUID> = []
    /// The app returned by `openApplication`'s completion, kept until the tracker sees it (or it dies first).
    /// Bridges the gap between launch completion and `NSWorkspace.runningApplications` catching up.
    private var pending: [UUID: NSRunningApplication] = [:]

    init(model: AppModel, onError: @escaping (String, String) -> Void = Alerts.show) {
        self.model = model
        self.onError = onError
    }

    /// Brings the account's instance to the front, or starts it. Never starts a second
    /// instance on a folder that is already running, still launching, or launched but not yet tracked.
    func open(_ account: Account, completion: (() -> Void)? = nil) {
        model.tracker.refresh()
        let running = model.tracker.running[account.id]
        if running != nil {
            pending[account.id] = nil
        }
        let pendingAlive = pending[account.id].map { !$0.isTerminated } ?? false
        if !pendingAlive {
            pending[account.id] = nil
        }

        switch OpenDecision.decide(running: running != nil, launching: launching.contains(account.id), pendingAlive: pendingAlive) {
        case .focusRunning:
            if let running { Focuser.bringToFront(running) }
            completion?()
            return
        case .focusPending:
            if let app = pending[account.id] { Focuser.bringToFront(app) }
            completion?()
            return
        case .wait:
            completion?()
            return
        case .launch:
            break
        }

        guard let appURL = ClaudeApp.url else {
            onError("Claude app not found", "Install Claude in /Applications, then try again.")
            completion?()
            return
        }
        if let folder = account.folder {
            try? FileManager.default.createDirectory(atPath: FolderPath.expand(folder, home: NSHomeDirectory()),
                                                     withIntermediateDirectories: true)
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        config.arguments = ProcessArgs.launchArguments(folder: account.folder, home: NSHomeDirectory())
        launching.insert(account.id)
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] app, error in
            Task { @MainActor in
                if let app { self?.pending[account.id] = app }
                self?.launching.remove(account.id)
                if let error { self?.onError("Couldn't open \(account.name)", error.localizedDescription) }
                self?.model.tracker.refresh()
                completion?()
            }
        }
    }

    func quit(_ account: Account) {
        model.tracker.running[account.id]?.terminate()
    }
}
