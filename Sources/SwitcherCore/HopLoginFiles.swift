import Foundation

/// Where Hop keeps its as-login artifacts. The directory MUST be free of whitespace and shell
/// metacharacters: Claude Code runs the `apiKeyHelper` value through `/bin/sh -c`, so a path with a
/// space would word-split and fail with exit 127 before the helper ever runs.
public enum HopLoginFiles {
    public static func directory(home: String) -> String { home + "/.config/hop" }
    public static func helperScript(home: String) -> String { directory(home: home) + "/hop-apikeyhelper.sh" }
    public static func pointer(home: String) -> String { directory(home: home) + "/active-account" }
}
