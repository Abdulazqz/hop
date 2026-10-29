import Foundation

public enum SwitchLabel: Equatable { case active, switchLogin, logInFirst }
public enum TerminalLabel: Equatable { case openTerminal, logInFirst }

public struct MenuRow: Equatable {
    public let accountID: UUID
    public let title: String
    public let hint: String?
    public let isActive: Bool
    public let desktopRunning: Bool
    public let switchLabel: SwitchLabel
    public let terminalLabel: TerminalLabel
    public let desktopLabel: String
}

/// Everything the status menu shows, computed without AppKit so it can be tested.
public struct MenuModel: Equatable {
    public let header: String
    public let sessionsLine: String?
    public let rows: [MenuRow]
    /// Set when the live login matches no account: show "Save current login (email · organization) as new account…".
    public let saveCurrentLoginLabel: String?
    public let activeAccountID: UUID?

    public static func build(accounts: [Account], live: LiveLoginState, state: HopState, savedLoginExpiry: [UUID: Date],
                             hasSavedLogin: Set<UUID>, desktopRunning: Set<UUID>, runningSessions: Int,
                             hotkeyAction: HotkeyAction, hotkeyPositions: Set<Int>, now: Date) -> MenuModel {
        var activeID: UUID?
        var unknownLogin: String?
        let header: String
        switch live {
        case .loggedIn(let summary):
            let attribution = LoginAttribution.attribute(summary, accounts: accounts, state: state)
            activeID = attribution.accountID
            if let activeID, let account = accounts.first(where: { $0.id == activeID }) {
                header = "Active: \(account.name) (\(account.loginLabel ?? summary.label))"
            } else {
                unknownLogin = summary.label
                header = "Active: \(summary.label) (not saved)"
            }
        case .loggedOut:
            header = "Not logged in"
        case .unrecognized:
            header = "Login format not recognized"
        }

        let rows = accounts.enumerated().map { position, account -> MenuRow in
            let isActive = account.id == activeID
            let running = desktopRunning.contains(account.id)
            let saved = hasSavedLogin.contains(account.id)
            return MenuRow(
                accountID: account.id,
                title: account.name + (saved ? expirySuffix(savedLoginExpiry[account.id], now: now) : ""),
                hint: hotkeyAction != .off && hotkeyPositions.contains(position) ? "⌃⌥\(position + 1)" : nil,
                isActive: isActive,
                desktopRunning: running,
                switchLabel: isActive ? .active : (saved ? .switchLogin : .logInFirst),
                terminalLabel: saved ? .openTerminal : .logInFirst,
                desktopLabel: running ? "Bring Claude app to front" : "Open Claude app")
        }

        let sessionsLine: String? = runningSessions == 0 ? nil
            : runningSessions == 1 ? "1 terminal session running · it follows within 8 hours"
            : "\(runningSessions) terminal sessions running · they follow within 8 hours"

        return MenuModel(header: header, sessionsLine: sessionsLine, rows: rows,
                         saveCurrentLoginLabel: unknownLogin, activeAccountID: activeID)
    }

    static func expirySuffix(_ expiry: Date?, now: Date) -> String {
        guard let expiry else { return "" }
        let seconds = expiry.timeIntervalSince(now)
        if seconds <= 0 { return " · login expired" }
        let days = Int(seconds / 86_400)
        return days < 7 ? " · login expires in \(days) day\(days == 1 ? "" : "s")" : ""
    }
}
