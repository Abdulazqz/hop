import Foundation

/// A browser Hop opens on its own profile for one account, so each account has its own claude.ai sign-in:
/// nothing is shared with the user's normal browser windows or with another account's. The profile is kept,
/// so an account signs in there once and later renewals are just "Authorize". Chromium browsers all take
/// `--user-data-dir`, which runs a separate instance on that profile that Hop can close afterwards.
/// (Incognito windows aren't used: they share one session while any is open, so a second account would
/// arrive already signed in as the first.)
public struct PrivateBrowser: Equatable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// Supported browsers, in the order Hop prefers them when the default browser isn't one.
    public static let known: [PrivateBrowser] = [
        PrivateBrowser(bundleID: "com.google.Chrome", name: "Chrome"),
        PrivateBrowser(bundleID: "com.brave.Browser", name: "Brave"),
        PrivateBrowser(bundleID: "com.microsoft.edgemac", name: "Edge"),
        PrivateBrowser(bundleID: "org.chromium.Chromium", name: "Chromium"),
        PrivateBrowser(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi"),
    ]

    /// The default browser when it's supported, else the first supported one installed, else nil.
    public static func choose(defaultBundleID: String?, installed: Set<String>) -> PrivateBrowser? {
        if let defaultBundleID, installed.contains(defaultBundleID),
           let browser = known.first(where: { $0.bundleID.caseInsensitiveCompare(defaultBundleID) == .orderedSame }) {
            return browser
        }
        return known.first { installed.contains($0.bundleID) }
    }

    /// The script handed to `claude setup-token` as `$BROWSER`: `claude` runs it with the sign-in URL as its
    /// only argument, and it opens that URL in a new instance of the browser on `profileDirectory`.
    public static func openerScript(appPath: String, profileDirectory: String) -> String {
        """
        #!/bin/bash
        # Hop: open the Claude sign-in page in this account's own browser profile.
        exec /usr/bin/open -n -a \(shellQuoted(appPath)) --args \(shellQuoted("--user-data-dir=" + profileDirectory)) \
        --no-first-run --no-default-browser-check --new-window "$1"

        """
    }

    /// Whether a running browser's argv is the instance Hop opened on `profileDirectory`.
    public static func isInstance(argv: [String], profileDirectory: String) -> Bool {
        ProcessArgs.userDataDir(from: argv) == profileDirectory
    }

    /// Where an account's browser profile lives, under Hop's support folder.
    public static func profileDirectory(for id: UUID, in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent("Browser", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Single-quoted for bash; a `'` inside becomes `'\''`.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
