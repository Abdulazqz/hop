import XCTest
@testable import SwitcherCore

final class ClaudeSettingsTests: XCTestCase {
    let helper = "/Users/me/Library/Application Support/Hop/hop-apikeyhelper.sh"
    let ttlKey = "CLAUDE_CODE_API_KEY_HELPER_TTL_MS"

    func nsdict(_ data: Data) -> NSDictionary {
        try! JSONSerialization.jsonObject(with: data) as! NSDictionary
    }

    func testEnablePreservesOtherKeysAndEnvEntries() throws {
        let input = Data(#"{"model":"x","env":{"FOO":"1"}}"#.utf8)
        let out = nsdict(try ClaudeSettings.enableHelper(input, helperPath: helper, ttlMs: 3000))
        XCTAssertEqual(out["model"] as? String, "x")
        XCTAssertEqual(out["apiKeyHelper"] as? String, helper)
        let env = out["env"] as? [String: Any]
        XCTAssertEqual(env?["FOO"] as? String, "1")
        XCTAssertEqual(env?[ttlKey] as? String, "3000")
    }

    func testEnableFromNilStartsFromEmpty() throws {
        let out = nsdict(try ClaudeSettings.enableHelper(nil, helperPath: helper, ttlMs: 3000))
        XCTAssertEqual(out["apiKeyHelper"] as? String, helper)
        XCTAssertEqual((out["env"] as? [String: Any])?[ttlKey] as? String, "3000")
        XCTAssertEqual(out.count, 2)
    }

    func testEnableDisableRoundTripsPreservingEnv() throws {
        let input = Data(#"{"model":"x","env":{"FOO":"1"}}"#.utf8)
        let enabled = try ClaudeSettings.enableHelper(input, helperPath: helper, ttlMs: 3000)
        let disabled = try ClaudeSettings.disableHelper(enabled)
        XCTAssertEqual(nsdict(disabled), nsdict(input))
    }

    func testDisableDropsEnvWhenItBecomesEmpty() throws {
        let enabled = try ClaudeSettings.enableHelper(nil, helperPath: helper, ttlMs: 3000)
        let disabled = try ClaudeSettings.disableHelper(enabled)
        XCTAssertEqual(nsdict(disabled), NSDictionary())
    }

    func testEnableOnInvalidJSONThrows() {
        XCTAssertThrowsError(try ClaudeSettings.enableHelper(Data("not json".utf8), helperPath: helper, ttlMs: 3000))
    }
}
