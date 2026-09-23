import AppKit
import SwitcherCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var launcher: Launcher!
    private var menu: MenuController!
    private var editWindow: EditAccountsWindow!
    private let hotkeys = Hotkeys()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let fileURL = AccountStore.defaultURL
        let (accounts, recovered) = AccountStore.loadOrSeed(from: fileURL, home: NSHomeDirectory())
        model = AppModel(accounts: accounts, fileURL: fileURL)
        launcher = Launcher(model: model)
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
