// swift-tools-version: 5.9
import PackageDescription

// Pure playback-order logic can be tested independently of the iOS SDK.
let package = Package(
    name: "LoopMP3Logic",
    products: [.library(name: "RepeatCore", targets: ["RepeatCore"])],
    targets: [
        .target(name: "RepeatCore", path: "LoopMP3",
                exclude: ["LoopMP3App.swift", "ContentView.swift", "PlayerStore.swift", "Info.plist"],
                sources: ["RepeatMode.swift"]),
        .testTarget(name: "RepeatCoreTests", dependencies: ["RepeatCore"], path: "Tests")
    ]
)
