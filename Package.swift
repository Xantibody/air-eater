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
    .testTarget(name: "AirEaterCoreTests", dependencies: ["AirEaterCore"]),
  ]
)
