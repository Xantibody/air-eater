// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "air-eater",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "air-eater", targets: ["AirEater"])
  ],
  targets: [
    .target(name: "AirEaterCore"),
    .executableTarget(name: "AirEater", dependencies: ["AirEaterCore"]),
    // 実機で Desktop を切り替えて確かめる E2E。just e2e で回す
    .executableTarget(name: "AirEaterE2E", dependencies: ["AirEaterCore"]),
    .testTarget(name: "AirEaterCoreTests", dependencies: ["AirEaterCore"]),
  ]
)
