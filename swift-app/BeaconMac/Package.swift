// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Beacon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Beacon", targets: ["Beacon"])
    ],
    targets: [
        .executableTarget(
            name: "Beacon",
            path: "Sources/Beacon",
            exclude: [
                "Resources/Info.plist",
                "Resources/Beacon.entitlements"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("Network"),
                .linkedFramework("UserNotifications")
            ]
        )
    ]
)
