import Foundation

/// Builds Claude Code-shaped data with fake tokens. Never real credentials.
enum LoginFixtures {
    /// 2100-01-01 in Unix ms: comfortably in the future.
    static let farFuture: Double = 4_102_444_800_000

    static func keychainValue(access: String = "at-1", refresh: String = "rt-1",
                              expiresAt: Double = farFuture, refreshTokenExpiresAt: Double = farFuture,
                              extra: [String: Any] = ["mcpOAuth": ["srv|1": ["accessToken": "m-1"]]]) -> Data {
        var object = extra
        object["claudeAiOauth"] = ["accessToken": access, "refreshToken": refresh, "expiresAt": expiresAt,
                                   "refreshTokenExpiresAt": refreshTokenExpiresAt, "scopes": ["user:inference"],
                                   "subscriptionType": "max", "rateLimitTier": "default"] as [String: Any]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    static func identityDocument(email: String? = "a@example.com", organizationUuid: String? = nil, organizationName: String? = "Org",
                                 extra: [String: Any] = ["numStartups": 3]) -> Data {
        var object = extra
        if let email {
            var identity: [String: Any] = ["emailAddress": email, "accountUuid": "acc-\(email)"]
            if let organizationUuid { identity["organizationUuid"] = organizationUuid }
            if let organizationName { identity["organizationName"] = organizationName }
            object["oauthAccount"] = identity
        }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    static func json(_ data: Data) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}
