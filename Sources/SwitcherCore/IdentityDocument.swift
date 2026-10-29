import Foundation

/// Claude Code's `~/.claude.json`. Hop only ever touches its `oauthAccount` object.
public enum IdentityDocument {
    public enum DocumentError: Error, Equatable {
        case notAnObject
    }

    public static func identity(of document: Data) throws -> Data? {
        guard let object = LiveLogin.jsonObject(document) else { throw DocumentError.notAnObject }
        guard let identity = object[LiveLogin.identityKey] as? [String: Any] else { return nil }
        return try JSONSerialization.data(withJSONObject: identity)
    }

    public static func email(inIdentity identity: Data) -> String? { string(LiveLogin.emailKey, inIdentity: identity) }
    public static func organizationUuid(inIdentity identity: Data) -> String? { string(LiveLogin.organizationUuidKey, inIdentity: identity) }
    public static func organizationName(inIdentity identity: Data) -> String? { string(LiveLogin.organizationNameKey, inIdentity: identity) }

    static func string(_ key: String, inIdentity identity: Data) -> String? {
        guard let object = LiveLogin.jsonObject(identity) else { return nil }
        return LiveLogin.string(object[key])
    }

    public static func replacingIdentity(in document: Data?, with identity: Data) throws -> Data {
        var object: [String: Any] = [:]
        if let document {
            guard let existing = LiveLogin.jsonObject(document) else { throw DocumentError.notAnObject }
            object = existing
        }
        guard let identityObject = LiveLogin.jsonObject(identity) else { throw DocumentError.notAnObject }
        object[LiveLogin.identityKey] = identityObject
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}

/// Write-to-temp-then-rename, so readers never see a half-written file.
public enum AtomicFile {
    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).hop-\(UUID().uuidString)")
        try data.write(to: temp, options: [])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp, options: .usingNewMetadataOnly)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}
