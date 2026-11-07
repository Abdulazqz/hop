import AppKit
import SwitcherCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var launcher: Launcher!
    private var switcher: SwitchController!
    private var menu: MenuController!
    private var editWindow: EditAccountsWindow!
    private let hotkeys = Hotkeys()
    private let hopLogin = HopLoginInstall()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let fileURL = AccountStore.defaultURL
        let (accounts, recovered) = AccountStore.loadOrSeed(from: fileURL, home: NSHomeDirectory())
        model = AppModel(accounts: accounts, fileURL: fileURL)
        launcher = Launcher(model: model)
        switcher = SwitchController(model: model)
        switcher.onChange = { [unowned self] in self.menu.rebuild() }
        editWindow = EditAccountsWindow(model: model)
        menu = MenuController(model: model, actions: MenuActions(
            open: { [unowned self] in self.launcher.open($0) },
            quit: { [unowned self] in self.launcher.quit($0) },
            switchLogin: { [unowned self] in _ = self.switcher.switchTo($0) },
            openTerminal: { [unowned self] in self.switcher.openTerminal($0) },
            setHotkeyAction: { [unowned self] in self.setHotkeyAction($0) },
            addAccount: { [unowned self] in self.addAccount() },
            editAccounts: { [unowned self] in self.editWindow.show() },
            toggleHopLogin: { [unowned self] in self.toggleHopLogin() }
        ))
        menu.hotkeyAction = hotkeyAction
        menu.modelProvider = { [unowned self] in
            self.switcher.menuModel(desktopRunning: Set(self.model.tracker.running.keys),
                                           hotkeyAction: self.hotkeyAction, hotkeyPositions: self.hotkeys.registered)
        }
        menu.hopLoginEnabled = { [unowned self] in self.hopLogin.isEnabled() }
        model.tracker.onChange = { [unowned self] in self.menu.rebuild() }
        model.onAccountsChanged = { [unowned self] in self.accountsChanged() }
        accountsChanged()
        if recovered { Alerts.recovered() }
        // The status item's frame isn't final until the menu bar has laid it out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.reportFirstRunProblems() }
    }

    private static let hiddenIconAlertSuppressedKey = "hiddenIconAlertSuppressed"
    private static let log = Logger(subsystem: "local.hop", category: "startup")

    /// Problems a new user can't see from the menu: the icon itself may be invisible, and Claude may be missing.
    private func reportFirstRunProblems() {
        let defaults = UserDefaults.standard
        let hidden = menu.isHiddenByNotch
        Self.log.notice("startup check: icon hidden behind notch = \(String(describing: hidden), privacy: .public), Claude app found = \(ClaudeApp.url != nil, privacy: .public)")
        if hidden == true, !defaults.bool(forKey: Self.hiddenIconAlertSuppressedKey) {
            if Alerts.hiddenByNotch() { defaults.set(true, forKey: Self.hiddenIconAlertSuppressedKey) }
        }
        if ClaudeApp.url == nil { Alerts.claudeMissing() }
    }

    private var hotkeyAction: HotkeyAction {
        get { HotkeyAction(rawValue: UserDefaults.standard.string(forKey: HotkeyAction.defaultsKey) ?? "") ?? .default }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: HotkeyAction.defaultsKey) }
    }

    private func setHotkeyAction(_ action: HotkeyAction) {
        hotkeyAction = action
        menu.hotkeyAction = action
        accountsChanged()
    }

    private func accountsChanged() {
        let actions: [() -> Void]
        switch hotkeyAction {
        case .off: actions = []
        case .switchLogin: actions = model.accounts.map { account in { [unowned self] in _ = self.switcher.switchTo(account) } }
        case .openClaudeApp: actions = model.accounts.map { account in { [unowned self] in self.launcher.open(account) } }
        case .openTerminal: actions = model.accounts.map { account in { [unowned self] in self.switcher.openTerminal(account) } }
        }
        hotkeys.register(actions)
        menu.hotkeyPositions = hotkeys.registered
        menu.rebuild()
    }

    private func addAccount() {
        editWindow.close()   // an open editor would overwrite the new account on Save
        if let account = AddAccountFlow.run(model: model) { launcher.open(account) }
    }

    private func toggleHopLogin() {
        if hopLogin.isEnabled() {
            guard Alerts.confirmDisableHopLogin() else { return }
            do { try hopLogin.disable() } catch { Alerts.switchFailed(error) }
        } else {
            let initial = model.accounts.first(where: { $0.tokenAddedAt != nil })?.id
            if let reason = HopLoginGate.blockReason(accounts: model.accounts, initialActive: initial) {
                Alerts.hopLoginNotReady(reason)
                return
            }
            let name = model.accounts.first(where: { $0.id == initial })?.name ?? ""
            guard Alerts.confirmEnableHopLogin(startAccount: name) else { return }
            do { try hopLogin.enable(initialActive: initial) } catch { Alerts.switchFailed(error) }
        }
        menu.rebuild()
    }
}
