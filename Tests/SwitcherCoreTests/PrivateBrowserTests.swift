import XCTest
@testable import SwitcherCore

final class PrivateBrowserTests: XCTestCase {
    let chrome = "com.google.Chrome", brave = "com.brave.Browser", edge = "com.microsoft.edgemac"

    func testPrefersTheDefaultBrowserWhenSupported() {
        XCTAssertEqual(PrivateBrowser.choose(defaultBundleID: brave, installed: [chrome, brave])?.name, "Brave")
        XCTAssertEqual(PrivateBrowser.choose(defaultBundleID: "com.google.chrome", installed: [chrome, brave])?.name, "Chrome")
    }

    func testFallsBackInPreferenceOrder() {
        XCTAssertEqual(PrivateBrowser.choose(defaultBundleID: "com.apple.Safari", installed: [edge, brave])?.name, "Brave")
        XCTAssertEqual(PrivateBrowser.choose(defaultBundleID: nil, installed: [edge])?.name, "Edge")
    }

    func testNilWhenNoSupportedBrowserIsInstalled() {
        XCTAssertNil(PrivateBrowser.choose(defaultBundleID: "com.apple.Safari", installed: ["com.apple.Safari"]))
    }

    func testOpenerScriptQuotesPathsAndPassesTheURL() throws {
        let script = PrivateBrowser.openerScript(appPath: "/Applications/Google Chrome.app",
                                                 profileDirectory: "/tmp/o'brien/profile")
        XCTAssertTrue(script.hasPrefix("#!/bin/bash\n"), script)
        XCTAssertTrue(script.contains("-n -a '/Applications/Google Chrome.app'"), script)
        XCTAssertTrue(script.contains(#"'--user-data-dir=/tmp/o'\''brien/profile'"#), script)
        XCTAssertTrue(script.contains(#"--new-window "$1""#), script)

        // bash must accept it.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hop-opener-\(UUID().uuidString).sh")
        try Data(script.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let bash = Process()
        bash.executableURL = URL(fileURLWithPath: "/bin/bash")
        bash.arguments = ["-n", file.path]
        try bash.run()
        bash.waitUntilExit()
        XCTAssertEqual(bash.terminationStatus, 0)
    }

    func testEachAccountHasItsOwnProfileUnderHop() {
        let support = URL(fileURLWithPath: "/Users/me/Library/Application Support/Hop")
        let a = UUID(), b = UUID()
        let pa = PrivateBrowser.profileDirectory(for: a, in: support).path
        XCTAssertEqual(pa, "/Users/me/Library/Application Support/Hop/Browser/\(a.uuidString)")
        XCTAssertNotEqual(pa, PrivateBrowser.profileDirectory(for: b, in: support).path)
        // A path with a space still reaches Chrome as one argument.
        XCTAssertTrue(PrivateBrowser.openerScript(appPath: "/A.app", profileDirectory: pa)
            .contains("'--user-data-dir=\(pa)'"))
    }

    func testRecognizesTheInstance() {
        let argv = ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "--user-data-dir=/tmp/x/profile", "--no-first-run"]
        XCTAssertTrue(PrivateBrowser.isInstance(argv: argv, profileDirectory: "/tmp/x/profile"))
        XCTAssertFalse(PrivateBrowser.isInstance(argv: ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"],
                                                          profileDirectory: "/tmp/x/profile"))
    }
}
