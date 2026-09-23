import Foundation

/// The value Hop stores in its own Keychain items: one captured terminal login plus its identity.
public struct SavedLogin: Equatable {
    public static let formatVersion = 1

    public let loginSection: Data   // the claudeAiOauth object, serialized
    public let identity: Data       // the oauthAccount object, serialized
    public let capturedAt: Date

    public init(loginSection: Data, identity: Data, capturedAt: Date) {
        self.loginSection = loginSection
        self.identity = identity
        self.capturedAt = capturedAt
    }

    public enum FormatError: Error, Equatable {
        case notAnObject
        case unsupportedVersion(Int)
        case missingField(String)
    }

    public var email: String? { IdentityDocument.email(inIdentity: identity) }
    public var refreshTokenExpiresAt: Date? { LiveLogin.refreshTokenExpiry(ofLoginSection: loginSection) }
    public var refreshTokenSHA256: String? { LiveLogin.refreshTokenSHA256(ofLoginSection: loginSection) }

    public func encoded() throws -> Data {
        guard let login = LiveLogin.jsonObject(loginSection), let identityObject = LiveLogin.jsonObject(identity) else {
            throw FormatError.notAnObject
        }
        let object: [String: Any] = [
            "version": Self.formatVersion,
            LiveLogin.loginKey: login,
            LiveLogin.identityKey: identityObject,
            "capturedAt": ISO8601DateFormatter().string(from: capturedAt),
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    public static func decode(_ data: Data) throws -> SavedLogin {
        guard let object = LiveLogin.jsonObject(data) else { throw FormatError.notAnObject }
        let version = (object["version"] as? NSNumber)?.intValue ?? 0
        guard version == formatVersion else { throw FormatError.unsupportedVersion(version) }
        guard let login = object[LiveLogin.loginKey] as? [String: Any] else { throw FormatError.missingField(LiveLogin.loginKey) }
        guard let identity = object[LiveLogin.identityKey] as? [String: Any] else { throw FormatError.missingField(LiveLogin.identityKey) }
        guard let stamp = object["capturedAt"] as? String else { throw FormatError.missingField("capturedAt") }
        return SavedLogin(loginSection: try JSONSerialization.data(withJSONObject: login),
                          identity: try JSONSerialization.data(withJSONObject: identity),
                          capturedAt: ISO8601DateFormatter().date(from: stamp) ?? .distantPast)
    }
}
