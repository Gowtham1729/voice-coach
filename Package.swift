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
  targets: [
    .target(name: "VoiceCoachCore"),
    .target(
      name: "VoiceCoachSession",
      dependencies: ["VoiceCoachCore"]
    ),
    .executableTarget(
      name: "VoiceCoachApp",
      dependencies: ["VoiceCoachCore", "VoiceCoachSession"]
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
