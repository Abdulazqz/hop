import AppKit
import SwiftUI
import SwitcherCore

@MainActor
final class EditAccountsWindow {
    private let model: AppModel
    private let switcher: SwitchController
    private let tokenStore: TokenStore
    private var window: NSWindow?

    init(model: AppModel, switcher: SwitchController, tokenStore: TokenStore = KeychainTokenStore()) {
        self.model = model
        self.switcher = switcher
        self.tokenStore = tokenStore
    }

    /// Opens a fresh editor (so it always starts from the saved accounts), or fronts the open one.
    func show() {
        NSApp.activate()
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = EditAccountsView(model: model, switcher: switcher, tokenStore: tokenStore) { [weak self] in self?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Edit accounts"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func close() {
        // Deferred so the window isn't freed while its own Save/Cancel action is still running.
        DispatchQueue.main.async { [weak self] in
            self?.window?.close()
            self?.window = nil
        }
    }
}

private struct EditAccountsView: View {
    let model: AppModel
    let switcher: SwitchController
    let tokenStore: TokenStore
    let close: () -> Void
    @State private var accounts: [Account]
    @State private var accountsToTrash: [Account] = []
    @State private var pendingRemoval: Account?
    @State private var error: String?

    init(model: AppModel, switcher: SwitchController, tokenStore: TokenStore, close: @escaping () -> Void) {
        self.model = model
        self.switcher = switcher
        self.tokenStore = tokenStore
        self.close = close
        _accounts = State(initialValue: model.accounts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach($accounts) { $account in
                    HStack(spacing: 8) {
                        Circle().fill(Color(nsColor: account.color.nsColor)).frame(width: 10, height: 10)
                        Picker("Color", selection: $account.color) {
                            ForEach(AccountColor.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        TextField("Name", text: $account.name)
                        Text(folderLabel(account))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if account.tokenAddedAt != nil {
                            Image(systemName: "key.fill").foregroundStyle(.secondary).help("Has a setup-token")
                            Button("Replace") { setToken(for: account) }.buttonStyle(.borderless).font(.caption)
                            Button("Remove") { removeToken(for: account) }.buttonStyle(.borderless).font(.caption)
                        } else {
                            Button("Add token") { setToken(for: account) }.buttonStyle(.borderless).font(.caption)
                        }
                        Button { pendingRemoval = account } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove account")
                    }
                }
                .onMove { accounts.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 180)

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Text("Drag to reorder. Row 1 is ⌃⌥1.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: close)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 480)
        .sheet(item: $pendingRemoval) { account in
            RemoveAccountSheet(account: account, canTrashFolder: canTrashFolder(account)) { trash in
                accounts.removeAll { $0.id == account.id }
                if trash { accountsToTrash.append(account) }
                pendingRemoval = nil
            } onCancel: {
                pendingRemoval = nil
            }
        }
    }

    private func setToken(for account: Account) {
        guard let raw = TokenPrompt.paste(accountName: account.name) else { return }
        do {
            let token = try SetupToken.normalize(raw)
            try tokenStore.writeToken(token, for: account.id)
            let now = Date()
            try model.setTokenState(now, for: account.id)
            if let i = accounts.firstIndex(where: { $0.id == account.id }) { accounts[i].tokenAddedAt = now }
            error = nil
        } catch {
            self.error = message(for: error)
        }
    }

    private func removeToken(for account: Account) {
        // The helper would find no token for the account every session is on, and sign them all out.
        if account.id == switcher.activeAccountID, switcher.loginEnabled {
            error = "\(account.name) is the active Claude login. Switch to another account first, or stop using Hop as your Claude login."
            return
        }
        do {
            try tokenStore.deleteToken(account.id)
            try model.setTokenState(nil, for: account.id)
            if let i = accounts.firstIndex(where: { $0.id == account.id }) { accounts[i].tokenAddedAt = nil }
            error = nil
        } catch {
            self.error = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case SetupTokenError.empty: return "Paste the setup-token."
        case SetupTokenError.wrongPrefix: return "That should start with sk-ant-oat01-."
        case SetupTokenError.tooShort: return "That setup-token looks too short."
        default: return error.localizedDescription
        }
    }

    private func folderLabel(_ account: Account) -> String {
        account.folder.map { ($0 as NSString).lastPathComponent } ?? "Claude (default)"
    }

    /// Never trash the default profile, a folder outside our own Claude-* folders, or one a running instance is using.
    private func canTrashFolder(_ account: Account) -> Bool {
        FolderPath.isTrashable(account.folder, home: NSHomeDirectory()) && !model.tracker.isRunning(account)
    }

    private func save() {
        let trimmed = accounts.map { account -> Account in
            var account = account
            account.name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return account
        }
        model.tracker.refresh()
        let safe = accountsToTrash.filter { canTrashFolder($0) }
        let kept = accountsToTrash.filter { !canTrashFolder($0) }
        // Decide token/pointer cleanup against the accounts as they are BEFORE the save.
        let before = model.accounts
        let (removedTokenIDs, clearPointer) = AccountRemoval.cleanup(before: before, after: trimmed,
                                                                     active: switcher.activeAccountID)
        do {
            try model.setAccounts(trimmed)
        } catch {
            self.error = error.localizedDescription
            return
        }
        // Don't leave an orphaned token behind, or a pointer naming an account the user just removed.
        let orphaned = removedTokenIDs.filter { (try? tokenStore.deleteToken($0)) == nil }
        if clearPointer { switcher.deactivate() }
        if !orphaned.isEmpty {
            let names = before.filter { orphaned.contains($0.id) }.map(\.name).joined(separator: ", ")
            Alerts.show("Couldn't delete the setup-token for \(names)",
                        "It's still in the Keychain under \u{201c}\(TokenStoreConst.service)\u{201d}. Delete it in Keychain Access.")
        }
        for account in safe {
            let url = URL(fileURLWithPath: FolderPath.normalize(account.folder, home: NSHomeDirectory()))
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        if !kept.isEmpty {
            let names = kept.map(\.name).joined(separator: ", ")
            Alerts.show("Kept the data folder for \(names)",
                        "It was running when you saved. Quit it, then move its folder to the Trash yourself.")
        }
        close()
    }
}

private struct RemoveAccountSheet: View {
    let account: Account
    let canTrashFolder: Bool
    let onRemove: (Bool) -> Void
    let onCancel: () -> Void
    @State private var trashFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remove “\(account.name)”?").font(.headline)
            Text("It leaves Hop. Its desktop sign-in stays in its folder unless you move the folder to the Trash; its saved terminal login is deleted.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Also move its data folder to the Trash", isOn: $trashFolder)
                .disabled(!canTrashFolder)
            if !canTrashFolder {
                Text("Not available for the default Claude folder or an account that's running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Remove", role: .destructive) { onRemove(trashFolder && canTrashFolder) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
