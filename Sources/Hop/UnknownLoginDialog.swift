import AppKit
import SwitcherCore

@MainActor
enum UnknownLoginDialog {
    /// Asks which account the live login is (`login` is "email · organization"): one of the accounts that has no
    /// login yet, or a new one. `target` is the account about to be switched to, when this precedes a switch;
    /// `preselect` is offered first. nil = cancel.
    static func ask(login: String, target: String?, candidates: [Account], preselect: UUID? = nil) -> UnknownLoginChoice? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = target.map { "Keep the current login before switching to \u{201c}\($0)\u{201d}?" } ?? "Keep the current login?"
        alert.informativeText = "Terminal is logged in as \(login). Hop has no account for that login yet"
            + (target == nil ? ". " : ", and switching away would lose it. ")
            + "Choose which account it is; Hop saves the login there so you can switch back to it later."
        alert.addButton(withTitle: target == nil ? "Save" : "Save and switch")
        alert.addButton(withTitle: "Cancel")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        popup.addItem(withTitle: "Save as a new account")
        for account in candidates { popup.addItem(withTitle: "Save as \u{201c}\(account.name)\u{201d}") }
        if let preselect, let index = candidates.firstIndex(where: { $0.id == preselect }) { popup.selectItem(at: index + 1) }
        alert.accessoryView = popup
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let index = popup.indexOfSelectedItem
        return index == 0 ? .create : .attach(candidates[index - 1].id)
    }
}
