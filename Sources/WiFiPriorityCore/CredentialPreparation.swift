import Security

/// A configured network is ready only after the app-owned copy can be read
/// without asking macOS to unlock the original system Wi-Fi item again.
public enum CredentialPreparation {
    public static func prepare(
        ssid: String,
        allowedSSIDs: Set<String>,
        refreshExisting: Bool = false,
        cacheLookup: (String) -> CredentialLookupResult,
        sourceLookup: (String) -> CredentialLookupResult,
        cacheStore: (String, String) -> OSStatus
    ) -> CredentialLookupResult {
        guard allowedSSIDs.contains(ssid) else { return .outsideScope }
        let cached = cacheLookup(ssid)
        if case .password = cached, !refreshExisting { return cached }
        guard cached == .missing || refreshExisting else { return cached }
        let source = sourceLookup(ssid)
        guard case .password(let password) = source else { return source }
        let status = cacheStore(ssid, password)
        guard status == errSecSuccess else { return .unavailable(status) }
        let verified = cacheLookup(ssid)
        guard verified == .password(password) else {
            if case .password = verified { return .unavailable(errSecDecode) }
            return verified
        }
        return verified
    }
}
