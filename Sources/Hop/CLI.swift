import AppKit
import SwitcherCore

/// `Hop status | open <n> | quit <n>` (n = 1-based menu position).
@MainActor
enum CLI {
    static let commands: Set<String> = ["status", "open", "quit"]

    static func run(_ args: [String]) -> Int32 {
        _ = NSApplication.shared   // Focuser uses NSApp
        let (accounts, _) = AccountStore.loadOrSeed(from: AccountStore.defaultURL, home: NSHomeDirectory())
        let model = AppModel(accounts: accounts, fileURL: AccountStore.defaultURL)
        let launcher = Launcher(model: model) { title, info in print("error: \(title). \(info)") }

        if args[0] == "status" {
            for (i, account) in model.accounts.enumerated() {
                let app = model.tracker.running[account.id]
                let state = app.map { "running\tpid \($0.processIdentifier)" } ?? "closed\t-"
                print("\(i + 1)\t\(account.name)\t\(state)\t\(account.folder ?? FolderPath.defaultProfile)")
            }
            return 0
        }

        guard args.count == 2, let n = Int(args[1]), model.accounts.indices.contains(n - 1) else {
            print("usage: Hop \(args[0]) <1-\(model.accounts.count)>")
            return 2
        }
        let account = model.accounts[n - 1]
        if args[0] == "quit" {
            let sent = model.tracker.running[account.id]?.terminate() ?? false
            print(sent ? "quit sent to \(account.name)" : "\(account.name) isn't running")
            return 0
        }
        var done = false
        launcher.open(account) { done = true }
        let deadline = Date().addingTimeInterval(20)
        while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        model.tracker.refresh()
        print(model.tracker.isRunning(account) ? "\(account.name) running" : "\(account.name) didn't start")
        return model.tracker.isRunning(account) ? 0 : 1
    }
}
