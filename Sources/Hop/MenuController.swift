import AppKit
import SwitcherCore

struct MenuActions {
    var open: (Account) -> Void
    var quit: (Account) -> Void
    var switchLogin: (Account) -> Void
    var openTerminal: (Account) -> Void
    var setHotkeyAction: (HotkeyAction) -> Void
    var addAccount: (() -> Void)? = nil
    var editAccounts: (() -> Void)? = nil
    /// Starts Get token for one account right away.
    var getToken: ((Account) -> Void)? = nil
    var toggleHopLogin: (() -> Void)? = nil
}

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let actions: MenuActions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    /// Supplies the computed menu each rebuild; set by AppDelegate.
    var modelProvider: (() -> MenuModel)?
    /// Whether Hop is currently the Claude login; set by AppDelegate so the toggle item shows the right label.
    var hopLoginEnabled: (() -> Bool)?
    var hotkeyAction: HotkeyAction = .default
    private static let symbolIcon = NSImage(systemSymbolName: "person.2", accessibilityDescription: "Claude accounts")

    init(model: AppModel, actions: MenuActions) {
        self.model = model
        self.actions = actions
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "person.2", accessibilityDescription: "Claude accounts")
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        rebuild()
    }

    /// `true` when macOS has hidden the icon behind a display notch, `nil` before the item is laid out.
    var isHiddenByNotch: Bool? {
        guard let window = statusItem.button?.window else { return nil }
        let screen = window.screen
            ?? NSScreen.screens.first { $0.frame.intersects(window.frame) }
            ?? NSScreen.main
        guard let screen else { return nil }
        return MenuBarPlacement.isHiddenByNotch(itemFrame: window.frame, safeTopRight: screen.auxiliaryTopRightArea)
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.tracker.refresh()
        rebuild()
    }

    func rebuild() {
        menu.removeAllItems()
        let computed = modelProvider?() ?? MenuModel.build(accounts: [], activeAccountID: nil, tokenBacked: [],
                                                            desktopRunning: [], runningSessions: 0,
                                                            hotkeyAction: hotkeyAction, hotkeyPositions: [])
        updateIcon(activeID: computed.activeAccountID)

        if !computed.header.isEmpty {
            let header = NSMenuItem(title: computed.header, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            if let line = computed.sessionsLine {
                let sessions = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                sessions.isEnabled = false
                menu.addItem(sessions)
            }
            menu.addItem(.separator())
        }
        if ClaudeApp.url == nil {
            let missing = NSMenuItem(title: "Claude app not found", action: nil, keyEquivalent: "")
            missing.isEnabled = false
            menu.addItem(missing)
        }
        for row in computed.rows {
            guard let account = model.accounts.first(where: { $0.id == row.accountID }) else { continue }
            menu.addItem(accountItem(account, row: row))
        }
        menu.addItem(.separator())
        if let add = actions.addAccount { menu.addItem(ClosureMenuItem(title: "Add account…", handler: add)) }
        if let edit = actions.editAccounts { menu.addItem(ClosureMenuItem(title: "Edit accounts…", handler: edit)) }
        menu.addItem(hotkeysItem())
        if let toggle = actions.toggleHopLogin {
            let on = hopLoginEnabled?() ?? false
            menu.addItem(ClosureMenuItem(title: on ? "Stop using Hop as my Claude login" : "Use Hop as my Claude login\u{2026}", handler: toggle))
        }
        let login = ClosureMenuItem(title: "Launch at login") { LoginItem.toggle() }
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Quit Hop", keyEquivalent: "q") { NSApp.terminate(nil) })
    }

    /// One account row with no submenu: clicking it switches to the account (or gets its setup-token when it has
    /// none), and its icons open Terminal on it or its Claude app. Return on the highlighted row does the same
    /// as a click.
    private func accountItem(_ account: Account, row: MenuRow) -> NSMenuItem {
        let primary: () -> Void
        let help: String
        switch row.switchLabel {
        case .active:
            primary = {}
            help = "\(account.name) is the active Claude login"
        case .switchLogin:
            primary = { [weak self] in self?.actions.switchLogin(account) }
            help = "Switch every claude session to \(account.name)"
        case .needsToken:
            primary = { [weak self] in
                if let getToken = self?.actions.getToken { getToken(account) } else { self?.actions.editAccounts?() }
            }
            help = "Add a setup-token for \(account.name)"
        }
        let appIcon = ClaudeApp.url.map { url -> NSImage in
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            return icon
        }
        let view = AccountRowView(AccountRowView.Content(
            name: row.title,
            color: account.color.nsColor,
            desktopRunning: row.desktopRunning,
            isActive: row.isActive,
            hint: row.hint,
            help: help,
            terminalHelp: row.terminalLabel == .openTerminal ? "Open Terminal on \(account.name)" : nil,
            appIcon: appIcon,
            appHelp: row.desktopLabel + (row.desktopRunning ? " (\u{2325}-click to quit it)" : "")))
        view.onRow = primary
        view.onTerminal = { [weak self] in self?.actions.openTerminal(account) }
        view.onApp = { [weak self] quit in
            if quit { if row.desktopRunning { self?.actions.quit(account) } } else { self?.actions.open(account) }
        }
        let item = ClosureMenuItem(title: row.title, handler: primary)
        item.view = view
        return item
    }

    private func hotkeysItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Hotkeys", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        for action in HotkeyAction.allCases {
            let choice = ClosureMenuItem(title: action.label) { [weak self] in self?.actions.setHotkeyAction(action) }
            choice.state = action == hotkeyAction ? .on : .off
            sub.addItem(choice)
        }
        item.submenu = sub
        return item
    }

    /// Filled circle in the active account's color; the gray symbol when nothing is active.
    private func updateIcon(activeID: UUID?) {
        if let activeID, let account = model.accounts.first(where: { $0.id == activeID }) {
            let image = Dot.image(color: account.color.nsColor, filled: true, size: 14)
            image.isTemplate = false
            statusItem.button?.image = image
            statusItem.button?.toolTip = "Hop · \(account.name)"
        } else {
            statusItem.button?.image = Self.symbolIcon
            statusItem.button?.toolTip = "Hop"
        }
    }
}
