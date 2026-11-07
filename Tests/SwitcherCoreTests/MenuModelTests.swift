import XCTest
@testable import SwitcherCore

final class MenuModelTests: XCTestCase {
    let work = Account(name: "Work", color: .teal, folder: "~/w", tokenAddedAt: Date())
    let play = Account(name: "Play", color: .coral, folder: "~/p", tokenAddedAt: Date())
    let bare = Account(name: "Bare", color: .gray, folder: "~/b")   // no setup-token

    func build(active: UUID?, running: Set<UUID> = [], sessions: Int = 0,
               hotkeys: HotkeyAction = .openClaudeApp, positions: Set<Int> = [0, 1, 2]) -> MenuModel {
        MenuModel.build(accounts: [work, play, bare], activeAccountID: active,
                        tokenBacked: [work.id, play.id], desktopRunning: running, runningSessions: sessions,
                        hotkeyAction: hotkeys, hotkeyPositions: positions)
    }

    func testActiveTokenBackedAndTokenlessRowLabels() {
        let model = build(active: work.id)
        XCTAssertEqual(model.rows.map(\.isActive), [true, false, false])
        XCTAssertEqual(model.rows[0].switchLabel, .active)
        XCTAssertEqual(model.rows[1].switchLabel, .switchLogin)
        XCTAssertEqual(model.rows[2].switchLabel, .needsToken)
    }

    func testHeaderNamesTheActiveAccount() {
        XCTAssertEqual(build(active: play.id).header, "Active: Play")
        XCTAssertEqual(build(active: play.id).activeAccountID, play.id)
    }

    func testHeaderWhenNothingActive() {
        let model = build(active: nil)
        XCTAssertEqual(model.header, "No account active")
        XCTAssertNil(model.activeAccountID)
        XCTAssertTrue(model.rows.allSatisfy { !$0.isActive })
    }

    func testTerminalLabelFollowsTokenState() {
        let model = build(active: nil)
        XCTAssertEqual(model.rows[0].terminalLabel, .openTerminal)
        XCTAssertEqual(model.rows[2].terminalLabel, .logInFirst)
    }

    func testDesktopLabelsAndRunningFlag() {
        let model = build(active: nil, running: [play.id])
        XCTAssertEqual(model.rows[1].desktopLabel, "Bring Claude app to front")
        XCTAssertEqual(model.rows[0].desktopLabel, "Open Claude app")
        XCTAssertTrue(model.rows[1].desktopRunning)
    }

    func testSessionsLineReflectsNextTurnFollowing() {
        XCTAssertNil(build(active: nil).sessionsLine)
        XCTAssertEqual(build(active: nil, sessions: 1).sessionsLine, "1 terminal session running · it follows on its next turn")
        XCTAssertEqual(build(active: nil, sessions: 3).sessionsLine, "3 terminal sessions running · they follow on their next turn")
    }

    func testHintsFollowHotkeySetting() {
        XCTAssertEqual(build(active: nil).rows.map(\.hint), ["⌃⌥1", "⌃⌥2", "⌃⌥3"])
        XCTAssertEqual(build(active: nil, hotkeys: .off).rows.map(\.hint), [nil, nil, nil])
        XCTAssertEqual(build(active: nil, positions: [0]).rows.map(\.hint), ["⌃⌥1", nil, nil])
    }
}
