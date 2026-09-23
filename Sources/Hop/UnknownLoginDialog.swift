import AppKit
import SwitcherCore

@MainActor
enum UnknownLoginDialog {
    /// "Save the current login as…": a new account, or one of the accounts that has no email yet. nil = cancel.
    static func ask(email: String, candidates: [Account]) -> UnknownLoginChoice? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Save the current login?"
        alert.informativeText = "Terminal is logged in as \(email), which Hop hasn't saved. Switching away would lose that login, so save it first."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        popup.addItem(withTitle: "New account")
        for account in candidates { popup.addItem(withTitle: "Attach to \(account.name)") }
        alert.accessoryView = popup
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let index = popup.indexOfSelectedItem
        return index == 0 ? .create : .attach(candidates[index - 1].id)
    }
}
