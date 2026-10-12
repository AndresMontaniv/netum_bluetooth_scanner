// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "netum_bluetooth_scanner",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "netum-bluetooth-scanner", targets: ["netum_bluetooth_scanner"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "netum_bluetooth_scanner",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
