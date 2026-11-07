import XCTest
@testable import SwitcherCore

final class HelperScriptTests: XCTestCase {
    let script = HelperScript.contents(pointerPath: "/tmp/hop/active-account", tokenService: "local.hop.token")

    func testStartsWithBashShebang() {
        XCTAssertTrue(script.hasPrefix("#!/bin/bash"), script)
    }

    func testContainsPointerPath() {
        XCTAssertTrue(script.contains("/tmp/hop/active-account"), script)
    }

    func testReadsTokenForPointedAccount() {
        XCTAssertTrue(script.contains(#"find-generic-password -s "local.hop.token""#), script)
        XCTAssertTrue(script.contains(#"-a "$id""#), script)
    }

    func testGuardsMissingPointerAndEmptyId() {
        XCTAssertTrue(script.contains(#"[ -f "$P" ] || exit 0"#), script)
        XCTAssertTrue(script.contains(#"[ -n "$id" ] || exit 0"#), script)
    }
}
