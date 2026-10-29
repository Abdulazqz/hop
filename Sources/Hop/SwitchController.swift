import AppKit
import SwitcherCore

/// Glues SwitchCoordinator to the model, the stores, alerts, and Terminal.
/// Reads the Keychain only inside switchTo, saveCurrentLogin, forgetSavedLogin and deleteSavedLogins;
/// everything shown in the menu comes from ~/.claude.json and the accounts file.
@MainActor
final class SwitchController {
    private let model: AppModel
    private let logins: LoginStore
    private let identityDocument: IdentityDocumentStore
    private let coordinator: SwitchCoordinator
    private let stateURL: URL
    /// False from the command line: an unknown login is reported as an error instead of opening the save dialog.
    private let interactive: Bool
    private(set) var state: HopState
    private(set) var live: LiveLoginState = .loggedOut
    /// Set once the live data was unrecognized; Switch stays disabled until relaunch.
    private(set) var loginFormatBroken = false
    var onChange: (() -> Void)?
    /// Where failures go: an alert in the app, a printed line in the CLI.
    var reportError: (Error) -> Void = { Alerts.switchFailed($0) }

    init(model: AppModel, logins: LoginStore = KeychainLoginStore(),
         identityDocument: IdentityDocumentStore = IdentityDocumentFile(), stateURL: URL = HopStateFile.url,
         interactive: Bool = true, reportError: ((Error) -> Void)? = nil) {
        self.model = model
        self.logins = logins
        self.identityDocument = identityDocument
        self.stateURL = stateURL
        self.interactive = interactive
        self.state = HopState.load(from: stateURL)
        self.coordinator = SwitchCoordinator(logins: logins, identityDocument: identityDocument, home: NSHomeDirectory())
        if let reportError { self.reportError = reportError }
        refreshLive()
    }

    func refreshLive() {
        live = LiveLogin.parseIdentityOnly(identityDocument: try? identityDocument.read())
        if case .unrecognized = live, !loginFormatBroken {
            loginFormatBroken = true
            reportError(SwitchError.unrecognizedLogin(reason(of: live)))
        }
    }

    var activeAccountID: UUID? {
        guard case .loggedIn(let summary) = live else { return nil }
        return LoginAttribution.attribute(summary, accounts: model.accounts, state: state).accountID
    }

    func hasSavedLogin(_ id: UUID) -> Bool { model.accounts.first { $0.id == id }?.email != nil }

    func menuModel(desktopRunning: Set<UUID>, hotkeyAction: HotkeyAction, hotkeyPositions: Set<Int>) -> MenuModel {
        MenuModel.build(accounts: model.accounts, live: live, state: state,
                        savedLoginExpiry: Dictionary(uniqueKeysWithValues: model.accounts.compactMap { a in a.savedLoginExpiresAt.map { (a.id, $0) } }),
                        hasSavedLogin: Set(model.accounts.filter { $0.email != nil }.map(\.id)),
                        desktopRunning: desktopRunning, runningSessions: RunningSessions.count(),
                        hotkeyAction: hotkeyAction, hotkeyPositions: hotkeyPositions, now: Date())
    }

    /// Returns true when the account is now active (was already, or the switch succeeded).
    /// Always runs the coordinator, even when the menu already shows the account as active, so a wiped
    /// Keychain item or a rewritten identity file gets repaired.
    @discardableResult
    func switchTo(_ account: Account) -> Bool {
        guard !loginFormatBroken else { reportError(SwitchError.unrecognizedLogin("see the earlier alert")); return false }
        refreshLive()
        // First pass never blocks: an unknown login comes back as .cancelled, so ~/.claude.json isn't held
        // across the dialog. The second pass re-reads everything with the user's answer.
        do {
            return try attemptSwitch(to: account) { _ in nil }
        } catch SwitchError.cancelled(let login) {
            guard interactive else { return switchFailed(SwitchError.cancelled(login: login)) }
            guard let choice = UnknownLoginDialog.ask(login: login, candidates: model.accounts.filter { $0.email == nil }) else {
                return false
            }
            do {
                return try attemptSwitch(to: account) { _ in choice }
            } catch {
                return switchFailed(error)
            }
        } catch {
            return switchFailed(error)
        }
    }

    /// One coordinator run: persists on success; "already active" counts as success.
    private func attemptSwitch(to account: Account, resolveUnknown: (String) -> UnknownLoginChoice?) throws -> Bool {
        do {
            let result = try coordinator.switchTo(account.id, accounts: model.accounts, state: state, resolveUnknown: resolveUnknown)
            try persist(accounts: result.accounts, state: result.state)
        } catch SwitchError.alreadyActive {
            refreshLive()
            onChange?()
        }
        return true
    }

    private func switchFailed(_ error: Error) -> Bool {
        reportError(error)
        refreshLive()
        onChange?()
        return false
    }

    func openTerminal(_ account: Account) {
        guard hasSavedLogin(account.id) else { logInFirst(); return }
        guard switchTo(account) else { return }
        if !TerminalRunner.open(.claude) { Alerts.terminalAutomationDenied() }
    }

    func logInFirst() {
        if TerminalRunner.open(.login) { Alerts.logInFirst() } else { Alerts.terminalAutomationDenied() }
    }

    func saveCurrentLogin() {
        refreshLive()
        guard case .loggedIn(let summary) = live else { return }
        guard let choice = UnknownLoginDialog.ask(login: summary.label, candidates: model.accounts.filter { $0.email == nil }) else { return }
        do {
            let (accounts, newState) = try coordinator.saveCurrentLogin(accounts: model.accounts, state: state, choice: choice)
            try persist(accounts: accounts, state: newState)
        } catch {
            reportError(error)
        }
    }

    func forgetSavedLogin(_ account: Account) throws {
        if activeAccountID == account.id { throw SwitchError.store("\(account.name) is the active account. Switch to another account first.") }
        try logins.deleteSaved(account.id)
        var accounts = model.accounts
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index].email = nil
            accounts[index].organizationUuid = nil
            accounts[index].organizationName = nil
            accounts[index].savedLoginExpiresAt = nil
        }
        try model.setAccounts(accounts)
        if state.activeAccountID == account.id {
            // The recorded hash pointed at the login just deleted; keep it from attributing anything to this account.
            state = .empty
            try state.save(to: stateURL)
        }
        onChange?()
    }

    func deleteSavedLogins(for ids: [UUID]) {
        for id in ids { try? logins.deleteSaved(id) }
    }

    private func persist(accounts: [Account], state newState: HopState) throws {
        if accounts != model.accounts { try model.setAccounts(accounts) }
        state = newState
        try state.save(to: stateURL)
        refreshLive()
        onChange?()
    }

    private func reason(of state: LiveLoginState) -> String {
        if case .unrecognized(let why) = state { return why }
        return ""
    }
}
