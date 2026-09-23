import XCTest
@testable import SwitcherCore

final class RunningSessionsTests: XCTestCase {
    func testCountsOnlyProcessesNamedClaude() {
        XCTAssertEqual(RunningSessions.count(processNames: ["claude", "Claude", "node", "claude", "claude-helper"]), 2)
    }

    func testLiveCountDoesNotCrash() {
        XCTAssertGreaterThanOrEqual(RunningSessions.count(), 0)
    }
}
