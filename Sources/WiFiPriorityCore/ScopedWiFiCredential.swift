import Security

public enum CredentialLookupResult: Equatable {
    case password(String)
    case missing
    case denied
    case unavailable(OSStatus)
    case outsideScope
}

/// Reads only the Wi-Fi item whose exact SSID the user put in the priority list.
/// The system domain is preferred; the user domain is tried only if that item
/// does not exist. A denied request never causes a second prompt elsewhere.
public enum ScopedWiFiCredential {
    public static func find(
        ssid: String,
        allowedSSIDs: Set<String>,
        systemLookup: (String) -> (OSStatus, String?),
        userLookup: (String) -> (OSStatus, String?)
    ) -> CredentialLookupResult {
        guard allowedSSIDs.contains(ssid) else { return .outsideScope }
        let system = systemLookup(ssid)
        if system.0 == errSecSuccess, let value = system.1, !value.isEmpty {
            return .password(value)
        }
        guard system.0 == errSecSuccess || system.0 == errSecItemNotFound else {
            return classify(system.0)
        }
        let user = userLookup(ssid)
        if user.0 == errSecSuccess, let value = user.1, !value.isEmpty {
            return .password(value)
        }
        if user.0 == errSecSuccess || user.0 == errSecItemNotFound { return .missing }
        return classify(user.0)
    }

    private static func classify(_ status: OSStatus) -> CredentialLookupResult {
        switch status {
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed, errSecInteractionRequired:
            return .denied
        default: return .unavailable(status)
        }
    }
}
