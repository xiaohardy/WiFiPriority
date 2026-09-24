import Foundation

public enum ConnectionProbeOutcome: Equatable {
    case alreadyConnected
    case connected
    case connectedRestored
    case connectedRestoreFailed
    case failedPreviousAvailable
    case failedDisconnected
    case failedRestoreFailed
    case cancelled
    case changed
    case wifiOff
}

/// Attempts a named Wi-Fi directly, then restores the prior association when one existed.
/// The caller must pause automatic switching while this runs.
public enum ConnectionProbe {
    public static func run(radio: Radio, target: String, permitted: () -> Bool) -> ConnectionProbeOutcome {
        guard permitted() else { return .cancelled }
        guard radio.powered else { return .wifiOff }
        let previous = radio.current
        if previous == target { return .alreadyConnected }

        let attempt = radio.connect(to: target, permitted: permitted)
        guard permitted(), attempt != .cancelled else { return .cancelled }
        let afterAttempt = radio.current
        if let afterAttempt, afterAttempt != target && afterAttempt != previous { return .changed }
        let connected = attempt == .connected && afterAttempt == target

        guard let previous else { return connected ? .connected : .failedDisconnected }
        if !connected && afterAttempt == previous { return .failedPreviousAvailable }

        _ = radio.connect(to: previous, permitted: permitted)
        guard permitted() else { return .cancelled }
        if let current = radio.current, current != previous && current != target { return .changed }
        if radio.current == previous {
            return connected ? .connectedRestored : .failedPreviousAvailable
        }
        return connected ? .connectedRestoreFailed : .failedRestoreFailed
    }
}
