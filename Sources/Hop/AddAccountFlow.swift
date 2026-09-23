import AppKit
import SwitcherCore

@MainActor
enum AddAccountFlow {
    /// Asks for a name and color, picks a folder, and saves. Returns the new account, or nil if cancelled.
    static func run(model: AppModel) -> Account? {
        let home = NSHomeDirectory()
        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = "Add account"
        alert.informativeText = "Claude opens in a new window so you can sign in."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let name = NSTextField(frame: NSRect(x: 0, y: 32, width: 240, height: 24))
        name.placeholderString = "Work"
        let color = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26))
        color.addItems(withTitles: AccountColor.allCases.map(\.label))
        let used = Set(model.accounts.map(\.color))
        color.selectItem(at: AccountColor.allCases.firstIndex { !used.contains($0) } ?? 0)
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 58))
        fields.addSubview(name)
        fields.addSubview(color)
        alert.accessoryView = fields
        alert.window.initialFirstResponder = name

        while alert.runModal() == .alertFirstButtonReturn {
            let trimmed = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let picked = AccountColor.allCases[color.indexOfSelectedItem]
            let candidate = NewAccountFolder.candidate(forName: trimmed, accounts: model.accounts, home: home)
            do {
                // The candidate folder is unclaimed, so only name problems can fail here.
                try AccountValidation.validate(model.accounts + [Account(name: trimmed, color: picked, folder: candidate)],
                                               home: home)
            } catch {
                alert.informativeText = error.localizedDescription
                continue
            }
            guard let folder = chooseFolder(candidate, name: trimmed, model: model) else { return nil }
            let account = Account(name: trimmed, color: picked, folder: folder)
            do {
                try model.setAccounts(model.accounts + [account])
                return account
            } catch {
                alert.informativeText = error.localizedDescription
            }
        }
        return nil
    }

    /// If the folder already exists on disk (but no account uses it), ask whether to reuse it.
    private static func chooseFolder(_ candidate: String, name: String, model: AppModel) -> String? {
        let home = NSHomeDirectory()
        guard FileManager.default.fileExists(atPath: FolderPath.expand(candidate, home: home)) else { return candidate }
        let ask = NSAlert()
        ask.messageText = "A folder for “\(name)” already exists"
        ask.informativeText = "\(candidate) is already on disk and may hold a signed-in account. Use it, or start fresh in a new folder?"
        ask.addButton(withTitle: "Use existing folder")
        ask.addButton(withTitle: "Create new")
        ask.addButton(withTitle: "Cancel")
        switch ask.runModal() {
        case .alertFirstButtonReturn:
            return candidate
        case .alertSecondButtonReturn:
            return NewAccountFolder.candidate(forName: name, accounts: model.accounts, home: home, skipExistingOnDisk: true)
        default:
            return nil
        }
    }
}
