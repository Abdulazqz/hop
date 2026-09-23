import AppKit
import SwitcherCore

struct MenuActions {
    var open: (Account) -> Void
    var quit: (Account) -> Void
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

    func menuWillOpen(_ menu: NSMenu) {
        model.tracker.refresh()
        rebuild()
    }

    func rebuild() {
        menu.removeAllItems()
        if ClaudeApp.url == nil {
            let missing = NSMenuItem(title: "Claude app not found", action: nil, keyEquivalent: "")
            missing.isEnabled = false
            menu.addItem(missing)
        } else {
            for (position, account) in model.accounts.enumerated() {
                addRows(for: account, position: position)
            }
        }
        menu.addItem(.separator())
        if let add = actions.addAccount { menu.addItem(ClosureMenuItem(title: "Add account…", handler: add)) }
        if let edit = actions.editAccounts { menu.addItem(ClosureMenuItem(title: "Edit accounts…", handler: edit)) }
        let login = ClosureMenuItem(title: "Launch at login") { LoginItem.toggle() }
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Quit Hop", keyEquivalent: "q") { NSApp.terminate(nil) })
    }

    /// A row that opens/focuses, plus its ⌥ alternate that quits.
    private func addRows(for account: Account, position: Int) {
        let running = model.tracker.isRunning(account)
        let dot = Dot.image(color: account.color.nsColor, filled: running)
        dot.accessibilityDescription = running ? "Running" : "Closed"

        let open = ClosureMenuItem(title: account.name) { [weak self] in self?.actions.open(account) }
        open.attributedTitle = Self.title(account.name,
                                          hint: hotkeyPositions.contains(position) ? "⌃⌥\(position + 1)" : nil)
        open.image = dot
        open.toolTip = running ? "Running" : "Closed"
        open.keyEquivalentModifierMask = []
        menu.addItem(open)

        let quit = ClosureMenuItem(title: "Quit \(account.name)") { [weak self] in self?.actions.quit(account) }
        quit.image = dot
        quit.isAlternate = true
        quit.keyEquivalentModifierMask = .option
        quit.isEnabled = running
        menu.addItem(quit)
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
