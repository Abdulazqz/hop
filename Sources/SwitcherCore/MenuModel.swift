import Foundation

public enum SwitchLabel: Equatable { case active, switchLogin, needsToken }
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

/// Everything the status menu shows, computed without AppKit so it can be tested. The active account
/// comes from the pointer (the same file the apiKeyHelper reads); a row is token-backed when Hop holds
/// a setup-token for it.
public struct MenuModel: Equatable {
    public let header: String
    public let sessionsLine: String?
    public let rows: [MenuRow]
    public let activeAccountID: UUID?

    public static func build(accounts: [Account], activeAccountID: UUID?, tokenBacked: Set<UUID>,
                             desktopRunning: Set<UUID>, runningSessions: Int,
                             hotkeyAction: HotkeyAction, hotkeyPositions: Set<Int>,
                             loginEnabled: Bool = true) -> MenuModel {
        let activeName = activeAccountID.flatMap { id in accounts.first { $0.id == id }?.name }
        let header = activeName.map { "Active: \($0)" } ?? "No account active"

        let rows = accounts.enumerated().map { position, account -> MenuRow in
            let isActive = account.id == activeAccountID
            let backed = tokenBacked.contains(account.id)
            let running = desktopRunning.contains(account.id)
            return MenuRow(
                accountID: account.id,
                title: account.name,
                hint: hotkeyAction != .off && hotkeyPositions.contains(position) ? "⌃⌥\(position + 1)" : nil,
                isActive: isActive,
                desktopRunning: running,
                switchLabel: isActive ? .active : (backed ? .switchLogin : .needsToken),
                terminalLabel: backed ? .openTerminal : .logInFirst,
                desktopLabel: running ? "Bring Claude app to front" : "Open Claude app")
        }

        // Sessions only follow a switch while Hop is the Claude login; otherwise they keep their own login.
        let sessionsLine: String? = runningSessions == 0 || !loginEnabled ? nil
            : runningSessions == 1 ? "1 terminal session running · it follows on its next turn"
            : "\(runningSessions) terminal sessions running · they follow on their next turn"

        return MenuModel(header: header, sessionsLine: sessionsLine, rows: rows, activeAccountID: activeAccountID)
    }
}
