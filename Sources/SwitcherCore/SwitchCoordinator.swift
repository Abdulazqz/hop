import Foundation

public protocol LoginStore {
    /// Claude Code's own item; nil when it doesn't exist.
    func readLive() throws -> Data?
    func writeLive(_ value: Data) throws
    /// Removes Claude Code's item; used only to undo a write Hop just made.
    func deleteLive() throws
    func readSaved(_ accountID: UUID) throws -> Data?
    func writeSaved(_ value: Data, for accountID: UUID) throws
    func deleteSaved(_ accountID: UUID) throws
}

public protocol IdentityDocumentStore {
    /// `~/.claude.json`; nil when the file doesn't exist.
    func read() throws -> Data?
    func write(_ document: Data) throws
}

public enum UnknownLoginChoice: Equatable {
    case attach(UUID)
    case create
}

public enum SwitchError: Error, Equatable, LocalizedError {
    case unrecognizedLogin(String)
    case targetHasNoLogin(String)
    case targetLoginExpired(name: String, on: Date)
    case alreadyActive(String)
    case cancelled(login: String)
    case attachTargetHasLogin(String)
    case store(String)
    case rolledBack(String)

    public var errorDescription: String? {
        switch self {
        case .unrecognizedLogin(let why): "Claude Code's login format changed (\(why)). Hop won't touch it."
        case .targetHasNoLogin(let name): "\(name) has no saved terminal login yet. Log in as it once, then switch to any other account so Hop can save it."
        case .targetLoginExpired(let name, let on):
            "\(name)'s saved login expired on \(on.formatted(date: .abbreviated, time: .omitted)). Log in as it once in Terminal."
        case .alreadyActive(let name): "\(name) is already the active account."
        case .cancelled(let login): "The current login (\(login)) isn't saved. Save it first, or the switch would lose it."
        case .attachTargetHasLogin(let name): "\(name) already has a saved login. Pick an account without one, or create a new account."
        case .store(let why): why
        case .rolledBack(let message): message
        }
    }
}

public struct SwitchResult: Equatable {
    public let from: UUID?
    public let to: UUID
    public let accounts: [Account]
    public let state: HopState
}

/// The switch procedure from the spec. Pure apart from the two stores it is given.
public struct SwitchCoordinator {
    private let logins: LoginStore
    private let identityDocument: IdentityDocumentStore
    private let home: String
    private let now: () -> Date

    public init(logins: LoginStore, identityDocument: IdentityDocumentStore, home: String, now: @escaping () -> Date = Date.init) {
        self.logins = logins
        self.identityDocument = identityDocument
        self.home = home
        self.now = now
    }

    public func switchTo(_ targetID: UUID, accounts: [Account], state: HopState,
                         resolveUnknown: (String) -> UnknownLoginChoice?) throws -> SwitchResult {
        guard let target = accounts.first(where: { $0.id == targetID }) else { throw SwitchError.store("unknown account") }
        // 1. Read everything before writing anything.
        let liveValue = try logins.readLive()
        let document = try identityDocument.read()
        let live = LiveLogin.parse(keychainValue: liveValue, identityDocument: document)
        if case .unrecognized(let why) = live { throw SwitchError.unrecognizedLogin(why) }
        var accounts = accounts

        // 3 (early). The target must be usable, so a refused switch never captures anything either.
        guard let savedData = try logins.readSaved(targetID) else { throw SwitchError.targetHasNoLogin(target.name) }
        let saved = try SavedLogin.decode(savedData)
        guard let refreshExpiry = saved.refreshTokenExpiresAt else { throw SwitchError.unrecognizedLogin("saved login has no expiry") }
        if refreshExpiry <= now().addingTimeInterval(60) { throw SwitchError.targetLoginExpired(name: target.name, on: refreshExpiry) }
        Self.learnOrganization(of: targetID, from: saved, in: &accounts)

        // 2. Attribute and save the outgoing login.
        var from: UUID?
        if case .loggedIn(let summary) = live, let liveValue, let document {
            let (outgoingID, updated) = try captureLive(summary: summary, liveValue: liveValue, document: document,
                                                        accounts: accounts, state: state, resolveUnknown: resolveUnknown)
            accounts = updated
            from = outgoingID
            if outgoingID == targetID {
                // A stale session may have rewritten the identity file; put back the one saved for this account.
                if saved.email != nil, !saved.matchesIdentity(of: summary) {
                    try identityDocument.write(IdentityDocument.replacingIdentity(in: document, with: saved.identity))
                }
                throw SwitchError.alreadyActive(target.name)
            }
        }

        // 4. Write: Keychain, then identity; undo the Keychain if the identity write fails.
        let newLive = try LiveLogin.replacingLoginSection(in: liveValue, with: saved.loginSection)
        let newDocument = try IdentityDocument.replacingIdentity(in: document, with: saved.identity)
        try logins.writeLive(newLive)
        do {
            try identityDocument.write(newDocument)
        } catch {
            do {
                if let liveValue { try logins.writeLive(liveValue) } else { try logins.deleteLive() }
            } catch let restoreError {
                throw SwitchError.rolledBack("Couldn't finish the switch (\(error.localizedDescription)), and restoring the previous login also failed (\(restoreError.localizedDescription)).")
            }
            throw SwitchError.rolledBack("Couldn't finish the switch (\(error.localizedDescription)). The previous login was restored.")
        }
        let newState = HopState(activeAccountID: targetID, writtenRefreshTokenSHA256: saved.refreshTokenSHA256)
        return SwitchResult(from: from, to: targetID, accounts: accounts, state: newState)
    }

