import AppKit
import SwitcherCore

/// Glues SwitchCoordinator to the model, the stores, alerts, and Terminal.
@MainActor
final class SwitchController {
    private let model: AppModel
    private let logins: LoginStore
    private let identityDocument: IdentityDocumentStore
    private let coordinator: SwitchCoordinator
    private let stateURL: URL
    private(set) var state: HopState
    private(set) var live: LiveLoginState = .loggedOut
    /// Set once the live data was unrecognized; Switch stays disabled until relaunch.
    private(set) var loginFormatBroken = false
    var onChange: (() -> Void)?
    /// Where failures go: an alert in the app, a printed line in the CLI.
    var reportError: (Error) -> Void = { Alerts.switchFailed($0) }

    init(model: AppModel, logins: LoginStore = KeychainLoginStore(),
         identityDocument: IdentityDocumentStore = IdentityDocumentFile(), stateURL: URL = HopStateFile.url,
         reportError: ((Error) -> Void)? = nil) {
        self.model = model
        self.logins = logins
        self.identityDocument = identityDocument
        self.stateURL = stateURL
        self.state = HopState.load(from: stateURL)
        self.coordinator = SwitchCoordinator(logins: logins, identityDocument: identityDocument, home: NSHomeDirectory())
        if let reportError { self.reportError = reportError }
        refreshLive()
    }

    func refreshLive() {
        let value = try? logins.readLive()
        let document = try? identityDocument.read()
        live = LiveLogin.parse(keychainValue: value, identityDocument: document)
        if case .unrecognized = live, !loginFormatBroken {
            loginFormatBroken = true
            reportError(SwitchError.unrecognizedLogin(reason(of: live)))
        }
    }

    var activeAccountID: UUID? {
        guard case .loggedIn(let summary) = live else { return nil }
        return LoginAttribution.attribute(summary, accounts: model.accounts, state: state).accountID
    }

    func hasSavedLogin(_ id: UUID) -> Bool { (try? logins.readSaved(id)) != nil }

    func menuModel(desktopRunning: Set<UUID>, hotkeyAction: HotkeyAction, hotkeyPositions: Set<Int>) -> MenuModel {
        MenuModel.build(accounts: model.accounts, live: live, state: state,
                        savedLoginExpiry: coordinator.savedLoginExpiry(for: model.accounts),
                        hasSavedLogin: Set(model.accounts.map(\.id).filter(hasSavedLogin)),
                        desktopRunning: desktopRunning, runningSessions: RunningSessions.count(),
                        hotkeyAction: hotkeyAction, hotkeyPositions: hotkeyPositions, now: Date())
    }

    /// Returns true when the account is now active (was already, or the switch succeeded).
    @discardableResult
    func switchTo(_ account: Account) -> Bool {
        guard !loginFormatBroken else { reportError(SwitchError.unrecognizedLogin("see the earlier alert")); return false }
        refreshLive()
        if activeAccountID == account.id { return true }
        do {
            let result = try coordinator.switchTo(account.id, accounts: model.accounts, state: state) { [self] email in
                UnknownLoginDialog.ask(email: email, candidates: model.accounts.filter { $0.email == nil })
            }
            try persist(accounts: result.accounts, state: result.state)
            return true
        } catch {
            reportError(error)
            refreshLive()
            onChange?()
            return false
        }
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
        guard let choice = UnknownLoginDialog.ask(email: summary.email, candidates: model.accounts.filter { $0.email == nil }) else { return }
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
        if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index].email = nil }
        try model.setAccounts(accounts)
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
