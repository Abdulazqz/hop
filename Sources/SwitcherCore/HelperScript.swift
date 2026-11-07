import Foundation

/// Generates the bash `apiKeyHelper` script Claude Code runs for credentials. It reads only the pointer
/// file (an account UUID) and the Keychain, prints only the token (never a partial value), and exits 0
/// with no output whenever there is nothing valid to return — so Claude Code falls back to its last
/// working token instead of treating the helper as failed.
public enum HelperScript {
    public static func contents(pointerPath: String, tokenService: String) -> String {
        """
        #!/bin/bash
        # Hop apiKeyHelper — prints the active account's setup-token from the Keychain.
        # No token is ever written to disk: this reads a pointer file (an account UUID) and the Keychain only.
        # Missing pointer, empty id, or no stored token => print nothing and exit 0, so Claude Code falls
        # back to its last working token rather than reporting the helper as failing.
        P="\(pointerPath)"
        [ -f "$P" ] || exit 0
        id=$(cat "$P")
        id="${id//[[:space:]]/}"
        [ -n "$id" ] || exit 0
        /usr/bin/security find-generic-password -s "\(tokenService)" -a "$id" -w 2>/dev/null || exit 0
        """
    }
}
