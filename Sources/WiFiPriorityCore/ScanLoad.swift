import Foundation

/// Limits active scans while connected to a backup. The UI still reads the
/// current SSID on skipped checks, and a changed connection scans immediately.
public struct ScanCadence {
    private var lastNetwork: String?
    private var lastScanAt: TimeInterval?

    public init() {}

    public mutating func reset() {
        lastNetwork = nil
        lastScanAt = nil
    }

    public mutating func shouldScan(current: String?, preferred: String?, now: TimeInterval) -> Bool {
        guard let current, current != preferred else {
            lastNetwork = current
            lastScanAt = nil
            return true
        }
        if lastNetwork == current, let lastScanAt, now - lastScanAt < 30 { return false }
        lastNetwork = current
        lastScanAt = now
        return true
    }
}

public enum PriorityScanScope {
    /// A connected backup only needs to discover networks above its rank.
    /// With no configured connection, every saved hidden network is relevant.
    public static func directedNames(networks: [String], hidden: Set<String>, current: String?) -> [String] {
        let limit = current.flatMap { networks.firstIndex(of: $0) } ?? networks.count
        return networks.prefix(limit).filter { hidden.contains($0) }
    }
}
