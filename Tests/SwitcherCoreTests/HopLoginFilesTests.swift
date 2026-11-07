import XCTest
@testable import SwitcherCore

final class HopLoginFilesTests: XCTestCase {
    /// Claude Code runs the apiKeyHelper value via `/bin/sh -c`; a space (or shell metachar) in the
    /// installed helper path word-splits it and the helper never runs (exit 127).
    func testHelperScriptPathIsShellSafe() {
        let path = HopLoginFiles.helperScript(home: "/Users/me")
        XCTAssertFalse(path.contains(" "), "helper path must have no space: \(path)")
        XCTAssertFalse(path.contains(where: { "\t\n\"\\$`'".contains($0) }), "helper path must have no shell metachar: \(path)")
    }

    func testPointerSharesTheShellSafeDirectory() {
        XCTAssertFalse(HopLoginFiles.pointer(home: "/Users/me").contains(" "))
    }
}
