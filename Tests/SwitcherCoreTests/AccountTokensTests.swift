import XCTest
@testable import SwitcherCore

final class AccountTokensTests: XCTestCase {
    func testSetMarksOnlyTheTargetAccount() {
        let a = Account(name: "A", color: .gray, folder: nil)
        let b = Account(name: "B", color: .teal, folder: nil)
        let date = Date(timeIntervalSinceReferenceDate: 100)
        let out = AccountTokens.apply([a, b], tokenAddedAt: date, for: b.id)
        XCTAssertNil(out[0].tokenAddedAt)
        XCTAssertEqual(out[1].tokenAddedAt, date)
    }

    func testClearRemovesTheMarker() {
        var a = Account(name: "A", color: .gray, folder: nil)
        a.tokenAddedAt = Date()
        let out = AccountTokens.apply([a], tokenAddedAt: nil, for: a.id)
        XCTAssertNil(out[0].tokenAddedAt)
    }
}
