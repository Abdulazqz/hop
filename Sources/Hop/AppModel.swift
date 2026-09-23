import Foundation
import SwitcherCore

@MainActor
final class AppModel {
    let fileURL: URL
    let tracker = InstanceTracker()
    private(set) var accounts: [Account]
    var onAccountsChanged: (() -> Void)?

    init(accounts: [Account], fileURL: URL) {
        self.accounts = accounts
        self.fileURL = fileURL
        tracker.accountsProvider = { [unowned self] in self.accounts }
        tracker.refresh()
    }

    /// Validates and saves `new`. On failure nothing changes and the error says why.
    func setAccounts(_ new: [Account]) throws {
        try AccountValidation.validate(new, home: NSHomeDirectory())
        try AccountStore.save(new, to: fileURL)
        accounts = new
        tracker.refresh()
        onAccountsChanged?()
    }
}
