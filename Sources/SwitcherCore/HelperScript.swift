import Foundation

/// Generates the bash `apiKeyHelper` script Claude Code runs for credentials. It reads only the pointer
/// file (an account UUID) and the Keychain, and prints only the token — never a partial or stale value.
/// When there is nothing valid to return it prints nothing and exits 0; Claude Code then reports
/// "apiKeyHelper is failing" (it does not fall back to the Keychain login while a helper is set), so the
/// job here is only ever to avoid emitting a wrong token. Moving sessions to a healthy account is Hop's
/// own auto-failover (a later plan), not Claude Code's.
public enum HelperScript {
    public static func contents(pointerPath: String, tokenService: String) -> String {
        """
        #!/bin/bash
        # Hop apiKeyHelper — prints the active account's setup-token from the Keychain.
        # No token is ever written to disk: this reads a pointer file (an account UUID) and the Keychain only.
        # Missing pointer, empty id, or no stored token => print nothing and exit 0. Claude Code then
        # reports "apiKeyHelper is failing"; the point is only never to emit a wrong or partial token.
        P="\(pointerPath)"
        [ -f "$P" ] || exit 0
        id=$(cat "$P")
        id="${id//[[:space:]]/}"
        [ -n "$id" ] || exit 0
        /usr/bin/security find-generic-password -s "\(tokenService)" -a "$id" -w 2>/dev/null || exit 0
        """
    }
}
