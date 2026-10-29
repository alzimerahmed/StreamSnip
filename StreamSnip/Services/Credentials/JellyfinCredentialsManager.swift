//
//  JellyfinCredentialsManager.swift
//  StreamSnip
//
//  Manages Jellyfin access tokens (with their user ids) stored in the Keychain.
//

import Foundation
import Security

/// Manages Jellyfin credentials stored securely in the Keychain.
///
/// A credential is the access token plus the user id the server issued with
/// it, encoded as JSON in one item — the user-scoped item endpoints need both,
/// and splitting them across two items would let a half-written login exist.
@MainActor
@Observable
final class JellyfinCredentialsManager: InstanceCredentialsManager {
    private static let keychainServiceName = "com.streamsnip.jellyfin"

    /// Tracks which instances have stored credentials (for reactive UI updates)
    private(set) var loggedInInstanceIDs: Set<UUID> = []

    /// Account-keyed, identity-scoped storage — the multi-login path.
    let accountCredentials: AccountKeychainCredentials

    /// Reference to settings manager for iCloud sync decisions
    weak var settingsManager: SettingsManager? {
        didSet { accountCredentials.settingsManager = settingsManager }
    }

    init(identityScope: CredentialIdentityScope? = nil) {
        accountCredentials = AccountKeychainCredentials(
            service: Self.keychainServiceName,
            credentialNoun: "token",
            identityScope: identityScope ?? CredentialIdentityScope()
        )
    }

    /// Whether credentials should sync to iCloud Keychain (when iCloud sync is enabled for instances).
    private var shouldSyncToiCloud: Bool {
        settingsManager?.iCloudSyncEnabled == true && settingsManager?.syncInstances == true
    }

    // MARK: - Encoding

    nonisolated static func encode(_ credential: JellyfinCredential) -> Data? {
        try? JSONEncoder().encode(credential)
    }

    nonisolated static func decode(_ data: Data) -> JellyfinCredential? {
        try? JSONDecoder().decode(JellyfinCredential.self, from: data)
    }

    // MARK: - InstanceCredentialsManager Protocol

    /// Stores the credential for a Jellyfin instance. The string is the
    /// JSON-encoded `JellyfinCredential` (token + user id).
    func setCredential(_ credential: String, for instance: Instance) {
        guard let data = credential.data(using: .utf8),
              let decoded = Self.decode(data) else {
            LoggingService.shared.error("Failed to encode Jellyfin credential", category: .keychain)
            return
        }
        store(decoded, for: instance)
    }

    /// Stores a decoded credential for a Jellyfin instance.
    func setCredential(_ credential: JellyfinCredential, for instance: Instance) {
        store(credential, for: instance)
    }

    private func store(_ credential: JellyfinCredential, for instance: Instance) {
        guard let data = Self.encode(credential) else {
            LoggingService.shared.error("Failed to encode Jellyfin credential", category: .keychain)
            return
        }

        let account = instance.id.uuidString
        let syncEnabled = shouldSyncToiCloud

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: syncEnabled,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        if status == errSecSuccess {
            LoggingService.shared.info(
                "Stored credential for Jellyfin instance",
                category: .keychain,
                details: "instanceID=\(instance.id), iCloudSync=\(syncEnabled)"
            )
            loggedInInstanceIDs.insert(instance.id)
        } else {
            LoggingService.shared.error(
                "Failed to store credential for Jellyfin instance",
                category: .keychain,
                details: "instanceID=\(instance.id), status=\(status)"
            )
        }
    }

    /// Retrieves the credential for a Jellyfin instance.
    func credential(for instance: Instance) -> String? {
        guard let decoded = storedCredential(for: instance) else { return nil }
        return Self.encode(decoded).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Retrieves the decoded credential for a Jellyfin instance.
    func jellyfinCredential(for instance: Instance) -> JellyfinCredential? {
        storedCredential(for: instance)
    }

    private func storedCredential(for instance: Instance) -> JellyfinCredential? {
        let account = instance.id.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let credential = Self.decode(data) else {
            return nil
        }

        loggedInInstanceIDs.insert(instance.id)
        return credential
    }

    /// Deletes the credential for an instance (logout).
    func deleteCredential(for instance: Instance) {
        let account = instance.id.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            LoggingService.shared.info(
                "Deleted credential for Jellyfin instance",
                category: .keychain,
                details: "instanceID=\(instance.id)"
            )
        }
        loggedInInstanceIDs.remove(instance.id)
    }

    /// Whether an instance has a stored credential.
    func isLoggedIn(for instance: Instance) -> Bool {
        if loggedInInstanceIDs.contains(instance.id) {
            return true
        }
        let hasCredential = credential(for: instance) != nil
        if hasCredential {
            loggedInInstanceIDs.insert(instance.id)
        }
        return hasCredential
    }

    /// Refreshes the logged-in status for an instance.
    func refreshLoginStatus(for instance: Instance) {
        if credential(for: instance) != nil {
            loggedInInstanceIDs.insert(instance.id)
        } else {
            loggedInInstanceIDs.remove(instance.id)
        }
    }
}

// MARK: - AccountCredentialsManager

/// Jellyfin has no `Account` concept yet (see `InstanceType.accountCapabilities`),
/// but the account-keyed plumbing is implemented so a capability row later
/// lights up sign-in without new storage code.
extension JellyfinCredentialsManager: AccountCredentialsManager {
    var isScopeResolved: Bool { accountCredentials.isScopeResolved }

    func setCredential(_ credential: String, for account: Account) {
        accountCredentials.setCredential(credential, for: account)
    }

    func credential(for account: Account) -> String? {
        accountCredentials.credential(for: account)
    }

    func deleteCredential(for account: Account) {
        accountCredentials.deleteCredential(for: account)
    }

    func deleteCredential(forAccountID accountID: UUID) {
        accountCredentials.deleteCredential(forAccountID: accountID)
    }

    func resyncCredentialsWithCurrentSetting() {
        accountCredentials.resyncCredentialsWithCurrentSetting()
    }

    func setUsername(_ username: String, for account: Account) {
        accountCredentials.setUsername(username, for: account)
    }

    func username(for account: Account) -> String? {
        accountCredentials.username(for: account)
    }

    func isLoggedIn(for account: Account) -> Bool {
        accountCredentials.isLoggedIn(for: account)
    }

    func refreshLoginStatus(for account: Account) {
        accountCredentials.refreshLoginStatus(for: account)
    }

    @discardableResult
    func migrateCredential(forAccountID accountID: UUID, fromScope sourceScope: String) -> Bool {
        accountCredentials.migrateCredential(forAccountID: accountID, fromScope: sourceScope)
    }

    @discardableResult
    func deleteCredential(forAccountID accountID: UUID, inScope scope: String) -> Bool {
        accountCredentials.deleteCredential(forAccountID: accountID, inScope: scope)
    }

    func hasAdoptableLegacyCredential(for account: Account) -> Bool {
        accountCredentials.hasAdoptableLegacyCredential(for: account)
    }

    @discardableResult
    func adoptLegacyCredential(for account: Account) -> Bool {
        accountCredentials.adoptLegacyCredential(for: account)
    }

    func deleteLegacyCredentialIfOwned(for account: Account) {
        accountCredentials.deleteLegacyCredentialIfOwned(for: account)
    }
}
