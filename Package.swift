// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Swipepad", platforms: [.macOS(.v13)],
  products: [.executable(name: "Swipepad", targets: ["Swipepad"])],
  targets: [
    .target(name: "SwipepadCore"),
    .target(
      name: "TrackpadBridge", cSettings: [.unsafeFlags(["-fobjc-arc"])],
      linkerSettings: [
        .unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "MultitouchSupport"])
      ]),
    .executableTarget(name: "Swipepad", dependencies: ["SwipepadCore", "TrackpadBridge"]),
    .executableTarget(name: "SwipepadChecks", dependencies: ["SwipepadCore"]),
  ])
