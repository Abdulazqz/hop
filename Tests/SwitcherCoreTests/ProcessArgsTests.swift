import XCTest
@testable import SwitcherCore

final class ProcessArgsTests: XCTestCase {
    let exe = "/Applications/Claude.app/Contents/MacOS/Claude"

    func testEqualsForm() {
        XCTAssertEqual(ProcessArgs.userDataDir(from: [exe, "--user-data-dir=/Users/t/Library/Application Support/Claude-acct2"]),
                       "/Users/t/Library/Application Support/Claude-acct2")
    }

    func testAbsentOrEmptyMeansDefault() {
        XCTAssertNil(ProcessArgs.userDataDir(from: [exe]))
        XCTAssertNil(ProcessArgs.userDataDir(from: [exe, "--user-data-dir="]))
    }

    func testSpaceFormIsIgnoredLikeChromium() {
        XCTAssertNil(ProcessArgs.userDataDir(from: [exe, "--user-data-dir", "/x"]))
    }

    func testLastValueWins() {
        XCTAssertEqual(ProcessArgs.userDataDir(from: [exe, "--user-data-dir=/a", "--user-data-dir=/b"]), "/b")
    }

    func testArgumentsAfterDoubleDashAreNotSwitches() {
        XCTAssertNil(ProcessArgs.userDataDir(from: [exe, "--", "--user-data-dir=/a"]))
    }

    func testArgv0IsNeverTheFlag() {
        XCTAssertNil(ProcessArgs.userDataDir(from: ["--user-data-dir=/a"]))
    }

    func testLaunchArgumentsRoundTrip() {
        let home = "/Users/tester"
        XCTAssertEqual(ProcessArgs.launchArguments(folder: nil, home: home), [])
        let args = ProcessArgs.launchArguments(folder: "~/Library/Application Support/Claude-acct3", home: home)
        XCTAssertEqual(args, ["--user-data-dir=/Users/tester/Library/Application Support/Claude-acct3"])
        XCTAssertEqual(ProcessArgs.userDataDir(from: [exe] + args),
                       "/Users/tester/Library/Application Support/Claude-acct3")
    }

    func testLaunchArgumentsEmptyOrWhitespaceFolderIsDefault() {
        let home = "/Users/tester"
        XCTAssertEqual(ProcessArgs.launchArguments(folder: "", home: home), [])
        XCTAssertEqual(ProcessArgs.launchArguments(folder: " ", home: home), [])
    }

    func testParsesProcArgs2Buffer() {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: Int32(3)) { bytes += $0 }
        bytes += Array(exe.utf8) + [0, 0, 0, 0]
        for arg in [exe, "--user-data-dir=/a b", ""] { bytes += Array(arg.utf8) + [0] }
        bytes += Array("HOME=/Users/t".utf8) + [0]
        XCTAssertEqual(ProcessArgs.parseProcArgs2(bytes), [exe, "--user-data-dir=/a b", ""])
    }

    func testTruncatedBufferReturnsNil() {
        XCTAssertNil(ProcessArgs.parseProcArgs2([1, 0]))
        var bytes: [UInt8] = []
        withUnsafeBytes(of: Int32(2)) { bytes += $0 }
        bytes += Array("/x".utf8) + [0, 0] + Array("/x".utf8) + [0]
        XCTAssertNil(ProcessArgs.parseProcArgs2(bytes))
    }

    func testReadsOwnProcess() {
        XCTAssertEqual(ProcessArgs.argv(pid: getpid()), CommandLine.arguments)
    }
}
