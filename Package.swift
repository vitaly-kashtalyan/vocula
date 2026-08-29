// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Vocula",
  defaultLocalization: "en",
  platforms: [.macOS("26.0")],
  products: [
    .library(name: "VoculaKit", targets: ["VoculaKit"]),
    .library(name: "VoculaWhisper", targets: ["VoculaWhisper"]),
  ],
  targets: [
    .target(name: "VoculaKit", resources: [.process("Resources")]),
    .binaryTarget(
      name: "whisper",
      url:
        "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.2/whisper-v1.9.2-xcframework.zip",
      checksum: "af74fed13ea7f2d5ca2a39d9f58ec177713fafd7cab63aef4e27b79f3ceca80b"),
    .target(name: "VoculaWhisper", dependencies: ["VoculaKit", "whisper"]),
    .testTarget(name: "VoculaKitTests", dependencies: ["VoculaKit"]),
    .testTarget(name: "VoculaWhisperTests", dependencies: ["VoculaWhisper"]),
    .testTarget(name: "VoculaSlowTests", dependencies: ["VoculaWhisper"]),
  ]
)
