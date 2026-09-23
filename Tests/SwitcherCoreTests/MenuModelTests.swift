import XCTest
@testable import SwitcherCore

final class MenuModelTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let work = Account(name: "Work", color: .teal, folder: "~/w", email: "work@example.com")
    let play = Account(name: "Play", color: .coral, folder: "~/p", email: "play@example.com")
    let bare = Account(name: "Bare", color: .gray, folder: "~/b")

    func live(_ email: String, refresh: String = "rt") -> LiveLoginState {
        .loggedIn(LoginSummary(email: email, refreshTokenSHA256: LiveLogin.sha256Hex(refresh), expiresAt: .distantFuture, refreshTokenExpiresAt: .distantFuture))
    }

    func build(live: LiveLoginState, state: HopState = .empty, expiry: [UUID: Date] = [:], saved: Set<UUID>? = nil,
               running: Set<UUID> = [], sessions: Int = 0, hotkeys: HotkeyAction = .openClaudeApp, positions: Set<Int> = [0, 1, 2]) -> MenuModel {
        MenuModel.build(accounts: [work, play, bare], live: live, state: state, savedLoginExpiry: expiry,
                        hasSavedLogin: saved ?? [work.id, play.id], desktopRunning: running, runningSessions: sessions,
                        hotkeyAction: hotkeys, hotkeyPositions: positions, now: now)
    }

    func testHeaderAndCheckmarkFollowTheLiveEmail() {
        let model = build(live: live("play@example.com"))
        XCTAssertEqual(model.header, "Active: Play (play@example.com)")
        XCTAssertEqual(model.activeAccountID, play.id)
        XCTAssertEqual(model.rows.map(\.isActive), [false, true, false])
        XCTAssertEqual(model.rows[1].switchLabel, .active)
        XCTAssertEqual(model.rows[0].switchLabel, .switchLogin)
        XCTAssertNil(model.saveCurrentLoginEmail)
    }

    func testHopsOwnWriteWinsOverARewrittenIdentity() {
        let state = HopState(activeAccountID: work.id, writtenRefreshTokenSHA256: LiveLogin.sha256Hex("rt"))
        let model = build(live: live("play@example.com"), state: state)
        XCTAssertEqual(model.activeAccountID, work.id)
        XCTAssertEqual(model.header, "Active: Work (work@example.com)")
    }

    func testUnknownLoginOffersToSaveIt() {
        let model = build(live: live("new@example.com"))
        XCTAssertNil(model.activeAccountID)
        XCTAssertEqual(model.header, "Active: new@example.com (not saved)")
        XCTAssertEqual(model.saveCurrentLoginEmail, "new@example.com")
        XCTAssertTrue(model.rows.allSatisfy { !$0.isActive })
    }

    func testLoggedOutAndUnrecognized() {
        XCTAssertEqual(build(live: .loggedOut).header, "Not logged in")
        XCTAssertEqual(build(live: .unrecognized("x")).header, "Login format not recognized")
        XCTAssertNil(build(live: .loggedOut).saveCurrentLoginEmail)
    }

    func testAccountWithoutSavedLoginSaysLogInFirst() {
        let model = build(live: live("work@example.com"))
        XCTAssertEqual(model.rows[2].switchLabel, .logInFirst)
        XCTAssertEqual(model.rows[2].terminalLabel, .logInFirst)
        XCTAssertEqual(model.rows[0].terminalLabel, .openTerminal)
    }

    func testDesktopLabelsAndRunningFlag() {
        let model = build(live: live("work@example.com"), running: [play.id])
        XCTAssertEqual(model.rows[1].desktopLabel, "Bring Claude app to front")
        XCTAssertEqual(model.rows[0].desktopLabel, "Open Claude app")
        XCTAssertTrue(model.rows[1].desktopRunning)
    }

    func testSessionsLine() {
        XCTAssertNil(build(live: .loggedOut).sessionsLine)
        XCTAssertEqual(build(live: .loggedOut, sessions: 1).sessionsLine, "1 terminal session running · it follows within 8 hours")
        XCTAssertEqual(build(live: .loggedOut, sessions: 3).sessionsLine, "3 terminal sessions running · they follow within 8 hours")
    }

    func testExpirySuffixOnlyWithinSevenDays() {
        let soon = now.addingTimeInterval(3 * 86_400 + 60)
        let far = now.addingTimeInterval(30 * 86_400)
        let gone = now.addingTimeInterval(-60)
        let model = build(live: .loggedOut, expiry: [work.id: soon, play.id: far, bare.id: gone])
        XCTAssertEqual(model.rows[0].title, "Work · login expires in 3 days")
        XCTAssertEqual(model.rows[1].title, "Play")
        XCTAssertEqual(model.rows[2].title, "Bare · login expired")
    }

    func testHintsFollowHotkeySetting() {
        XCTAssertEqual(build(live: .loggedOut).rows.map(\.hint), ["⌃⌥1", "⌃⌥2", "⌃⌥3"])
        XCTAssertEqual(build(live: .loggedOut, hotkeys: .off).rows.map(\.hint), [nil, nil, nil])
        XCTAssertEqual(build(live: .loggedOut, positions: [0]).rows.map(\.hint), ["⌃⌥1", nil, nil])
    }
}
