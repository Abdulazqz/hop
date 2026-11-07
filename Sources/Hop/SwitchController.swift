import AppKit
import SwitcherCore

/// Switches the active account by flipping the pointer file the apiKeyHelper reads; every running
/// `claude` session adopts it on its next stale request. Desktop-profile launching is unchanged.
@MainActor
final class SwitchController {
    private let model: AppModel
    private let stateURL: URL
    /// Where the active-account pointer is written; the apiKeyHelper reads this same file.
    private let pointerURL: URL
    private(set) var state: HopState
    var onChange: (() -> Void)?
    /// Where failures go: an alert in the app, a printed line in the CLI.
    var reportError: (Error) -> Void = { Alerts.switchFailed($0) }

    init(model: AppModel, stateURL: URL = HopStateFile.url, pointerURL: URL = ActivePointerFile.url,
         reportError: ((Error) -> Void)? = nil) {
        self.model = model
        self.stateURL = stateURL
        self.pointerURL = pointerURL
        self.state = HopState.load(from: stateURL)
        if let reportError { self.reportError = reportError }
    }

    /// The active account, read from the pointer file (the single source of truth the apiKeyHelper reads).
    var activeAccountID: UUID? {
        guard let text = try? String(contentsOf: pointerURL, encoding: .utf8) else { return nil }
        return ActivePointer.parse(text)
    }

    func menuModel(desktopRunning: Set<UUID>, hotkeyAction: HotkeyAction, hotkeyPositions: Set<Int>) -> MenuModel {
        MenuModel.build(accounts: model.accounts, activeAccountID: activeAccountID,
                        tokenBacked: Set(model.accounts.filter { $0.tokenAddedAt != nil }.map(\.id)),
                        desktopRunning: desktopRunning, runningSessions: RunningSessions.count(),
                        hotkeyAction: hotkeyAction, hotkeyPositions: hotkeyPositions)
    }

    /// Flips the pointer file (atomically) so every running session's next stale request adopts the account.
    /// Refuses an account with no stored setup-token. Returns true on success.
    @discardableResult
    func switchTo(_ account: Account) -> Bool {
        guard account.tokenAddedAt != nil else {
            reportError(SwitchError.store("\(account.name) has no setup-token yet. Add one in Edit accounts first."))
            return false
        }
        do {
            try AtomicFile.write(Data(ActivePointer.content(for: account.id).utf8), to: pointerURL)
            state.activeAccountID = account.id
            try state.save(to: stateURL)
            onChange?()
            return true
        } catch {
            reportError(error)
            return false
        }
    }

    func openTerminal(_ account: Account) {
        guard switchTo(account) else { return }
        if !TerminalRunner.open(.claude) { Alerts.terminalAutomationDenied() }
    }
}
