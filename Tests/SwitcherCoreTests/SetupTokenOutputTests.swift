import XCTest
@testable import SwitcherCore

final class SetupTokenOutputTests: XCTestCase {
    let token = "sk-ant-oat01-" + String(repeating: "Ab3_-", count: 19)   // 108 characters, like a real one

    func testFindsTheTokenOnItsOwnLine() {
        let output = "\u{2713} Long-lived authentication token created successfully!\r\n\r\nYour OAuth token (valid for 1 year):\r\n\(token)\r\nStore this token securely.\r\n"
        XCTAssertEqual(SetupTokenOutput.token(in: output), token)
    }

    func testFindsTheTokenInsideColorCodes() {
        let output = "\u{1B}[33m\(token)\u{1B}[39m\u{1B}[1C\u{1B}[2mStore\u{1B}[22m"
        XCTAssertEqual(SetupTokenOutput.token(in: output), token)
    }

    func testWaitsUntilTheTokenIsPrintedInFull() {
        XCTAssertNil(SetupTokenOutput.token(in: "Your OAuth token:\r\n\(token)"))
        XCTAssertNil(SetupTokenOutput.token(in: "Your OAuth token:\r\n\(token.prefix(60))"))
    }

    func testIgnoresTooShortMatches() {
        XCTAssertNil(SetupTokenOutput.token(in: "use sk-ant-oat01-abc here\n"))
    }

    func testNoTokenWhileWaitingForTheBrowser() {
        let output = "\u{1B}[?2026h\u{1B}[2K\u{1B}[GThis\u{1B}[1Cwill\u{1B}[1Cguide\u{1B}[1Cyou\r\n"
            + "Browser\u{1B}[1Cdidn't\u{1B}[1Copen?\r\n\u{1B}]8;;https://claude.com/cai/oauth/authorize?code=true\u{07}https://claude.com/cai/oauth/authorize?code=true\u{1B}]8;;\u{07}\r\n"
            + "Paste\u{1B}[1Ccode\u{1B}[1Chere\u{1B}[1Cif\u{1B}[1Cprompted\u{1B}[1C>\u{1B}[?2026l"
        XCTAssertNil(SetupTokenOutput.token(in: output))
        XCTAssertEqual(SetupTokenOutput.lastLine(of: output), "Paste code here if prompted >")
    }

    func testStripTurnsCursorMovesIntoSpacesAndLines() {
        XCTAssertEqual(SetupTokenOutput.stripEscapes("a\u{1B}[1Cb\u{1B}[1Ac\u{1B}[0;1mbold\u{1B}[0m"), "a b\ncbold")
        XCTAssertEqual(SetupTokenOutput.stripEscapes("\u{1B}]0;title\u{1B}\\x\u{1B}=y"), "xy")
    }
}
