import AppKit
import SwitcherCore

struct MenuActions {
    var open: (Account) -> Void
    var quit: (Account) -> Void
    var switchLogin: (Account) -> Void
    var openTerminal: (Account) -> Void
    var logInFirst: () -> Void
    var saveCurrentLogin: () -> Void
    var setHotkeyAction: (HotkeyAction) -> Void
    var addAccount: (() -> Void)? = nil
    var editAccounts: (() -> Void)? = nil
}

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let actions: MenuActions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    /// 0-based positions whose ⌃⌥N hotkey is registered; shown as hints.
    var hotkeyPositions: Set<Int> = []
    /// Supplies the computed menu each rebuild; set by AppDelegate.
    var modelProvider: (() -> MenuModel)?
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
        let computed = modelProvider?() ?? MenuModel.build(accounts: [], live: .loggedOut, state: .empty, savedLoginExpiry: [:],
                                                            hasSavedLogin: [], desktopRunning: [], runningSessions: 0,
                                                            hotkeyAction: hotkeyAction, hotkeyPositions: [], now: Date())
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
        if let email = computed.saveCurrentLoginEmail {
            menu.addItem(ClosureMenuItem(title: "Save current login (\(email)) as new account…") { [weak self] in self?.actions.saveCurrentLogin() })
        }
        if let add = actions.addAccount { menu.addItem(ClosureMenuItem(title: "Add account…", handler: add)) }
        if let edit = actions.editAccounts { menu.addItem(ClosureMenuItem(title: "Edit accounts…", handler: edit)) }
        menu.addItem(hotkeysItem())
        let login = ClosureMenuItem(title: "Launch at login") { LoginItem.toggle() }
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Quit Hop", keyEquivalent: "q") { NSApp.terminate(nil) })
    }

    /// One account row: color dot, checkmark when active, and a submenu with the three actions.
    private func accountItem(_ account: Account, row: MenuRow) -> NSMenuItem {
        let dot = Dot.image(color: account.color.nsColor, filled: row.desktopRunning)
        dot.accessibilityDescription = row.desktopRunning ? "Running" : "Closed"
        let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
        item.attributedTitle = Self.title(row.title, hint: row.hint)
        item.image = dot
        item.state = row.isActive ? .on : .off
        item.toolTip = row.isActive ? "Active terminal login" : nil

        let sub = NSMenu()
        sub.autoenablesItems = false
        switch row.switchLabel {
        case .active:
            let active = NSMenuItem(title: "Active", action: nil, keyEquivalent: "")
            active.isEnabled = false
            active.state = .on
            sub.addItem(active)
        case .switchLogin:
            sub.addItem(ClosureMenuItem(title: "Switch terminal login") { [weak self] in self?.actions.switchLogin(account) })
        case .logInFirst:
            sub.addItem(ClosureMenuItem(title: "Log in first…") { [weak self] in self?.actions.logInFirst() })
        }
        sub.addItem(ClosureMenuItem(title: "Open Terminal") { [weak self] in self?.actions.openTerminal(account) })
        sub.addItem(.separator())
        if ClaudeApp.url != nil {
            let open = ClosureMenuItem(title: row.desktopLabel) { [weak self] in self?.actions.open(account) }
            open.keyEquivalentModifierMask = []
            sub.addItem(open)
            let quit = ClosureMenuItem(title: "Quit Claude app") { [weak self] in self?.actions.quit(account) }
            quit.isAlternate = true
            quit.keyEquivalentModifierMask = .option
            quit.isEnabled = row.desktopRunning
            sub.addItem(quit)
        }
        item.submenu = sub
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

    private static func title(_ name: String, hint: String?) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 200)]
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(string: name, attributes: [.font: font, .paragraphStyle: style])
        if let hint {
            title.append(NSAttributedString(string: "\t" + hint, attributes: [
                .font: font, .paragraphStyle: style, .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return title
    }
}
