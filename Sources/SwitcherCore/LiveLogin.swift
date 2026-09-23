import CryptoKit
import Foundation

/// What Claude Code's shared terminal login looks like right now.
public struct LoginSummary: Equatable {
    public let email: String
    public let refreshTokenSHA256: String
    public let expiresAt: Date
    public let refreshTokenExpiresAt: Date

    public init(email: String, refreshTokenSHA256: String, expiresAt: Date, refreshTokenExpiresAt: Date) {
        self.email = email
        self.refreshTokenSHA256 = refreshTokenSHA256
        self.expiresAt = expiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }
}

public enum LiveLoginState: Equatable {
    case loggedIn(LoginSummary)
    case loggedOut
    /// The data isn't shaped the way Hop knows. The string says what was wrong; Hop touches nothing.
    case unrecognized(String)
}

/// Reads and rewrites the value of Claude Code's Keychain item ("Claude Code-credentials").
/// Only the `claudeAiOauth` object is ever replaced; every other key is carried over untouched.
public enum LiveLogin {
    public static let loginKey = "claudeAiOauth"
    public static let identityKey = "oauthAccount"
    public static let emailKey = "emailAddress"

    public enum LoginError: Error, Equatable {
        case notAnObject
        case missingLoginSection
    }

    public static func parse(keychainValue: Data?, identityDocument: Data?) -> LiveLoginState {
        guard let keychainValue else { return .loggedOut }
        guard let object = jsonObject(keychainValue) else { return .unrecognized("the Keychain item isn't a JSON object") }
        guard let login = object[loginKey] as? [String: Any] else { return .unrecognized("no \(loginKey) section") }
        let access = login["accessToken"] as? String ?? ""
        let refresh = login["refreshToken"] as? String ?? ""
        let expiresAt = millis(login["expiresAt"])
        if access.isEmpty || refresh.isEmpty || expiresAt == nil || expiresAt == 0 { return .loggedOut }
        guard let refreshExpiresAt = millis(login["refreshTokenExpiresAt"]) else {
            return .unrecognized("\(loginKey) has no refreshTokenExpiresAt")
        }
        guard let identityDocument, let document = jsonObject(identityDocument) else {
            return .unrecognized("~/.claude.json is missing or isn't valid JSON")
        }
        guard let identity = document[identityKey] as? [String: Any],
              let email = identity[emailKey] as? String, !email.isEmpty else {
            return .unrecognized("~/.claude.json has no \(identityKey).\(emailKey)")
        }
        return .loggedIn(LoginSummary(email: email, refreshTokenSHA256: sha256Hex(refresh),
                                      expiresAt: Date(timeIntervalSince1970: expiresAt! / 1000),
                                      refreshTokenExpiresAt: Date(timeIntervalSince1970: refreshExpiresAt / 1000)))
    }

    /// The identity file alone, for display. No Keychain access, so no token hash and no expiry.
    public static func parseIdentityOnly(identityDocument: Data?) -> LiveLoginState {
        guard let identityDocument else { return .loggedOut }
        guard let document = jsonObject(identityDocument) else { return .unrecognized("~/.claude.json isn't valid JSON") }
        guard let identity = document[identityKey] as? [String: Any],
              let email = identity[emailKey] as? String, !email.isEmpty else { return .loggedOut }
        return .loggedIn(LoginSummary(email: email, refreshTokenSHA256: "", expiresAt: .distantFuture, refreshTokenExpiresAt: .distantFuture))
    }

    public static func loginSection(of keychainValue: Data) throws -> Data {
        guard let object = jsonObject(keychainValue) else { throw LoginError.notAnObject }
        guard let login = object[loginKey] as? [String: Any] else { throw LoginError.missingLoginSection }
        return try JSONSerialization.data(withJSONObject: login)
    }

    public static func replacingLoginSection(in keychainValue: Data?, with section: Data) throws -> Data {
        var object: [String: Any] = [:]
        if let keychainValue {
            guard let existing = jsonObject(keychainValue) else { throw LoginError.notAnObject }
            object = existing
        }
        guard let login = jsonObject(section) else { throw LoginError.notAnObject }
        object[loginKey] = login
        return try JSONSerialization.data(withJSONObject: object)
    }

    public static func refreshTokenExpiry(ofLoginSection section: Data) -> Date? {
        guard let login = jsonObject(section), let ms = millis(login["refreshTokenExpiresAt"]) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    public static func refreshTokenSHA256(ofLoginSection section: Data) -> String? {
        guard let login = jsonObject(section), let refresh = login["refreshToken"] as? String, !refresh.isEmpty else { return nil }
        return sha256Hex(refresh)
    }

    public static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - helpers

    static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func millis(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
