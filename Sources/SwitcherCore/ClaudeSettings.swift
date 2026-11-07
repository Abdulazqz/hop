import Foundation

public enum ClaudeSettingsError: Error, Equatable {
    /// Input was non-empty but not a JSON object: refuse rather than clobber the user's settings.
    case invalidJSON
}

/// Pure merge/unmerge of Hop's `apiKeyHelper` (and its TTL env entry) into Claude Code's settings JSON.
/// Every other top-level key and every other `env` entry is preserved untouched.
public enum ClaudeSettings {
    static let ttlKey = "CLAUDE_CODE_API_KEY_HELPER_TTL_MS"

    /// Sets `apiKeyHelper` and `env.CLAUDE_CODE_API_KEY_HELPER_TTL_MS`. nil/empty input starts from `{}`.
    public static func enableHelper(_ json: Data?, helperPath: String, ttlMs: Int) throws -> Data {
        var root = try object(from: json)
        root["apiKeyHelper"] = helperPath
        var env = root["env"] as? [String: Any] ?? [:]
        env[ttlKey] = String(ttlMs)
        root["env"] = env
        return try data(from: root)
    }

    /// Removes exactly `apiKeyHelper` and the TTL env entry, dropping `env` only if it becomes empty.
    public static func disableHelper(_ json: Data?) throws -> Data {
        var root = try object(from: json)
        root["apiKeyHelper"] = nil
        if var env = root["env"] as? [String: Any] {
            env[ttlKey] = nil
            root["env"] = env.isEmpty ? nil : env
        }
        return try data(from: root)
    }

    static func object(from json: Data?) throws -> [String: Any] {
        guard let json, !json.isEmpty else { return [:] }
        guard let any = try? JSONSerialization.jsonObject(with: json),
              let dict = any as? [String: Any] else { throw ClaudeSettingsError.invalidJSON }
        return dict
    }

    static func data(from root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted])
    }
}
