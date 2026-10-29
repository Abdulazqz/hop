import XCTest
@testable import SwitcherCore

final class SavedLoginTests: XCTestCase {
    let captured = Date(timeIntervalSince1970: 1_800_000_000)

    func sample(refresh: String = "rt-s", refreshExpiresAt: Double = LoginFixtures.farFuture) throws -> SavedLogin {
        SavedLogin(loginSection: try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: refresh, refreshTokenExpiresAt: refreshExpiresAt)),
                   identity: try XCTUnwrap(try IdentityDocument.identity(of: LoginFixtures.identityDocument(email: "s@example.com"))),
                   capturedAt: captured)
    }

    func testRoundTrip() throws {
        let saved = try sample()
        let decoded = try SavedLogin.decode(try saved.encoded())
        XCTAssertEqual(decoded.email, "s@example.com")
        XCTAssertEqual(decoded.capturedAt.timeIntervalSince1970, captured.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.refreshTokenSHA256, LiveLogin.sha256Hex("rt-s"))
        XCTAssertEqual(LoginFixtures.json(decoded.loginSection)["refreshToken"] as? String, "rt-s")
    }

    func testEncodedShape() throws {
        let object = LoginFixtures.json(try sample().encoded())
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertNotNil(object["claudeAiOauth"] as? [String: Any])
        XCTAssertNotNil(object["oauthAccount"] as? [String: Any])
        XCTAssertNotNil(object["capturedAt"] as? String)
    }

    func testDerivedValues() throws {
        XCTAssertEqual(try sample(refreshExpiresAt: 2_000).refreshTokenExpiresAt, Date(timeIntervalSince1970: 2))
    }

    func testOrganizationComesFromTheSavedIdentity() throws {
        let identity = try XCTUnwrap(try IdentityDocument.identity(of: LoginFixtures.identityDocument(email: "s@example.com", organizationUuid: "org-s", organizationName: "Team S")))
        let saved = SavedLogin(loginSection: try sample().loginSection, identity: identity, capturedAt: captured)
        XCTAssertEqual(saved.organizationUuid, "org-s")
        XCTAssertEqual(saved.organizationName, "Team S")
        XCTAssertNil(try sample().organizationUuid)
        let summary = LoginSummary(email: "S@example.com", refreshTokenSHA256: "", expiresAt: .distantFuture, refreshTokenExpiresAt: .distantFuture,
                                   organizationUuid: "org-s", organizationName: "Team S")
        XCTAssertTrue(saved.matchesIdentity(of: summary))
        XCTAssertFalse(saved.matchesIdentity(of: LoginSummary(email: "s@example.com", refreshTokenSHA256: "", expiresAt: .distantFuture,
                                                                refreshTokenExpiresAt: .distantFuture, organizationUuid: "org-other")))
        XCTAssertTrue(try sample().matchesIdentity(of: summary), "a saved identity without an organization matches on email alone")
    }

    func testRejectsUnsupportedVersionAndMissingFields() throws {
        let future = try JSONSerialization.data(withJSONObject: ["version": 9, "claudeAiOauth": [:], "oauthAccount": [:], "capturedAt": "x"])
        XCTAssertThrowsError(try SavedLogin.decode(future)) { XCTAssertEqual($0 as? SavedLogin.FormatError, .unsupportedVersion(9)) }
        let missing = try JSONSerialization.data(withJSONObject: ["version": 1, "oauthAccount": [:], "capturedAt": "x"])
        XCTAssertThrowsError(try SavedLogin.decode(missing)) { XCTAssertEqual($0 as? SavedLogin.FormatError, .missingField("claudeAiOauth")) }
        XCTAssertThrowsError(try SavedLogin.decode(Data("[]".utf8))) { XCTAssertEqual($0 as? SavedLogin.FormatError, .notAnObject) }
    }
}
