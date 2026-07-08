// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "InputUtils",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(
      name: "InputUtils",
      targets: ["InputUtils"]
    )
  ],
  targets: [
    .executableTarget(
      name: "InputUtils"
    )
  ]
)
