// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OmniRouteQuota",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OmniRouteQuota", targets: ["OmniRouteQuota"]),
        .library(name: "QuotaCore", targets: ["QuotaCore"])
    ],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(name: "OmniRouteQuota", dependencies: ["QuotaCore"]),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"]),
        .testTarget(name: "QuotaUITests", dependencies: ["OmniRouteQuota", "QuotaCore"])
    ]
)
