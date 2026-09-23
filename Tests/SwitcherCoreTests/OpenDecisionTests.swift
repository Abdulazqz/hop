import XCTest
@testable import SwitcherCore

final class OpenDecisionTests: XCTestCase {
    func testRunningFocusesRegardlessOfOtherState() {
        XCTAssertEqual(OpenDecision.decide(running: true, launching: false, pendingAlive: false), .focusRunning)
        XCTAssertEqual(OpenDecision.decide(running: true, launching: true, pendingAlive: false), .focusRunning)
        XCTAssertEqual(OpenDecision.decide(running: true, launching: false, pendingAlive: true), .focusRunning)
        XCTAssertEqual(OpenDecision.decide(running: true, launching: true, pendingAlive: true), .focusRunning)
    }

    func testLaunchingWaitsWhenNotRunning() {
        XCTAssertEqual(OpenDecision.decide(running: false, launching: true, pendingAlive: false), .wait)
        XCTAssertEqual(OpenDecision.decide(running: false, launching: true, pendingAlive: true), .wait)
    }

    func testPendingAliveFocusesWhenNotRunningOrLaunching() {
        XCTAssertEqual(OpenDecision.decide(running: false, launching: false, pendingAlive: true), .focusPending)
    }

    func testLaunchesWhenNoneOfTheAboveApply() {
        XCTAssertEqual(OpenDecision.decide(running: false, launching: false, pendingAlive: false), .launch)
    }
}
