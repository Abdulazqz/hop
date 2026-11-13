import Foundation

public enum SetupTokenError: Error, Equatable, LocalizedError {
    case empty
    case wrongPrefix
    case tooShort

    public var errorDescription: String? {
        switch self {
        case .empty: return "Paste the setup-token."
        case .wrongPrefix: return "That should start with sk-ant-oat01-."
        case .tooShort: return "That setup-token looks too short."
        }
    }
}

/// Validates and normalizes a `claude setup-token` the user pasted into Hop.
public enum SetupToken {
    static let prefix = "sk-ant-oat01-"
    /// Real setup-tokens are ~108 chars; `claude-as` requires well past the prefix, so do we.
    static let minLength = 80

    /// Strips all whitespace/newlines (a token copied from a terminal can carry hard line wraps; a real
    /// token never contains whitespace) and checks the token's shape.
    /// Returns the cleaned token; throws `SetupTokenError` on a bad one.
    public static func normalize(_ raw: String) throws -> String {
        let trimmed = raw.filter { !$0.isWhitespace }
        guard !trimmed.isEmpty else { throw SetupTokenError.empty }
        guard trimmed.hasPrefix(prefix) else { throw SetupTokenError.wrongPrefix }
        guard trimmed.count > minLength else { throw SetupTokenError.tooShort }
        return trimmed
    }
}
