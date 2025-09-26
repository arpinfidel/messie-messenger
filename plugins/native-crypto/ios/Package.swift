// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NativeCrypto",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "NativeCrypto",
            targets: ["NativeCrypto"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-package.git", from: "6.2.0")
    ],
    targets: [
        .target(
            name: "NativeCrypto",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-package")
            ],
            path: "Sources/NativeCrypto"
        ),
        .testTarget(
            name: "NativeCryptoTests",
            dependencies: ["NativeCrypto"],
            path: "Tests/NativeCrypto"
        )
    ]
)
