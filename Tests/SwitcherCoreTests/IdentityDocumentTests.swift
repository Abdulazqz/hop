import XCTest
@testable import SwitcherCore

final class IdentityDocumentTests: XCTestCase {
    func testIdentityExtractsOnlyTheAccountObject() throws {
        let identity = try XCTUnwrap(try IdentityDocument.identity(of: LoginFixtures.identityDocument(email: "x@y.z")))
        let object = LoginFixtures.json(identity)
        XCTAssertEqual(object["emailAddress"] as? String, "x@y.z")
        XCTAssertNil(object["numStartups"])
        XCTAssertEqual(IdentityDocument.email(inIdentity: identity), "x@y.z")
    }

    func testMissingIdentityIsNil() throws {
        XCTAssertNil(try IdentityDocument.identity(of: LoginFixtures.identityDocument(email: nil)))
    }

    func testNotAnObjectThrows() {
        XCTAssertThrowsError(try IdentityDocument.identity(of: Data("[1]".utf8))) {
            XCTAssertEqual($0 as? IdentityDocument.DocumentError, .notAnObject)
        }
        XCTAssertThrowsError(try IdentityDocument.replacingIdentity(in: Data("{broken".utf8), with: Data("{}".utf8)))
    }

    func testReplacingIdentityPreservesEveryOtherKey() throws {
        let document = LoginFixtures.identityDocument(email: "old@example.com",
                                                      extra: ["numStartups": 3, "cachedThing": ["deep": true]])
        let newIdentity = try XCTUnwrap(try IdentityDocument.identity(of: LoginFixtures.identityDocument(email: "new@example.com")))
        let merged = LoginFixtures.json(try IdentityDocument.replacingIdentity(in: document, with: newIdentity))
        XCTAssertEqual((merged["oauthAccount"] as? [String: Any])?["emailAddress"] as? String, "new@example.com")
        XCTAssertEqual(merged["numStartups"] as? Int, 3)
        XCTAssertEqual((merged["cachedThing"] as? [String: Any])?["deep"] as? Bool, true)
    }

    func testReplacingIdentityInMissingDocumentStartsEmpty() throws {
        let identity = try XCTUnwrap(try IdentityDocument.identity(of: LoginFixtures.identityDocument()))
        let merged = LoginFixtures.json(try IdentityDocument.replacingIdentity(in: nil, with: identity))
        XCTAssertEqual(Array(merged.keys), ["oauthAccount"])
    }

    func testAtomicWriteReplacesContentAndRestrictsMode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("doc.json")
        try Data("old".utf8).write(to: url)
        try AtomicFile.write(Data("new".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["doc.json"], "no temp file left behind")
    }
}
