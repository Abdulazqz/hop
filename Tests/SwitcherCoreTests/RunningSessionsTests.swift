import XCTest
@testable import SwitcherCore

final class RunningSessionsTests: XCTestCase {
    func testNativeLauncherSessionIsCounted() {
        XCTAssertTrue(RunningSessions.isClaudeSession(name: "2.1.280",
                                                      path: "/Users/me/.local/share/claude/versions/2.1.280",
                                                      argv: ["claude", "--dangerously-skip-permissions"]))
    }

    func testPlainClaudeNameIsCounted() {
        XCTAssertTrue(RunningSessions.isClaudeSession(name: "claude", path: "/usr/local/bin/claude", argv: ["/usr/local/bin/claude"]))
    }

    func testNpmInstallUnderNodeIsCounted() {
        XCTAssertTrue(RunningSessions.isClaudeSession(name: "node", path: "/opt/homebrew/bin/node",
                                                      argv: ["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"]))
    }

    func testDesktopAppAndHelpersAreNotCounted() {
        XCTAssertFalse(RunningSessions.isClaudeSession(name: "Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude", argv: ["/Applications/Claude.app/Contents/MacOS/Claude"]))
        XCTAssertFalse(RunningSessions.isClaudeSession(name: "claude-helper", path: "/x/claude-helper", argv: ["claude-helper"]))
        XCTAssertFalse(RunningSessions.isClaudeSession(name: "node", path: "/opt/homebrew/bin/node", argv: ["node", "server.js"]))
    }

    func testCountSumsMatches() {
        let processes: [(name: String, path: String, argv: [String])] = [
            ("2.1.280", "/Users/me/.local/share/claude/versions/2.1.280", ["claude"]),
            ("Claude", "/Applications/Claude.app/Contents/MacOS/Claude", ["Claude"]),
            ("claude", "/usr/local/bin/claude", ["claude", "-p"]),
        ]
        XCTAssertEqual(RunningSessions.count(processes: processes), 2)
    }

    func testLiveCountDoesNotCrash() {
        XCTAssertGreaterThanOrEqual(RunningSessions.count(), 0)
    }
}
