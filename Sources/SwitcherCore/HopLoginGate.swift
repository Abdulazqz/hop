import Foundation

/// Guards turning Hop into the Claude login: it refuses unless at least one account has a stored
/// setup-token AND the account chosen to start active is one of them — so enabling never points
/// every session at an empty helper the instant Claude Code reloads its settings.
public enum HopLoginGate {
    /// Why Hop-as-login can't be enabled yet, or nil when it can.
    public static func blockReason(accounts: [Account], initialActive: UUID?) -> String? {
        let backed = accounts.filter { $0.tokenAddedAt != nil }
        if backed.isEmpty {
            return "Add a setup-token to at least one account first."
        }
        guard let initialActive, backed.contains(where: { $0.id == initialActive }) else {
            return "Choose which token-backed account to start active."
        }
        return nil
    }
}
