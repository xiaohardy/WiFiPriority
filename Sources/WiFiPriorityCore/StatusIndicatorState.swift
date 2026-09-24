/// Maps the saved priority order to the twelve fixed clock positions in the menu bar.
public struct StatusIndicatorState: Equatable {
    public static let maximumStars = 12

    public let starCount: Int
    public let activeIndex: Int?

    public init(networks: [String], currentSSID: String?, paused: Bool) {
        starCount = min(networks.count, Self.maximumStars)
        if !paused, let currentSSID,
           let index = networks.firstIndex(of: currentSSID), index < starCount {
            activeIndex = index
        } else {
            activeIndex = nil
        }
    }
}
