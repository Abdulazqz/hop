import XCTest
@testable import SwitcherCore

final class LoginAttributionTests: XCTestCase {
    let work = Account(name: "Work", color: .teal, folder: "~/w", email: "work@example.com")
    let home = Account(name: "Home", color: .blue, folder: "~/h", email: "home@example.com")
    func live(email: String, refresh: String = "rt") -> LoginSummary {
        LoginSummary(email: email, refreshTokenSHA256: LiveLogin.sha256Hex(refresh), expiresAt: .distantFuture, refreshTokenExpiresAt: .distantFuture)
    }

    func testHashMatchBeatsEmail() {
        let state = HopState(activeAccountID: work.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt"))
        XCTAssertEqual(LoginAttribution.attribute(live(email: "home@example.com"), accounts: [work, home], state: state), .hopWrote(work.id))
    }

    func testHashMatchForUnknownAccountFallsBackToEmail() {
        let state = HopState(activeAccountID: UUID(), writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt"))
        XCTAssertEqual(LoginAttribution.attribute(live(email: "home@example.com"), accounts: [work, home], state: state), .emailMatch(home.id))
    }

    func testEmailMatchIsCaseInsensitive() {
        XCTAssertEqual(LoginAttribution.attribute(live(email: "WORK@example.com"), accounts: [work, home], state: .empty), .emailMatch(work.id))
    }

    func testUnknownEmail() {
        let result = LoginAttribution.attribute(live(email: "new@example.com"), accounts: [work], state: .empty)
        XCTAssertEqual(result, .unknown(email: "new@example.com"))
        XCTAssertNil(result.accountID)
        XCTAssertEqual(LoginAttribution.emailMatch(work.id).accountID, work.id)
    }
}
