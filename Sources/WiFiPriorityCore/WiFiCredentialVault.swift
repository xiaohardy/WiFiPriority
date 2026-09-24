import Foundation
import Security

/// The app's own generic-password items in the user's login Keychain.
/// A different service name keeps them separate from macOS AirPort items.
public struct WiFiCredentialVault {
    public static let service = "org.wifipriority.saved-wifi.v1"

    private let keychain: SecKeychain
    private let allowedSSIDs: Set<String>
    private let serviceName: String

    public init(keychain: SecKeychain, allowedSSIDs: Set<String>, serviceName: String = service) {
        self.keychain = keychain
        self.allowedSSIDs = allowedSSIDs
        self.serviceName = serviceName
    }

    public static func login(allowedSSIDs: Set<String>) -> (OSStatus, WiFiCredentialVault?) {
        var keychain: SecKeychain?
        let status = SecKeychainCopyDomainDefault(.user, &keychain)
        guard status == errSecSuccess, let keychain else { return (status, nil) }
        return (errSecSuccess, .init(keychain: keychain, allowedSSIDs: allowedSSIDs))
    }

    private func query(_ ssid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: serviceName,
         kSecAttrAccount as String: ssid,
         kSecMatchSearchList as String: [keychain],
         kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
    }

    public func read(_ ssid: String) -> CredentialLookupResult {
        guard allowedSSIDs.contains(ssid) else { return .outsideScope }
        var request = query(ssid)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let password = String(data: data, encoding: .utf8), !password.isEmpty {
            return .password(password)
        }
        switch status {
        case errSecItemNotFound: return .missing
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed, errSecInteractionRequired:
            return .denied
        case errSecSuccess: return .unavailable(errSecDecode)
        default: return .unavailable(status)
        }
    }

    public func store(_ password: String, for ssid: String) -> OSStatus {
        guard allowedSSIDs.contains(ssid), !password.isEmpty else { return errSecParam }
        var access: SecAccess?
        let accessStatus = SecAccessCreate("WiFi Priority: \(ssid)" as CFString, nil, &access)
        guard accessStatus == errSecSuccess, let access else { return accessStatus }
        let data = Data(password.utf8)
        var attributes = query(ssid)
        attributes.removeValue(forKey: kSecMatchSearchList as String)
        attributes[kSecUseKeychain as String] = keychain
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccess as String] = access
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecDuplicateItem else { return status }
        // Refresh a password after the user updates it in macOS. The existing
        // item remains app-owned; no System Keychain ACL is modified.
        return SecItemUpdate(query(ssid) as CFDictionary,
                             [kSecValueData as String: data] as CFDictionary)
    }

    public func delete(_ ssid: String) -> OSStatus {
        guard allowedSSIDs.contains(ssid) else { return errSecParam }
        let status = SecItemDelete(query(ssid) as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}
