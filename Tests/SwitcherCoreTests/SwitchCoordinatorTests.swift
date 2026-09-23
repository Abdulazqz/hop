import XCTest
@testable import SwitcherCore

final class SwitchCoordinatorTests: XCTestCase {
    let home = "/Users/tester"
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var logins: FakeLoginStore!
    var identity: FakeIdentityStore!
    var coordinator: SwitchCoordinator!
    var work: Account!
    var play: Account!

    override func setUp() {
        logins = FakeLoginStore()
        identity = FakeIdentityStore()
        coordinator = SwitchCoordinator(logins: logins, identityDocument: identity, home: home) { [now] in now }
        work = Account(name: "Work", color: .teal, folder: "~/w", email: "work@example.com")
        play = Account(name: "Play", color: .coral, folder: "~/p", email: "play@example.com")
    }

    /// Live login = `email` with refresh token `refresh`; identity document carries the same email.
    func setLive(email: String, refresh: String) {
        logins.live = LoginFixtures.keychainValue(refresh: refresh, extra: ["mcpOAuth": ["srv": ["accessToken": "m"]]])
        identity.document = LoginFixtures.identityDocument(email: email, extra: ["numStartups": 7])
    }

    func save(_ account: Account, refresh: String, refreshExpiresAt: Double = LoginFixtures.farFuture) throws {
        let saved = SavedLogin(loginSection: try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: refresh, refreshTokenExpiresAt: refreshExpiresAt)),
                               identity: try XCTUnwrap(try IdentityDocument.identity(of: LoginFixtures.identityDocument(email: account.email))),
                               capturedAt: now)
        logins.saved[account.id] = try saved.encoded()
    }

    func testHappyPathSavesOutgoingAndWritesTarget() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        try save(play, refresh: "rt-play")
        let result = try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in XCTFail("no dialog"); return nil }
        XCTAssertEqual(result.from, work.id)
        XCTAssertEqual(result.to, play.id)
        // outgoing saved under Work with its live identity
        let savedWork = try SavedLogin.decode(try XCTUnwrap(logins.saved[work.id]))
        XCTAssertEqual(savedWork.refreshTokenSHA256, LiveLogin.sha256Hex("rt-work"))
        XCTAssertEqual(savedWork.email, "work@example.com")
        // live now holds Play's login section, mcpOAuth preserved
        let live = LoginFixtures.json(try XCTUnwrap(logins.live))
        XCTAssertEqual((live["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String, "rt-play")
        XCTAssertNotNil(live["mcpOAuth"])
        // identity document: only oauthAccount replaced
        let doc = LoginFixtures.json(try XCTUnwrap(identity.document))
        XCTAssertEqual((doc["oauthAccount"] as? [String: Any])?["emailAddress"] as? String, "play@example.com")
        XCTAssertEqual(doc["numStartups"] as? Int, 7)
        // state records the write
        XCTAssertEqual(result.state, HopState(activeAccountID: play.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt-play")))
        var expectedWork = work!
        expectedWork.savedLoginExpiresAt = Date(timeIntervalSince1970: LoginFixtures.farFuture / 1000)
        XCTAssertEqual(result.accounts, [expectedWork, play])
    }

    func testAlreadyActiveTouchesNeitherKeychainNorIdentity() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        try save(work, refresh: "rt-old")
        XCTAssertThrowsError(try coordinator.switchTo(work.id, accounts: [work, play], state: .empty) { _ in nil }) {
            XCTAssertEqual($0 as? SwitchError, .alreadyActive("Work"))
        }
        XCTAssertTrue(logins.liveWrites.isEmpty)
        XCTAssertEqual(identity.writes, 0)
    }

    func testTargetWithoutSavedLoginIsRefusedBeforeSaving() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            XCTAssertEqual($0 as? SwitchError, .targetHasNoLogin("Play"))
        }
        XCTAssertTrue(logins.liveWrites.isEmpty)
    }

    func testExpiredTargetIsRefusedWithDate() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        let past = (now.timeIntervalSince1970 - 10) * 1000
        try save(play, refresh: "rt-play", refreshExpiresAt: past)
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            XCTAssertEqual($0 as? SwitchError, .targetLoginExpired(name: "Play", on: Date(timeIntervalSince1970: now.timeIntervalSince1970 - 10)))
        }
        XCTAssertTrue(logins.liveWrites.isEmpty)
    }

    func testUnknownEmailCancelledWritesNothing() throws {
        setLive(email: "new@example.com", refresh: "rt-new")
        try save(play, refresh: "rt-play")
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            XCTAssertEqual($0 as? SwitchError, .cancelled(email: "new@example.com"))
        }
        XCTAssertTrue(logins.liveWrites.isEmpty)
        XCTAssertTrue(logins.saved[work.id] == nil)
    }

    func testUnknownEmailCreatesAccountWithFolder() throws {
        setLive(email: "new@example.com", refresh: "rt-new")
        try save(play, refresh: "rt-play")
        var asked: String?
        let result = try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { email in asked = email; return .create }
        XCTAssertEqual(asked, "new@example.com")
        XCTAssertEqual(result.accounts.count, 3)
        let created = result.accounts[2]
        XCTAssertEqual(created.name, "new@example.com")
        XCTAssertEqual(created.email, "new@example.com")
        XCTAssertEqual(created.folder, "~/Library/Application Support/Claude-newexamplecom")
        XCTAssertEqual(result.from, created.id)
        XCTAssertNotNil(logins.saved[created.id])
        XCTAssertNoThrow(try AccountValidation.validate(result.accounts, home: home))
    }

    func testUnknownEmailAttachesToAccountWithoutEmail() throws {
        let bare = Account(name: "Third", color: .gray, folder: "~/t")
        setLive(email: "new@example.com", refresh: "rt-new")
        try save(play, refresh: "rt-play")
        let result = try coordinator.switchTo(play.id, accounts: [work, play, bare], state: .empty) { _ in .attach(bare.id) }
        XCTAssertEqual(result.accounts[2].email, "new@example.com")
        XCTAssertNotNil(logins.saved[bare.id])
        XCTAssertEqual(result.from, bare.id)
    }

    func testAttachingToTheTargetIsRefusedAndKeepsItsLogin() throws {
        setLive(email: "new@example.com", refresh: "rt-new")
        try save(play, refresh: "rt-play")
        let before = logins.saved[play.id]
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in .attach(play.id) }) {
            XCTAssertEqual($0 as? SwitchError, .attachTargetHasLogin("Play"))
        }
        XCTAssertEqual(logins.saved[play.id], before, "the target's saved login must be untouched")
        XCTAssertTrue(logins.liveWrites.isEmpty)
        XCTAssertEqual(identity.writes, 0)
    }

    func testAttachingToAnAccountWithAnEmailIsRefused() throws {
        setLive(email: "new@example.com", refresh: "rt-new")
        try save(play, refresh: "rt-play")
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in .attach(work.id) }) {
            XCTAssertEqual($0 as? SwitchError, .attachTargetHasLogin("Work"))
        }
        XCTAssertNil(logins.saved[work.id])
        XCTAssertTrue(logins.liveWrites.isEmpty)
    }

    func testLoggedOutSkipsCapture() throws {
        logins.live = nil
        identity.document = LoginFixtures.identityDocument(email: nil)
        try save(play, refresh: "rt-play")
        let result = try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }
        XCTAssertNil(result.from)
        XCTAssertEqual(LoginFixtures.json(try XCTUnwrap(logins.live)).keys.sorted(), ["claudeAiOauth"])
        XCTAssertEqual((LoginFixtures.json(try XCTUnwrap(identity.document))["oauthAccount"] as? [String: Any])?["emailAddress"] as? String, "play@example.com")
    }

    func testUnrecognizedShapeStops() throws {
        logins.live = Data("{\"weird\":1}".utf8)
        identity.document = LoginFixtures.identityDocument()
        try save(play, refresh: "rt-play")
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            guard case .unrecognizedLogin = $0 as? SwitchError else { return XCTFail("\($0)") }
        }
        XCTAssertTrue(logins.liveWrites.isEmpty)
    }

    func testHopWroteHashSavesUnderStateAccountWithItsOwnIdentity() throws {
        // Hop wrote Work's token; a stale session then rewrote the identity file as Play.
        setLive(email: "play@example.com", refresh: "rt-work")
        try save(work, refresh: "rt-work")   // Work's saved identity = work@example.com
        try save(play, refresh: "rt-play")
        let state = HopState(activeAccountID: work.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt-work"))
        let result = try coordinator.switchTo(play.id, accounts: [work, play], state: state) { _ in nil }
        XCTAssertEqual(result.from, work.id)
        XCTAssertEqual(try SavedLogin.decode(try XCTUnwrap(logins.saved[work.id])).email, "work@example.com")
    }

    func testIdentityWriteFailureRestoresKeychain() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        let before = logins.live
        try save(play, refresh: "rt-play")
        identity.failWrite = true
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            guard case .rolledBack = $0 as? SwitchError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(logins.live, before)
        XCTAssertEqual(logins.liveWrites.count, 2, "target write then restore")
    }

    func testIdentityWriteFailureWhenLoggedOutRemovesKeychainItem() throws {
        logins.live = nil
        identity.document = LoginFixtures.identityDocument(email: nil)
        try save(play, refresh: "rt-play")
        identity.failWrite = true
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            guard case .rolledBack = $0 as? SwitchError else { return XCTFail("\($0)") }
        }
        XCTAssertNil(logins.live, "the item Hop created must be removed again")
        XCTAssertEqual(logins.liveDeletes, 1)
    }

    func testSaveCurrentLoginWithoutSwitching() throws {
        setLive(email: "new@example.com", refresh: "rt-new")
        let (accounts, state) = try coordinator.saveCurrentLogin(accounts: [work], state: .empty, choice: .create)
        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(state.activeAccountID, accounts[1].id)
        XCTAssertEqual(state.writtenRefreshTokenSHA256, LiveLogin.sha256Hex("rt-new"))
        XCTAssertTrue(logins.liveWrites.isEmpty)
        XCTAssertNotNil(logins.saved[accounts[1].id])
    }

    func testCaptureRecordsSavedLoginExpiryOnTheAccount() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        logins.live = LoginFixtures.keychainValue(refresh: "rt-work", refreshTokenExpiresAt: 9_000)
        try save(play, refresh: "rt-play")
        let result = try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }
        XCTAssertEqual(result.accounts[0].savedLoginExpiresAt, Date(timeIntervalSince1970: 9))
        XCTAssertNil(result.accounts[1].savedLoginExpiresAt, "the target's expiry is recorded only when it is captured")
    }

    func testNewAccountPicksUnusedColor() {
        let account = SwitchCoordinator.newAccount(email: "x@example.com", accounts: [work, play], home: home)
        XCTAssertEqual(account.color, .purple)
        XCTAssertEqual(account.folder, "~/Library/Application Support/Claude-xexamplecom")
    }
}
