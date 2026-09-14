// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "QuickElevate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "QuickElevateApp", targets: ["QuickElevateApp"]),
        .executable(name: "QuickElevateHelper", targets: ["QuickElevateHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc.git", exact: "2.15.0")
    ],
    targets: [
        .target(
            name: "QuickElevateShared",
            path: "Sources/QuickElevateShared"
        ),
        .executableTarget(
            name: "QuickElevateApp",
            dependencies: [
                "QuickElevateShared",
                .product(name: "MSAL", package: "microsoft-authentication-library-for-objc")
            ],
            path: "Sources/QuickElevateApp",
            exclude: ["Resources"],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .executableTarget(
            name: "QuickElevateHelper",
            dependencies: ["QuickElevateShared"],
            path: "Sources/QuickElevateHelper"
        )
    ]
)
