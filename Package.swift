// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LinkEgressKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "LinkEgressKit", targets: ["LinkEgressKit"]),
        .executable(name: "LinkEgressDemo", targets: ["LinkEgressDemo"])
    ],
    targets: [
        .target(name: "LinkEgressKit"),
        .executableTarget(
            name: "LinkEgressDemo",
            dependencies: ["LinkEgressKit"]
        ),
        .testTarget(
            name: "LinkEgressKitTests",
            dependencies: ["LinkEgressKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
