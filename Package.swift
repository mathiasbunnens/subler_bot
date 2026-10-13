// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SublerAutomation",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AutomationCore", targets: ["AutomationCore"]), .executable(name: "SublerAutomation", targets: ["SublerAutomation"])],
    targets: [
        .target(name: "AutomationCore"),
        .executableTarget(name: "SublerAutomation", dependencies: ["AutomationCore"], exclude: ["Resources"]),
        .testTarget(name: "AutomationCoreTests", dependencies: ["AutomationCore"])
    ]
)
