// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Vocula",
  defaultLocalization: "en",
  platforms: [.macOS("26.0")],
  products: [
    .library(name: "VoculaKit", targets: ["VoculaKit"]),
    .library(name: "VoculaWhisper", targets: ["VoculaWhisper"]),
    .library(name: "VoculaParakeet", targets: ["VoculaParakeet"]),
  ],
  dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.3", traits: [])
  ],
  targets: [
    .target(name: "VoculaKit", resources: [.process("Resources")]),
    .binaryTarget(
      name: "whisper",
      url:
        "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
      checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"),
    .target(name: "VoculaWhisper", dependencies: ["VoculaKit", "whisper"]),
    .target(
      name: "VoculaParakeet",
      dependencies: ["VoculaKit", .product(name: "FluidAudio", package: "FluidAudio")]),
    .testTarget(name: "VoculaKitTests", dependencies: ["VoculaKit"]),
    .testTarget(name: "VoculaWhisperTests", dependencies: ["VoculaWhisper"]),
    .testTarget(name: "VoculaSlowTests", dependencies: ["VoculaWhisper", "VoculaParakeet"]),
  ]
)
