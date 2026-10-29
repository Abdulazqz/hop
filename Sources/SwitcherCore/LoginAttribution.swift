import Foundation

/// Which Hop account the live terminal login belongs to. A login is an email *in an organization*: one claude.ai
/// account can be in several organizations, each with its own login, so the email alone doesn't settle it.
public enum LoginAttribution: Equatable {
    /// The token is the one Hop last wrote, so it belongs to that account even if a stale session rewrote the identity file.
    case hopWrote(UUID)
    /// Same email and organization; or same email against an account whose organization isn't recorded yet.
    case emailMatch(UUID)
    case unknown(email: String)

    public var accountID: UUID? {
        switch self {
        case .hopWrote(let id), .emailMatch(let id): id
        case .unknown: nil
        }
    }

    public static func attribute(_ live: LoginSummary, accounts: [Account], state: HopState) -> LoginAttribution {
        if let hash = state.writtenRefreshTokenSHA256, hash == live.refreshTokenSHA256,
           let id = state.activeAccountID, accounts.contains(where: { $0.id == id }) {
            return .hopWrote(id)
        }
        let wanted = live.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sameEmail = accounts.filter { $0.normalizedEmail == wanted }
        if let organization = live.normalizedOrganizationUuid,
           let match = sameEmail.first(where: { $0.normalizedOrganizationUuid == organization }) {
            return .emailMatch(match.id)
        }
        // An account saved before Hop recorded organizations matches on email alone. One that records a different
        // organization never does: saving under it would overwrite that organization's login.
        if let legacy = sameEmail.first(where: { $0.normalizedOrganizationUuid == nil }) {
            return .emailMatch(legacy.id)
        }
        return .unknown(email: live.email)
    }
}
