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
            addAccount: { [unowned self] in self.addAccount() },
            editAccounts: { [unowned self] in self.editWindow.show() }
        ))
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

    private func accountsChanged() {
        hotkeys.register(model.accounts.map { account in { [unowned self] in self.launcher.open(account) } })
        menu.hotkeyPositions = hotkeys.registered
        menu.rebuild()
    }

    private func addAccount() {
        editWindow.close()   // an open editor would overwrite the new account on Save
        if let account = AddAccountFlow.run(model: model) { launcher.open(account) }
    }
}