    /// Menu action "Save current login as…": capture without switching.
    public func saveCurrentLogin(accounts: [Account], state: HopState, choice: UnknownLoginChoice) throws -> (accounts: [Account], state: HopState) {
        let liveValue = try logins.readLive()
        let document = try identityDocument.read()
        guard case .loggedIn(let summary) = LiveLogin.parse(keychainValue: liveValue, identityDocument: document),
              let liveValue, let document else {
            throw SwitchError.unrecognizedLogin("nothing is logged in")
        }
        let (id, updated) = try captureLive(summary: summary, liveValue: liveValue, document: document,
                                            accounts: accounts, state: state, resolveUnknown: { _ in choice })
        return (updated, HopState(activeAccountID: id, writtenRefreshTokenSHA256: summary.refreshTokenSHA256))
    }

    /// Named after the email; after the organization too when another account already has that email.
    public static func newAccount(email: String, organizationUuid: String?, organizationName: String?,
                                  accounts: [Account], home: String) -> Account {
        let used = Set(accounts.map(\.color))
        let color = AccountColor.allCases.first { !used.contains($0) } ?? .gray
        let emailTaken = accounts.contains { $0.normalizedEmail == Account.normalized(email)?.lowercased() }
        var base = email
        if emailTaken, let organization = Account.normalized(organizationName) { base = "\(email) (\(organization))" }
        let name = uniqueName(base, among: accounts)
        let folder = NewAccountFolder.candidate(forName: name, accounts: accounts, home: home)
        return Account(name: name, color: color, folder: folder, email: email,
                       organizationUuid: organizationUuid, organizationName: organizationName)
    }

    /// `base`, or `base 2`, `base 3`… when an account already has that name (case-insensitive).
    static func uniqueName(_ base: String, among accounts: [Account]) -> String {
        let taken = Set(accounts.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var candidate = base
        var n = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(base) \(n)"
            n += 1
        }
        return candidate
    }

    /// Records the organization an account's saved login belongs to, when the account doesn't know it yet.
    static func learnOrganization(of id: UUID, from saved: SavedLogin, in accounts: inout [Account]) {
        guard let index = accounts.firstIndex(where: { $0.id == id }), accounts[index].organizationUuid == nil,
              let organization = saved.organizationUuid else { return }
        accounts[index].organizationUuid = organization
        accounts[index].organizationName = saved.organizationName
    }

    // MARK: - capture

    /// Saves the live login under the account it belongs to, creating or attaching when unknown.
    /// Returns that account's id and the (possibly extended) account list.
    private func captureLive(summary: LoginSummary, liveValue: Data, document: Data, accounts: [Account], state: HopState,
                             resolveUnknown: (String) -> UnknownLoginChoice?) throws -> (UUID, [Account]) {
        var accounts = accounts
        let section = try LiveLogin.loginSection(of: liveValue)
        var identity = try IdentityDocument.identity(of: document) ?? Data("{}".utf8)
        let outgoingID: UUID
        var attribution = LoginAttribution.attribute(summary, accounts: accounts, state: state)
        if case .hopWrote(let id) = attribution {
            // A stale session may have rewritten the identity file; prefer the identity we saved for this account.
            // Without a readable saved item (it was forgotten) the hash proves nothing: attribute by email instead.
            if let data = try logins.readSaved(id), let previous = try? SavedLogin.decode(data) {
                Self.learnOrganization(of: id, from: previous, in: &accounts)
                if !previous.matchesIdentity(of: summary) { identity = previous.identity }
            } else {
                attribution = LoginAttribution.attribute(summary, accounts: accounts, state: .empty)
            }
        }
        if case .emailMatch(let id) = attribution, let index = accounts.firstIndex(where: { $0.id == id }),
           accounts[index].organizationUuid == nil,
           let data = try logins.readSaved(id), let previous = try? SavedLogin.decode(data), previous.organizationUuid != nil {
            // Matched on email alone because this account predates organizations. Its saved login says which
            // organization it is; record that, then decide again so another organization's login never lands on it.
            Self.learnOrganization(of: id, from: previous, in: &accounts)
            attribution = LoginAttribution.attribute(summary, accounts: accounts, state: .empty)
        }
        switch attribution {
        case .hopWrote(let id), .emailMatch(let id):
            outgoingID = id
        case .unknown(let email):
            switch resolveUnknown(summary.label) {
            case .attach(let id)?:
                guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw SwitchError.store("unknown account") }
                if try accounts[index].email != nil || logins.readSaved(id) != nil {
                    throw SwitchError.attachTargetHasLogin(accounts[index].name)
                }
                accounts[index].email = email
                outgoingID = id
            case .create?:
                let created = Self.newAccount(email: email, organizationUuid: summary.organizationUuid,
                                              organizationName: summary.organizationName, accounts: accounts, home: home)
                accounts.append(created)
                outgoingID = created.id
            case nil:
                throw SwitchError.cancelled(login: summary.label)
            }
        }
        if let index = accounts.firstIndex(where: { $0.id == outgoingID }) {
            if accounts[index].email == nil { accounts[index].email = summary.email }
            // The organization is the saved identity's: the live one, or the repaired one when a stale session rewrote it.
            if accounts[index].organizationUuid == nil, let organization = IdentityDocument.organizationUuid(inIdentity: identity) {
                accounts[index].organizationUuid = organization
                accounts[index].organizationName = IdentityDocument.organizationName(inIdentity: identity)
            }
        }
        let saved = SavedLogin(loginSection: section, identity: identity, capturedAt: now())
        try logins.writeSaved(try saved.encoded(), for: outgoingID)
        if let index = accounts.firstIndex(where: { $0.id == outgoingID }) {
            accounts[index].savedLoginExpiresAt = saved.refreshTokenExpiresAt
        }
        return (outgoingID, accounts)
    }
}
