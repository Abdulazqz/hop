import XCTest
@testable import SwitcherCore

final class SetupTokenTests: XCTestCase {
    func testNormalizeTrimsWhitespaceAndNewlines() throws {
        let token = "sk-ant-oat01-" + String(repeating: "x", count: 90)
        XCTAssertEqual(try SetupToken.normalize("  " + token + "\n"), token)
    }

    func testNormalizeDropsHardLineWrapsInsideTheToken() throws {
        let token = "sk-ant-oat01-" + String(repeating: "x", count: 90)
        let wrapped = String(token.prefix(40)) + "\n" + String(token.dropFirst(40).prefix(30)) + " \r\n" + String(token.dropFirst(70))
        XCTAssertEqual(try SetupToken.normalize(wrapped), token)
    }

    func testEmptyThrowsEmpty() {
        XCTAssertThrowsError(try SetupToken.normalize("   \n")) {
            XCTAssertEqual($0 as? SetupTokenError, .empty)
        }
    }

    func testWrongPrefixThrows() {
        let value = "sk-ant-api03-" + String(repeating: "x", count: 100)
        XCTAssertThrowsError(try SetupToken.normalize(value)) {
            XCTAssertEqual($0 as? SetupTokenError, .wrongPrefix)
        }
    }

    func testTooShortThrows() {
        XCTAssertThrowsError(try SetupToken.normalize("sk-ant-oat01-short")) {
            XCTAssertEqual($0 as? SetupTokenError, .tooShort)
        }
    }
}
