// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "VoiceCoach",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "VoiceCoachCore", targets: ["VoiceCoachCore"]),
    .executable(name: "VoiceCoachApp", targets: ["VoiceCoachApp"]),
    .executable(name: "VoiceCoachSelfTest", targets: ["VoiceCoachSelfTest"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
  ],
  targets: [
    .target(name: "VoiceCoachCore"),
    .target(
      name: "VoiceCoachSession",
      dependencies: ["VoiceCoachCore"]
    ),
    .executableTarget(
      name: "VoiceCoachApp",
      dependencies: [
        "VoiceCoachCore", "VoiceCoachSession",
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
      ]
    ),
    .executableTarget(
      name: "VoiceCoachSelfTest",
      dependencies: ["VoiceCoachCore"]
    ),
    .testTarget(
      name: "VoiceCoachCoreTests",
      dependencies: ["VoiceCoachCore"]
    ),
    .testTarget(
      name: "VoiceCoachSessionTests",
      dependencies: ["VoiceCoachCore", "VoiceCoachSession"]
    ),
  ]
)
