import XCTest
@testable import SwitcherCore

final class InstanceMatcherTests: XCTestCase {
    let home = "/Users/tester"
    let exe = "/Applications/Claude.app/Contents/MacOS/Claude"
    let main = Account(name: "Main", color: .purple, folder: nil)
    let work = Account(name: "Work", color: .teal, folder: "~/Library/Application Support/Claude-acct2")
    let side = Account(name: "Side", color: .coral, folder: "~/Library/Application Support/Claude-acct3")

    func testMapsDefaultAndCustomFolders() {
        let processes = [
            ClaudeProcess(pid: 10, argv: [exe]),
            ClaudeProcess(pid: 20, argv: [exe, "--user-data-dir=/Users/tester/Library/Application Support/Claude-acct2"]),
        ]
        XCTAssertEqual(InstanceMatcher.match(accounts: [main, work, side], processes: processes, home: home),
                       [main.id: 10, work.id: 20])
    }

    func testIgnoresUnknownFolders() {
        let processes = [ClaudeProcess(pid: 30, argv: [exe, "--user-data-dir=/Users/tester/elsewhere"])]
        XCTAssertEqual(InstanceMatcher.match(accounts: [main, work], processes: processes, home: home), [:])
    }

    func testFirstProcessWinsWhenTwoShareAFolder() {
        let argv = [exe, "--user-data-dir=/Users/tester/Library/Application Support/Claude-acct2"]
        let processes = [ClaudeProcess(pid: 40, argv: argv), ClaudeProcess(pid: 41, argv: argv)]
        XCTAssertEqual(InstanceMatcher.match(accounts: [work], processes: processes, home: home), [work.id: 40])
    }
}
