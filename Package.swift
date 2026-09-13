// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "QuickElevate",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QuickElevateApp", targets: ["QuickElevateApp"]),
        .executable(name: "QuickElevateHelper", targets: ["QuickElevateHelper"])
    ],
    targets: [
        .target(
            name: "QuickElevateShared",
            path: "Sources/QuickElevateShared"
        ),
        .executableTarget(
            name: "QuickElevateApp",
            dependencies: ["QuickElevateShared"],
            path: "Sources/QuickElevateApp",
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
