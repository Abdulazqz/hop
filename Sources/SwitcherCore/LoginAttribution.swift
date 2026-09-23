import Foundation

/// Which Hop account the live terminal login belongs to.
public enum LoginAttribution: Equatable {
    /// The token is the one Hop last wrote, so it belongs to that account even if a stale session rewrote the identity file.
    case hopWrote(UUID)
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
        if let match = accounts.first(where: { $0.normalizedEmail == wanted }) {
            return .emailMatch(match.id)
        }
        return .unknown(email: live.email)
    }
}
