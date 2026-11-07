import Foundation

public enum SetupTokenError: Error, Equatable {
    case empty
    case wrongPrefix
    case tooShort
}

/// Validates and normalizes a `claude setup-token` the user pasted into Hop.
public enum SetupToken {
    static let prefix = "sk-ant-oat01-"
    /// Real setup-tokens are ~108 chars; `claude-as` requires well past the prefix, so do we.
    static let minLength = 80

    /// Strips surrounding whitespace/newlines and checks the token's shape.
    /// Returns the trimmed token; throws `SetupTokenError` on a bad one.
    public static func normalize(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SetupTokenError.empty }
        guard trimmed.hasPrefix(prefix) else { throw SetupTokenError.wrongPrefix }
        guard trimmed.count > minLength else { throw SetupTokenError.tooShort }
        return trimmed
    }
}
