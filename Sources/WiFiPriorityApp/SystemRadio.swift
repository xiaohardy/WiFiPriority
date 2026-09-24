import CoreWLAN
import Foundation
import Security
import WiFiPriorityCore

enum ConnectionFailure {
    case scanFailed
    case notFound
    case associationRejected(Int)
    case timedOut

    var message: StatusMessage {
        switch self {
        case .scanFailed: return .init(.testScanFailed)
        case .notFound: return .init(.testNetworkNotFound)
        case .associationRejected(let code):
            return .init(.testAssociationRejected, ["code": String(code)])
        case .timedOut: return .init(.testTimedOut)
        }
    }
}

private struct AssociationCancelled: Error {}

final class SystemRadio: Radio {
    let interface: CWInterface
    private let directedSSIDs: [String]
    private let prioritySSIDs: [String]
    private let credentialReadySSIDs: Set<String>
    private var failures: [String: ConnectionFailure] = [:]
    private var scannedNetworks: [String: CWNetwork] = [:]

    init?(directedSSIDs: [String] = [], prioritySSIDs: [String] = [],
          credentialReadySSIDs: Set<String> = []) {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        self.interface = interface
        self.directedSSIDs = directedSSIDs
        self.prioritySSIDs = prioritySSIDs
        self.credentialReadySSIDs = credentialReadySSIDs
    }

    var current: String? { interface.ssid() }
    var powered: Bool { interface.powerOn() }
    func failure(for ssid: String) -> ConnectionFailure? { failures[ssid] }

    var savedNetworkNames: [String] {
        let profiles = interface.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
        return Array(Set(profiles.compactMap(\.ssid).filter { !$0.isEmpty })).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    func scan() throws -> [String: Int] {
        scannedNetworks.removeAll()
        let networks = try interface.scanForNetworks(withName: nil, includeHidden: true)
        if !networks.isEmpty && networks.allSatisfy({ $0.ssid == nil }) {
            throw NSError(domain: "WiFiPriority.Permission", code: 1)
        }
        var visible = [String: Int]()
        for network in networks {
            record(network, in: &visible)
        }
        // A broadcast scan cannot reliably reveal a hidden SSID. A directed
        // scan asks only for networks the user explicitly marked as hidden.
        let associated = current
        let directed = prioritySSIDs.isEmpty ? directedSSIDs :
            PriorityScanScope.directedNames(networks: prioritySSIDs,
                                            hidden: Set(directedSSIDs), current: associated)
        for name in directed where visible[name] == nil && name != associated {
            guard let matches = try? interface.scanForNetworks(withName: name, includeHidden: true) else { continue }
            for network in matches where network.ssid == name {
                record(network, in: &visible)
            }
        }
        return visible
    }

    private func record(_ network: CWNetwork, in visible: inout [String: Int]) {
        guard let name = network.ssid, network.rssiValue > (visible[name] ?? -1000) else { return }
        visible[name] = network.rssiValue
        scannedNetworks[name] = network
    }

    private func fail(_ reason: ConnectionFailure, for ssid: String) -> JoinResult {
        failures[ssid] = reason
        return .failed
    }

    private static func keychainPassword(for ssid: String, domain: CWKeychainDomain) -> (OSStatus, String?) {
        var value: NSString?
        let status = CWKeychainFindWiFiPassword(domain, Data(ssid.utf8), &value)
        return (status, value as String?)
    }

    static func requestSavedCredential(for ssid: String, allowedSSIDs: Set<String>) -> CredentialLookupResult {
        guard allowedSSIDs.contains(ssid) else { return .outsideScope }
        var previous = DarwinBoolean(false)
        let status = SecKeychainGetUserInteractionAllowed(&previous)
        guard status == errSecSuccess else { return .unavailable(status) }
        let enableStatus = SecKeychainSetUserInteractionAllowed(true)
        guard enableStatus == errSecSuccess else { return .unavailable(enableStatus) }
        defer { _ = SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        // This is called only from the user's explicit setup action. macOS
        // may ask once for each original System Keychain Wi-Fi item.
        return ScopedWiFiCredential.find(
            ssid: ssid,
            allowedSSIDs: allowedSSIDs,
            systemLookup: { keychainPassword(for: $0, domain: .system) },
            userLookup: { keychainPassword(for: $0, domain: .user) }
        )
    }

    func connect(to ssid: String, permitted: () -> Bool) -> JoinResult {
        failures[ssid] = nil
        guard powered, permitted() else { return .cancelled }
        let original = current
        if original == ssid { return .connected }

        // Only the exact configured target may be looked up. The app never
        // enumerates other Keychain items or writes a password to settings/logs.
        let network: CWNetwork?
        if let scanned = scannedNetworks[ssid] {
            network = scanned
        } else {
            do {
                network = try interface.scanForNetworks(withName: ssid, includeHidden: true)
                    .filter { $0.ssid == ssid }
                    .max(by: { $0.rssiValue < $1.rssiValue })
            } catch {
                return fail(.scanFailed, for: ssid)
            }
        }
        guard powered, permitted(), current == original else { return .cancelled }
        guard let network else {
            return fail(.notFound, for: ssid)
        }

        let isOpen = network.supportsSecurity(.none) || network.supportsSecurity(.OWE) ||
            network.supportsSecurity(.oweTransition)
        let password: String?
        if isOpen {
            password = nil
        } else {
            guard credentialReadySSIDs.contains(ssid) else { return .requiresCredentialSetup }
            let (_, vault) = WiFiCredentialVault.login(allowedSSIDs: credentialReadySSIDs)
            guard let vault else { return .requiresCredentialSetup }
            switch vault.read(ssid) {
            case .password(let saved): password = saved
            case .missing, .denied, .unavailable, .outsideScope: return .requiresCredentialSetup
            }
        }
        do {
            guard powered, permitted(), current == original else { throw AssociationCancelled() }
            try interface.associate(to: network, password: password)
        } catch is AssociationCancelled {
            return .cancelled
        } catch {
            return fail(.associationRejected((error as NSError).code), for: ssid)
        }

        let deadline = ProcessInfo.processInfo.systemUptime + 25
        var associatedSince: TimeInterval?
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard permitted(), powered else { return .cancelled }
            let actual = current
            if let actual, actual != ssid, actual != original { return .cancelled }
            if actual == ssid {
                if associatedSince == nil { associatedSince = ProcessInfo.processInfo.systemUptime }
                if ProcessInfo.processInfo.systemUptime - associatedSince! >= 2 { return .connected }
            } else {
                associatedSince = nil
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return fail(.timedOut, for: ssid)
    }
}
