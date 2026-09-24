import Foundation

public enum JoinResult { case connected, failed, cancelled, requiresCredentialSetup }
public protocol Radio: AnyObject {
    var current: String? { get }
    var powered: Bool { get }
    func scan() throws -> [String: Int]
    func connect(to ssid: String, permitted: () -> Bool) -> JoinResult
}

/// Runs on one serial worker. No routing, DNS, proxy or network-service-order operations.
public final class SwitchEngine {
    public private(set) var policy: PriorityPolicy
    public init(networks: [String]) { policy = PriorityPolicy(networks: networks) }
    public func resetObservations() { policy.resetObservations() }
    public func tick(radio: Radio, now: () -> TimeInterval, permitted: () -> Bool) -> StatusMessage {
        guard permitted() else { return .init(.paused) }
        guard radio.powered else { policy.resetObservations(); return .init(.wifiOff) }
        guard !policy.networks.isEmpty else { return .init(.configure) }
        let original = radio.current
        if let original, !policy.networks.contains(original) {
            policy.resetObservations(); return .init(.manual, ["network": original])
        }
        if original == policy.networks.first {
            policy.observe(current: original, visible: [:])
            return .init(.preferredConnected, ["network": original!])
        }
        let visible: [String: Int]
        do { visible = try radio.scan() }
        catch { policy.resetObservations(); return .init(.scanFailed) }
        guard permitted(), radio.powered, radio.current == original else {
            policy.resetObservations(); return .init(.changed)
        }
        policy.observe(current: original, visible: visible)
        var target = policy.candidate(current: original, now: now())
        var attempted = Set<String>()
        var connectionAttempts = 0
        var credentialSetupTarget: String?
        while let ssid = target, connectionAttempts < 3 {
            guard permitted(), radio.powered else { return .init(.stopped) }
            // Respect a manual/native association that happened between attempts.
            if let actual = radio.current, actual != original { return .init(.keeping, ["network": actual]) }
            attempted.insert(ssid)
            let result = radio.connect(to: ssid, permitted: permitted)
            guard permitted() else { return .init(.paused) }
            switch result {
            case .connected:
                guard radio.current == ssid else { return .init(.changed) }
                policy.succeeded(ssid, now: now())
                return .init(.connected, ["network": ssid])
            case .cancelled: return .init(.cancelled)
            case .requiresCredentialSetup:
                // Missing or declined credential preparation is not an
                // association failure. Keep the connection and consider other
                // candidates without re-prompting the keychain automatically.
                if credentialSetupTarget == nil { credentialSetupTarget = ssid }
                target = policy.candidate(current: original, now: now(), excluding: attempted)
            case .failed:
                connectionAttempts += 1
                policy.failed(ssid, now: now())
                if let actual = radio.current {
                    return .init(.keepingRetry, ["network": actual])
                }
                // An upgrade can temporarily disassociate Wi-Fi. Restore the previously
                // working network first instead of chasing every other higher-ranked AP.
                if let original, !attempted.contains(original), connectionAttempts < 3 {
                    attempted.insert(original)
                    connectionAttempts += 1
                    guard permitted(), radio.powered else { return .init(.stopped) }
                    if radio.current != nil { return .init(.connectionRestored) }
                    let recovery = radio.connect(to: original, permitted: permitted)
                    guard permitted() else { return .init(.paused) }
                    switch recovery {
                    case .connected:
                        guard radio.current == original else { return .init(.changed) }
                        policy.succeeded(original, now: now())
                        return .init(.restored, ["network": original])
                    case .cancelled: return .init(.recoveryCancelled)
                    case .requiresCredentialSetup: return .init(.credentialSetupRequired, ["network": original])
                    case .failed: policy.failed(original, now: now())
                    }
                }
                if radio.current != nil { return .init(.connectionRestored) }
                // Fallback after a failed upgrade need not wait two disconnected polls.
                // Reuse evidence from real scans; do not manufacture stable sightings.
                target = policy.candidate(current: nil, now: now(), recovering: true,
                                          excluding: attempted)
            }
        }
        if let credentialSetupTarget {
            return .init(.credentialSetupRequired, ["network": credentialSetupTarget])
        }
        if let current = radio.current {
            if let retry = policy.earliestRetry, retry > now() {
                return .init(.cooldown, ["network": current, "minutes": String(Int(ceil((retry - now()) / 60)))])
            }
            return .init(.checking, ["network": current])
        }
        return .init(.waiting)
    }
}
