// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SplitCore",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "SplitCore", targets: ["SplitCore"])
  ],
  targets: [
    .target(
      name: "SplitCore",
      path: "Split/Models"
    ),
    .testTarget(
      name: "SplitCoreTests",
      dependencies: ["SplitCore"],
      path: "SplitTests"
    ),
  ]
)
