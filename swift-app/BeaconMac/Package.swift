// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BeaconMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BeaconMac", targets: ["Beacon"])
    ],
    targets: [
        .executableTarget(
            name: "Beacon",
            path: "Sources/Beacon",
            exclude: [
                "Resources/Info.plist",
                "Resources/Beacon.entitlements",
                "Resources/Beacon-DMG.entitlements",
                "Resources/Assets.xcassets"
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("Network"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("IOKit"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
