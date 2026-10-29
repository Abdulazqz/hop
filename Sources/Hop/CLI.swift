import AppKit
import SwitcherCore

/// `Hop status | open <n> | quit <n>` (n = 1-based menu position).
@MainActor
enum CLI {
    static let commands: Set<String> = ["status", "open", "quit", "probe-login", "switch"]

    static func run(_ args: [String]) -> Int32 {
        _ = NSApplication.shared   // Focuser uses NSApp
        let (accounts, _) = AccountStore.loadOrSeed(from: AccountStore.defaultURL, home: NSHomeDirectory())
        let model = AppModel(accounts: accounts, fileURL: AccountStore.defaultURL)
        let launcher = Launcher(model: model) { title, info in print("error: \(title). \(info)") }

        if args[0] == "probe-login" {
            // Read-only. Prints what Hop can see, never a token. A read error is reported, not shown as "logged out".
            let live: LiveLoginState
            do {
                live = LiveLogin.parse(keychainValue: try KeychainLoginStore().readLive(),
                                       identityDocument: try IdentityDocumentFile().read())
            } catch {
                print("error: \(error.localizedDescription)")
                return 1
            }
            switch live {
            case .loggedIn(let s): print("logged in as \(s.label); login expires \(s.expiresAt); refresh expires \(s.refreshTokenExpiresAt)")
            case .loggedOut: print("logged out")
            case .unrecognized(let why): print("unrecognized: \(why)")
            }
            print("running claude sessions: \(RunningSessions.count())")
            return 0
        }

        if args[0] == "status" {
            let switcher = SwitchController(model: model, interactive: false) { print("error: \($0.localizedDescription)") }
            let active = switcher.activeAccountID
            for (i, account) in model.accounts.enumerated() {
                let app = model.tracker.running[account.id]
                let desktop = app.map { "running\tpid \($0.processIdentifier)" } ?? "closed\t-"
                let mark = account.id == active ? "*" : " "
                print("\(i + 1)\t\(mark)\t\(account.name)\t\(account.loginLabel ?? "-")\t\(desktop)\t\(account.folder ?? FolderPath.defaultProfile)")
            }
            if case .loggedIn(let s) = switcher.live, active == nil { print("terminal login \(s.label) isn't saved in Hop") }
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
        if args[0] == "switch" {
            let switcher = SwitchController(model: model, interactive: false) { print("error: \($0.localizedDescription)") }
            let live = switcher.live
            if case .loggedIn(let s) = live, switcher.activeAccountID == nil {
                print("error: current login (\(s.label)) isn't saved; save it from the menu first")
                return 1
            }
            let ok = switcher.switchTo(account)
            print(ok ? "active: \(account.name)" : "switch failed")
            return ok ? 0 : 1
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
