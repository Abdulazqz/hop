import AppKit
import SwitcherCore

/// Switches the active account by flipping the pointer file the apiKeyHelper reads; every running
/// `claude` session adopts it on its next stale request. Desktop-profile launching is unchanged.
@MainActor
final class SwitchController {
    private let model: AppModel
    /// Where the active-account pointer is written; the apiKeyHelper reads this same file.
    private let pointerURL: URL
    /// Whether Hop is currently the Claude login. Without it, sessions keep Claude Code's own login.
    private let isLoginEnabled: () -> Bool
    var onChange: (() -> Void)?
    /// Where failures go: an alert in the app, a printed line in the CLI.
    var reportError: (Error) -> Void = { Alerts.switchFailed($0) }

    init(model: AppModel, pointerURL: URL = ActivePointerFile.url,
         isLoginEnabled: @escaping () -> Bool = { HopLoginInstall().isEnabled() },
         reportError: ((Error) -> Void)? = nil) {
        self.model = model
        self.pointerURL = pointerURL
        self.isLoginEnabled = isLoginEnabled
        if let reportError { self.reportError = reportError }
    }

    /// The active account, read from the pointer file (the single source of truth the apiKeyHelper reads).
    var activeAccountID: UUID? {
        guard let text = try? String(contentsOf: pointerURL, encoding: .utf8) else { return nil }
        return ActivePointer.parse(text)
    }

    var loginEnabled: Bool { isLoginEnabled() }

    func menuModel(desktopRunning: Set<UUID>, hotkeyAction: HotkeyAction, hotkeyPositions: Set<Int>) -> MenuModel {
        MenuModel.build(accounts: model.accounts, activeAccountID: activeAccountID,
                        tokenBacked: Set(model.accounts.filter { $0.tokenAddedAt != nil }.map(\.id)),
                        desktopRunning: desktopRunning, runningSessions: RunningSessions.count(),
                        hotkeyAction: hotkeyAction, hotkeyPositions: hotkeyPositions,
                        loginEnabled: isLoginEnabled())
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
            onChange?()
            return true
        } catch {
            reportError(error)
            return false
        }
    }

    /// Clears the active account by removing the pointer file, so no session authenticates as an account
    /// that is no longer there. Sessions have no credential until one is chosen.
    func deactivate() {
        try? FileManager.default.removeItem(at: pointerURL)
        onChange?()
    }

    /// Opens a terminal `claude` on `account`. Only meaningful while Hop is the Claude login: otherwise the
    /// new session would use Claude Code's own login, not the account picked.
    func openTerminal(_ account: Account) {
        guard isLoginEnabled() else {
            reportError(SwitchError.store("Hop isn't your Claude login yet, so a new terminal would use your normal "
                + "Claude Code login instead of \(account.name). Choose \u{201c}Use Hop as my Claude login\u{2026}\u{201d} first."))
            return
        }
        guard switchTo(account) else { return }
        if !TerminalRunner.open(.claude) { Alerts.terminalAutomationDenied() }
    }
}
