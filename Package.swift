// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ClaudeAgentSDK",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "ClaudeAgentSDK",
            targets: ["ClaudeAgentSDK"]
        ),
        .executable(
            name: "claude-sdk-example",
            targets: ["ClaudeSDKExample"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ClaudeAgentSDK",
            dependencies: [],
            path: "Sources/ClaudeAgentSDK"
        ),
        .executableTarget(
            name: "ClaudeSDKExample",
            dependencies: ["ClaudeAgentSDK"],
            path: "Sources/ClaudeSDKExample"
        ),
        .testTarget(
            name: "ClaudeAgentSDKTests",
            dependencies: ["ClaudeAgentSDK"],
            path: "Tests/ClaudeAgentSDKTests"
        ),
        .testTarget(
            name: "ClaudeAgentSDKE2ETests",
            dependencies: ["ClaudeAgentSDK"],
            path: "Tests/ClaudeAgentSDKE2ETests"
        )
    ]
)
