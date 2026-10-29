import XCTest
@testable import SwitcherCore

final class LoginAttributionTests: XCTestCase {
    let work = Account(name: "Work", color: .teal, folder: "~/w", email: "work@example.com")
    let home = Account(name: "Home", color: .blue, folder: "~/h", email: "home@example.com")
    let personal = Account(name: "Me (Personal)", color: .coral, folder: "~/mp", email: "me@example.com",
                           organizationUuid: "org-p", organizationName: "Personal")
    let team = Account(name: "Me (Team)", color: .blue, folder: "~/mt", email: "me@example.com",
                       organizationUuid: "org-t", organizationName: "Team")
    func live(email: String, refresh: String = "rt", organization: String? = nil) -> LoginSummary {
        LoginSummary(email: email, refreshTokenSHA256: LiveLogin.sha256Hex(refresh), expiresAt: .distantFuture, refreshTokenExpiresAt: .distantFuture,
                     organizationUuid: organization, organizationName: organization.map { "Org \($0)" })
    }
    func attribute(_ summary: LoginSummary, _ accounts: [Account]) -> LoginAttribution {
        LoginAttribution.attribute(summary, accounts: accounts, state: .empty)
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

    // One claude.ai account can belong to several organizations, each with its own login.

    func testSameEmailInTwoOrganizationsMatchesByOrganization() {
        XCTAssertEqual(attribute(live(email: "me@example.com", organization: "org-t"), [personal, team]), .emailMatch(team.id))
        XCTAssertEqual(attribute(live(email: "ME@example.com", organization: "org-p"), [personal, team]), .emailMatch(personal.id))
    }

    func testSameEmailInAnUnknownOrganizationIsUnknown() {
        // Never attribute to an account whose recorded organization differs: saving would overwrite that organization's login.
        XCTAssertEqual(attribute(live(email: "me@example.com", organization: "org-x"), [personal, team]), .unknown(email: "me@example.com"))
    }

    func testEmailAloneMatchesOnlyAnAccountWithoutARecordedOrganization() {
        let legacy = Account(name: "Legacy", color: .gray, folder: "~/l", email: "me@example.com")
        XCTAssertEqual(attribute(live(email: "me@example.com", organization: "org-x"), [team, legacy]), .emailMatch(legacy.id))
        XCTAssertEqual(attribute(live(email: "me@example.com"), [team, legacy]), .emailMatch(legacy.id))
        XCTAssertEqual(attribute(live(email: "me@example.com"), [team]), .unknown(email: "me@example.com"))
    }

    func testExactOrganizationMatchBeatsALegacyAccount() {
        let legacy = Account(name: "Legacy", color: .gray, folder: "~/l", email: "me@example.com")
        XCTAssertEqual(attribute(live(email: "me@example.com", organization: "org-t"), [legacy, team]), .emailMatch(team.id))
    }

    func testHashMatchStillBeatsOrganization() {
        let state = HopState(activeAccountID: personal.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt"))
        XCTAssertEqual(LoginAttribution.attribute(live(email: "me@example.com", organization: "org-t"), accounts: [personal, team], state: state),
                       .hopWrote(personal.id))
    }
}
