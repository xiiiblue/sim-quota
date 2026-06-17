// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SimQuotaMenu",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SimQuotaMenu", targets: ["SimQuotaMenu"])
    ],
    targets: [
        .executableTarget(
            name: "SimQuotaMenu",
            path: "Sources/SimQuotaMenu"
        )
    ]
)
