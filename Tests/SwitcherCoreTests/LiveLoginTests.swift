import XCTest
@testable import SwitcherCore

final class LiveLoginTests: XCTestCase {
    func testValidLoginIsSummarized() {
        let state = LiveLogin.parse(keychainValue: LoginFixtures.keychainValue(refresh: "rt-7"),
                                    identityDocument: LoginFixtures.identityDocument(email: "Me@Example.com"))
        guard case .loggedIn(let s) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(s.email, "Me@Example.com")
        XCTAssertEqual(s.refreshTokenSHA256, LiveLogin.sha256Hex("rt-7"))
        XCTAssertEqual(s.expiresAt, Date(timeIntervalSince1970: LoginFixtures.farFuture / 1000))
        XCTAssertEqual(s.refreshTokenExpiresAt, Date(timeIntervalSince1970: LoginFixtures.farFuture / 1000))
    }

    func testMissingItemIsLoggedOut() {
        XCTAssertEqual(LiveLogin.parse(keychainValue: nil, identityDocument: LoginFixtures.identityDocument()), .loggedOut)
    }

    func testExpiresAtZeroIsLoggedOut() {
        let wiped = LoginFixtures.keychainValue(expiresAt: 0)
        XCTAssertEqual(LiveLogin.parse(keychainValue: wiped, identityDocument: LoginFixtures.identityDocument()), .loggedOut)
    }

    func testEmptyTokensAreLoggedOut() {
        let empty = LoginFixtures.keychainValue(access: "", refresh: "")
        XCTAssertEqual(LiveLogin.parse(keychainValue: empty, identityDocument: LoginFixtures.identityDocument()), .loggedOut)
    }

    func testValueWithoutLoginKeyIsUnrecognized() {
        let odd = try! JSONSerialization.data(withJSONObject: ["somethingElse": 1])
        guard case .unrecognized = LiveLogin.parse(keychainValue: odd, identityDocument: LoginFixtures.identityDocument()) else {
            return XCTFail("expected unrecognized")
        }
    }

    func testNonJSONValueIsUnrecognized() {
        guard case .unrecognized = LiveLogin.parse(keychainValue: Data("nope".utf8), identityDocument: nil) else {
            return XCTFail("expected unrecognized")
        }
    }

    func testTokensWithoutIdentityEmailAreUnrecognized() {
        guard case .unrecognized = LiveLogin.parse(keychainValue: LoginFixtures.keychainValue(),
                                                   identityDocument: LoginFixtures.identityDocument(email: nil)) else {
            return XCTFail("expected unrecognized")
        }
    }

    func testTokensWithUnreadableIdentityDocumentAreUnrecognized() {
        guard case .unrecognized = LiveLogin.parse(keychainValue: LoginFixtures.keychainValue(),
                                                   identityDocument: Data("{broken".utf8)) else {
            return XCTFail("expected unrecognized")
        }
    }

    func testLoginSectionExtractsOnlyTheOAuthObject() throws {
        let section = try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: "rt-2"))
        let object = LoginFixtures.json(section)
        XCTAssertEqual(object["refreshToken"] as? String, "rt-2")
        XCTAssertNil(object["mcpOAuth"])
    }

    func testReplacingLoginSectionKeepsEveryOtherKey() throws {
        let base = LoginFixtures.keychainValue(refresh: "rt-old", extra: ["mcpOAuth": ["x": 1], "futureKey": "keep"])
        let section = try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: "rt-new"))
        let merged = LoginFixtures.json(try LiveLogin.replacingLoginSection(in: base, with: section))
        XCTAssertEqual((merged["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String, "rt-new")
        XCTAssertEqual((merged["mcpOAuth"] as? [String: Any])?["x"] as? Int, 1)
        XCTAssertEqual(merged["futureKey"] as? String, "keep")
    }

    func testReplacingLoginSectionWithNoBaseMakesAFreshObject() throws {
        let section = try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: "rt-new"))
        let merged = LoginFixtures.json(try LiveLogin.replacingLoginSection(in: nil, with: section))
        XCTAssertEqual(Array(merged.keys), ["claudeAiOauth"])
    }

    func testSectionHelpers() throws {
        let section = try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: "rt-3", refreshTokenExpiresAt: 1_000))
        XCTAssertEqual(LiveLogin.refreshTokenExpiry(ofLoginSection: section), Date(timeIntervalSince1970: 1))
        XCTAssertEqual(LiveLogin.refreshTokenSHA256(ofLoginSection: section), LiveLogin.sha256Hex("rt-3"))
        XCTAssertNil(LiveLogin.refreshTokenExpiry(ofLoginSection: Data("[]".utf8)))
    }

    func testSha256IsHexOfUTF8() {
        XCTAssertEqual(LiveLogin.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testIdentityOnlyParseUsesTheEmailAndNoTokens() {
        let state = LiveLogin.parseIdentityOnly(identityDocument: LoginFixtures.identityDocument(email: "Me@Example.com"))
        guard case .loggedIn(let s) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(s.email, "Me@Example.com")
        XCTAssertEqual(s.refreshTokenSHA256, "")
    }

    func testIdentityOnlyParseWithoutIdentityIsLoggedOut() {
        XCTAssertEqual(LiveLogin.parseIdentityOnly(identityDocument: LoginFixtures.identityDocument(email: nil)), .loggedOut)
        XCTAssertEqual(LiveLogin.parseIdentityOnly(identityDocument: nil), .loggedOut)
    }

    func testIdentityOnlyParseRejectsBrokenDocument() {
        guard case .unrecognized = LiveLogin.parseIdentityOnly(identityDocument: Data("{broken".utf8)) else {
            return XCTFail("expected unrecognized")
        }
    }
}
