// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "VoiceCoach",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoiceCoachCore", targets: ["VoiceCoachCore"]),
        .executable(name: "VoiceCoachApp", targets: ["VoiceCoachApp"]),
        .executable(name: "VoiceCoachSelfTest", targets: ["VoiceCoachSelfTest"])
    ],
    targets: [
        .target(name: "VoiceCoachCore"),
        .executableTarget(
            name: "VoiceCoachApp",
            dependencies: ["VoiceCoachCore"]
        ),
        .executableTarget(
            name: "VoiceCoachSelfTest",
            dependencies: ["VoiceCoachCore"]
        )
    ]
)
