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

    /// Live login = `email` with refresh token `refresh`; identity document carries the same email (and organization).
    func setLive(email: String, refresh: String, organization: String? = nil, organizationName: String? = "Org") {
        logins.live = LoginFixtures.keychainValue(refresh: refresh, extra: ["mcpOAuth": ["srv": ["accessToken": "m"]]])
        identity.document = LoginFixtures.identityDocument(email: email, organizationUuid: organization, organizationName: organizationName,
                                                           extra: ["numStartups": 7])
    }

    /// Saves a login for `account`; the saved identity carries the account's email and organization.
    func save(_ account: Account, refresh: String, refreshExpiresAt: Double = LoginFixtures.farFuture) throws {
        let document = LoginFixtures.identityDocument(email: account.email, organizationUuid: account.organizationUuid,
                                                      organizationName: account.organizationName ?? "Org")
        let saved = SavedLogin(loginSection: try LiveLogin.loginSection(of: LoginFixtures.keychainValue(refresh: refresh, refreshTokenExpiresAt: refreshExpiresAt)),
                               identity: try XCTUnwrap(try IdentityDocument.identity(of: document)),
                               capturedAt: now)
        logins.saved[account.id] = try saved.encoded()
    }

    func savedRefresh(_ id: UUID) throws -> String? {
        try SavedLogin.decode(try XCTUnwrap(logins.saved[id])).refreshTokenSHA256
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
            XCTAssertEqual($0 as? SwitchError, .cancelled(login: "new@example.com · Org"))
        }
        XCTAssertTrue(logins.liveWrites.isEmpty)
        XCTAssertTrue(logins.saved[work.id] == nil)
    }

    func testUnknownEmailCreatesAccountWithFolder() throws {
        setLive(email: "new@example.com", refresh: "rt-new")
        try save(play, refresh: "rt-play")
        var asked: String?
        let result = try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { login in asked = login; return .create }
        XCTAssertEqual(asked, "new@example.com · Org")
        XCTAssertEqual(result.accounts.count, 3)
        let created = result.accounts[2]
        XCTAssertEqual(created.name, "new@example.com")
        XCTAssertEqual(created.email, "new@example.com")
        XCTAssertEqual(created.organizationName, "Org")
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

    func testSwitchingToTheDisplayedAccountAfterAKeychainWipeRestoresItsLogin() throws {
        // Claude Code wiped its item; ~/.claude.json still names Work.
        logins.live = LoginFixtures.keychainValue(access: "", refresh: "", expiresAt: 0)
        identity.document = LoginFixtures.identityDocument(email: "work@example.com")
        try save(work, refresh: "rt-work")
        let result = try coordinator.switchTo(work.id, accounts: [work, play], state: .empty) { _ in XCTFail("no dialog"); return nil }
        XCTAssertNil(result.from)
        let live = LoginFixtures.json(try XCTUnwrap(logins.live))
        XCTAssertEqual((live["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String, "rt-work")
    }

    func testSwitchingToTheActiveAccountRepairsARewrittenIdentity() throws {
        // Hop wrote Work's token; a stale session then rewrote the identity file as Play.
        setLive(email: "play@example.com", refresh: "rt-work")
        try save(work, refresh: "rt-work")
        let state = HopState(activeAccountID: work.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt-work"))
        XCTAssertThrowsError(try coordinator.switchTo(work.id, accounts: [work, play], state: state) { _ in nil }) {
            XCTAssertEqual($0 as? SwitchError, .alreadyActive("Work"))
        }
        let doc = LoginFixtures.json(try XCTUnwrap(identity.document))
        XCTAssertEqual((doc["oauthAccount"] as? [String: Any])?["emailAddress"] as? String, "work@example.com")
        XCTAssertEqual(doc["numStartups"] as? Int, 7, "only oauthAccount is replaced")
        XCTAssertTrue(logins.liveWrites.isEmpty)
    }

    func testHopWroteWithoutASavedItemFallsBackToEmail() throws {
        // State says Hop wrote Work, but Work's saved item is gone (forgotten); the live login is Play's by email.
        setLive(email: "play@example.com", refresh: "rt-x")
        let state = HopState(activeAccountID: work.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt-x"))
        try save(play, refresh: "rt-play")
        let third = Account(name: "Third", color: .gray, folder: "~/t", email: "third@example.com")
        try save(third, refresh: "rt-third")
        let result = try coordinator.switchTo(third.id, accounts: [work, play, third], state: state) { _ in XCTFail("no dialog"); return nil }
        XCTAssertEqual(result.from, play.id)
        XCTAssertEqual(result.accounts[0].email, work.email)
        XCTAssertNil(logins.saved[work.id])
        let savedPlay = try SavedLogin.decode(try XCTUnwrap(logins.saved[play.id]))
        XCTAssertEqual(savedPlay.refreshTokenSHA256, LiveLogin.sha256Hex("rt-x"))
        XCTAssertEqual(savedPlay.email, "play@example.com")
    }

    func testKeychainWriteFailureLeavesIdentityUntouched() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        try save(play, refresh: "rt-play")
        logins.failLiveWrite = true
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            guard case .store = $0 as? SwitchError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(identity.writes, 0)
    }

    func testRefusedTargetNeverAsksOrCaptures() throws {
        setLive(email: "new@example.com", refresh: "rt-new")
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in
            XCTFail("resolver must not run"); return nil
        }) {
            XCTAssertEqual($0 as? SwitchError, .targetHasNoLogin("Play"))
        }
        XCTAssertTrue(logins.saved.isEmpty)
        XCTAssertTrue(logins.liveWrites.isEmpty)
    }

    func testRollbackMessageSaysWhenTheRestoreAlsoFailed() throws {
        logins.live = nil
        identity.document = LoginFixtures.identityDocument(email: nil)
        try save(play, refresh: "rt-play")
        identity.failWrite = true
        logins.failLiveDelete = true
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            guard case .rolledBack(let message) = $0 as? SwitchError else { return XCTFail("\($0)") }
            XCTAssertTrue(message.contains("restoring the previous login also failed"), message)
            XCTAssertFalse(($0 as? SwitchError)?.errorDescription?.contains("was restored") ?? true)
        }
    }

    func testRollbackMessageSaysTheRestoreSucceeded() throws {
        setLive(email: "work@example.com", refresh: "rt-work")
        try save(play, refresh: "rt-play")
        identity.failWrite = true
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in nil }) {
            XCTAssertTrue(($0 as? SwitchError)?.errorDescription?.contains("The previous login was restored.") ?? false)
        }
    }

    func testNewAccountPicksUnusedColor() {
        let account = SwitchCoordinator.newAccount(email: "x@example.com", organizationUuid: nil, organizationName: nil, accounts: [work, play], home: home)
        XCTAssertEqual(account.color, .purple)
        XCTAssertEqual(account.folder, "~/Library/Application Support/Claude-xexamplecom")
    }

    // MARK: - one email, several organizations

    let personal = Account(name: "Me (Personal)", color: .coral, folder: "~/mp", email: "me@example.com",
                           organizationUuid: "org-p", organizationName: "Personal")
    let team = Account(name: "Me (Team)", color: .blue, folder: "~/mt", email: "me@example.com",
                       organizationUuid: "org-t", organizationName: "Team")

    func testSwitchingBetweenTwoOrganizationsOfOneEmail() throws {
        setLive(email: "me@example.com", refresh: "rt-p", organization: "org-p", organizationName: "Personal")
        try save(team, refresh: "rt-t")
        let result = try coordinator.switchTo(team.id, accounts: [personal, team], state: .empty) { _ in XCTFail("no dialog"); return nil }
        XCTAssertEqual(result.from, personal.id)
        let savedPersonal = try SavedLogin.decode(try XCTUnwrap(logins.saved[personal.id]))
        XCTAssertEqual(savedPersonal.refreshTokenSHA256, LiveLogin.sha256Hex("rt-p"))
        XCTAssertEqual(savedPersonal.organizationUuid, "org-p")
        XCTAssertEqual(try savedRefresh(team.id), LiveLogin.sha256Hex("rt-t"), "Team's saved login is untouched")
        let doc = LoginFixtures.json(try XCTUnwrap(identity.document))
        XCTAssertEqual((doc["oauthAccount"] as? [String: Any])?["organizationUuid"] as? String, "org-t")
        XCTAssertEqual(result.state.activeAccountID, team.id)
    }

    func testSwitchingBetweenTwoOrganizationsOfOneEmailWithIdentityOnlyOrganizationName() throws {
        // Switching from Team to Personal: the identity file ends up carrying Personal's organization.
        setLive(email: "me@example.com", refresh: "rt-t", organization: "org-t", organizationName: "Team")
        try save(personal, refresh: "rt-p")
        let result = try coordinator.switchTo(personal.id, accounts: [personal, team], state: .empty) { _ in XCTFail("no dialog"); return nil }
        XCTAssertEqual(result.from, team.id)
        XCTAssertEqual(try savedRefresh(team.id), LiveLogin.sha256Hex("rt-t"))
        let doc = LoginFixtures.json(try XCTUnwrap(identity.document))
        XCTAssertEqual((doc["oauthAccount"] as? [String: Any])?["organizationName"] as? String, "Personal")
    }

    func testALegacyAccountIsNotOverwrittenByTheSameEmailInAnotherOrganization() throws {
        // Team was saved before Hop recorded organizations: email set, organization unknown, saved item holds org-t.
        var legacyTeam = team
        legacyTeam.organizationUuid = nil
        legacyTeam.organizationName = nil
        let bare = Account(name: "Me (Personal)", color: .coral, folder: "~/mp")
        try save(team, refresh: "rt-t")
        setLive(email: "me@example.com", refresh: "rt-p", organization: "org-p", organizationName: "Personal")
        try save(play, refresh: "rt-play")
        var asked: String?
        let result = try coordinator.switchTo(play.id, accounts: [legacyTeam, bare, play], state: .empty) { asked = $0; return .attach(bare.id) }
        XCTAssertEqual(asked, "me@example.com · Personal")
        XCTAssertEqual(result.from, bare.id)
        XCTAssertEqual(try savedRefresh(team.id), LiveLogin.sha256Hex("rt-t"), "Team's saved login must be untouched")
        XCTAssertEqual(try savedRefresh(bare.id), LiveLogin.sha256Hex("rt-p"))
        XCTAssertEqual(result.accounts[0].organizationUuid, "org-t", "Team learned its organization from its saved login")
        XCTAssertEqual(result.accounts[0].organizationName, "Team")
        XCTAssertEqual(result.accounts[1].email, "me@example.com")
        XCTAssertEqual(result.accounts[1].organizationUuid, "org-p")
        XCTAssertEqual(result.accounts[1].organizationName, "Personal")
        XCTAssertNoThrow(try AccountValidation.validate(result.accounts, home: home))
    }

    func testALegacyAccountIsNotOverwrittenEvenWhenTheUserCancels() throws {
        var legacyTeam = team
        legacyTeam.organizationUuid = nil
        try save(team, refresh: "rt-t")
        setLive(email: "me@example.com", refresh: "rt-p", organization: "org-p", organizationName: "Personal")
        try save(play, refresh: "rt-play")
        XCTAssertThrowsError(try coordinator.switchTo(play.id, accounts: [legacyTeam, play], state: .empty) { _ in nil }) {
            XCTAssertEqual($0 as? SwitchError, .cancelled(login: "me@example.com · Personal"))
        }
        XCTAssertEqual(try savedRefresh(team.id), LiveLogin.sha256Hex("rt-t"))
        XCTAssertTrue(logins.liveWrites.isEmpty)
    }

    func testALegacyAccountWhoseSavedLoginIsTheLiveOrganizationStillMatches() throws {
        var legacyTeam = team
        legacyTeam.organizationUuid = nil
        legacyTeam.organizationName = nil
        try save(team, refresh: "rt-t-old")
        setLive(email: "me@example.com", refresh: "rt-t", organization: "org-t", organizationName: "Team")
        try save(play, refresh: "rt-play")
        let result = try coordinator.switchTo(play.id, accounts: [legacyTeam, play], state: .empty) { _ in XCTFail("no dialog"); return nil }
        XCTAssertEqual(result.from, team.id)
        XCTAssertEqual(try savedRefresh(team.id), LiveLogin.sha256Hex("rt-t"))
        XCTAssertEqual(result.accounts[0].organizationUuid, "org-t")
        XCTAssertEqual(result.accounts[0].organizationName, "Team")
    }

    func testALegacyAccountWithoutASavedItemKeepsMatchingByEmail() throws {
        // Email set but the saved item is gone: nothing to learn from, so the email match stands and the capture repairs it.
        var legacyTeam = team
        legacyTeam.organizationUuid = nil
        setLive(email: "me@example.com", refresh: "rt-p", organization: "org-p", organizationName: "Personal")
        try save(play, refresh: "rt-play")
        let result = try coordinator.switchTo(play.id, accounts: [legacyTeam, play], state: .empty) { _ in XCTFail("no dialog"); return nil }
        XCTAssertEqual(result.from, team.id)
        XCTAssertEqual(result.accounts[0].organizationUuid, "org-p")
    }

    func testSwitchingStampsTheTargetsOrganizationFromItsSavedLogin() throws {
        var legacyTeam = team
        legacyTeam.organizationUuid = nil
        legacyTeam.organizationName = nil
        try save(team, refresh: "rt-t")
        setLive(email: "work@example.com", refresh: "rt-work")
        let result = try coordinator.switchTo(team.id, accounts: [work, legacyTeam], state: .empty) { _ in XCTFail("no dialog"); return nil }
        XCTAssertEqual(result.accounts[1].organizationUuid, "org-t")
        XCTAssertEqual(result.accounts[1].organizationName, "Team")
    }

    func testCaptureRecordsTheOrganizationOnTheOutgoingAccount() throws {
        setLive(email: "work@example.com", refresh: "rt-work", organization: "org-w", organizationName: "Work Inc")
        try save(play, refresh: "rt-play")
        let result = try coordinator.switchTo(play.id, accounts: [work, play], state: .empty) { _ in XCTFail("no dialog"); return nil }
        XCTAssertEqual(result.accounts[0].organizationUuid, "org-w")
        XCTAssertEqual(result.accounts[0].organizationName, "Work Inc")
    }

    func testHopWroteWithARewrittenOrganizationRepairsTheIdentity() throws {
        // Hop wrote Personal's token; a stale session then rewrote the identity file as the Team organization (same email).
        setLive(email: "me@example.com", refresh: "rt-p", organization: "org-t", organizationName: "Team")
        try save(personal, refresh: "rt-p")
        try save(play, refresh: "rt-play")
        let state = HopState(activeAccountID: personal.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt-p"))
        let result = try coordinator.switchTo(play.id, accounts: [personal, team, play], state: state) { _ in XCTFail("no dialog"); return nil }
        XCTAssertEqual(result.from, personal.id)
        XCTAssertEqual(try SavedLogin.decode(try XCTUnwrap(logins.saved[personal.id])).organizationUuid, "org-p")
    }

    func testSwitchingToTheActiveAccountRepairsARewrittenOrganization() throws {
        setLive(email: "me@example.com", refresh: "rt-p", organization: "org-t", organizationName: "Team")
        try save(personal, refresh: "rt-p")
        let state = HopState(activeAccountID: personal.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt-p"))
        XCTAssertThrowsError(try coordinator.switchTo(personal.id, accounts: [personal, team], state: state) { _ in nil }) {
            XCTAssertEqual($0 as? SwitchError, .alreadyActive("Me (Personal)"))
        }
        let doc = LoginFixtures.json(try XCTUnwrap(identity.document))
        XCTAssertEqual((doc["oauthAccount"] as? [String: Any])?["organizationUuid"] as? String, "org-p")
        XCTAssertTrue(logins.liveWrites.isEmpty)
    }

    func testNewAccountForASecondOrganizationOfAnEmailGetsTheOrganizationInItsName() {
        let first = Account(name: "x@example.com", color: .teal, folder: "~/x1", email: "x@example.com", organizationUuid: "org-1", organizationName: "One")
        let account = SwitchCoordinator.newAccount(email: "x@example.com", organizationUuid: "org-2", organizationName: "Two", accounts: [first], home: home)
        XCTAssertEqual(account.name, "x@example.com (Two)")
        XCTAssertEqual(account.email, "x@example.com")
        XCTAssertEqual(account.organizationUuid, "org-2")
        XCTAssertEqual(account.organizationName, "Two")
        XCTAssertEqual(account.folder, "~/Library/Application Support/Claude-xexamplecom-two")
        XCTAssertNoThrow(try AccountValidation.validate([first, account], home: home))
        let fresh = SwitchCoordinator.newAccount(email: "y@example.com", organizationUuid: "org-2", organizationName: "Two", accounts: [first], home: home)
        XCTAssertEqual(fresh.name, "y@example.com", "the organization only joins the name when the email is already taken")
    }

    func testUnknownOrganizationCreatesASecondAccountForTheEmail() throws {
        try save(team, refresh: "rt-t")
        setLive(email: "me@example.com", refresh: "rt-p", organization: "org-p", organizationName: "Personal")
        try save(play, refresh: "rt-play")
        let result = try coordinator.switchTo(play.id, accounts: [team, play], state: .empty) { _ in .create }
        XCTAssertEqual(result.accounts.count, 3)
        let created = result.accounts[2]
        XCTAssertEqual(created.name, "me@example.com (Personal)")
        XCTAssertEqual(created.organizationUuid, "org-p")
        XCTAssertEqual(result.from, created.id)
        XCTAssertEqual(try savedRefresh(team.id), LiveLogin.sha256Hex("rt-t"))
        XCTAssertNoThrow(try AccountValidation.validate(result.accounts, home: home))
    }
}
