// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WiFiPriority",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WiFiPriority", targets: ["WiFiPriorityApp"])],
    targets: [
        .target(name: "WiFiPriorityCore", resources: [.process("Resources")]),
        .executableTarget(name: "WiFiPriorityApp", dependencies: ["WiFiPriorityCore"]),
        .testTarget(name: "WiFiPriorityCoreTests", dependencies: ["WiFiPriorityCore"])
    ]
)
