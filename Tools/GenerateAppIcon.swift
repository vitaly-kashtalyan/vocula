#!/usr/bin/env swift
import AppKit
import WebKit

// MARK: - What to render

enum Artwork {
  case flat
  case stepped
  case full

  var file: String {
    switch self {
    case .flat: return "vocula-icon-small.svg"
    case .stepped: return "vocula-icon-32.svg"
    case .full: return "vocula-icon.svg"
    }
  }
}

let slices: [(name: String, pixels: Int, artwork: Artwork)] = [
  ("icon_16x16", 16, .flat),
  ("icon_16x16@2x", 32, .flat),  // 16pt at 2x — still the 16pt drawing
  ("icon_32x32", 32, .stepped),
  ("icon_32x32@2x", 64, .stepped),  // 32pt at 2x — still the 32pt drawing
  ("icon_128x128", 128, .full),
  ("icon_128x128@2x", 256, .full),
  ("icon_256x256", 256, .full),
  ("icon_256x256@2x", 512, .full),
  ("icon_512x512", 512, .full),
  ("icon_512x512@2x", 1024, .full),
]

let repoRoot = FileManager.default.currentDirectoryPath
let outDir =
  CommandLine.arguments.count > 1
  ? (CommandLine.arguments[1] == "install"
    ? "App/Vocula/Assets.xcassets/AppIcon.appiconset" : CommandLine.arguments[1])
  : "\(repoRoot)/App/Vocula/Assets.xcassets/AppIcon.appiconset"

func readSVG(_ name: String) -> String {
  let path = "\(repoRoot)/Icon/\(name)"
  guard let s = try? String(contentsOfFile: path, encoding: .utf8) else {
    FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
    FileHandle.standardError.write("run this from the repository root\n".data(using: .utf8)!)
    exit(1)
  }
  return s
}
var svgCache: [String: String] = [:]
func artwork(_ a: Artwork) -> String {
  if let cached = svgCache[a.file] { return cached }
  let s = readSVG(a.file)
  svgCache[a.file] = s
  return s
}

// MARK: - Render

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

func render(svg: String, pixels: Int) -> Data? {
  let scale = NSScreen.main?.backingScaleFactor ?? 2
  let points = CGFloat(pixels) / scale
  let view = WKWebView(
    frame: NSRect(x: 0, y: 0, width: points, height: points),
    configuration: WKWebViewConfiguration())
  view.setValue(false, forKey: "drawsBackground")

  final class Waiter: NSObject, WKNavigationDelegate {
    var result: Data?
    var done = false
    let pixels: Int
    init(pixels: Int) { self.pixels = pixels }

    func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
      let cfg = WKSnapshotConfiguration()
      cfg.rect = web.bounds
      web.takeSnapshot(with: cfg) { image, _ in
        defer { self.done = true }
        guard let image else { return }
        let target = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: self.pixels, pixelsHigh: self.pixels,
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        target.size = NSSize(width: self.pixels, height: self.pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: self.pixels, height: self.pixels))
        NSGraphicsContext.restoreGraphicsState()
        self.result = target.representation(using: .png, properties: [:])
      }
    }
  }

  let waiter = Waiter(pixels: pixels)
  view.navigationDelegate = waiter
  view.loadHTMLString(
    "<style>html,body{margin:0;padding:0}svg{width:100%;height:100%}</style>"
      + svg, baseURL: nil)

  let deadline = Date().addingTimeInterval(30)
  while !waiter.done && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
  }
  return waiter.result
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var failed = false
for slice in slices {
  guard let png = render(svg: artwork(slice.artwork), pixels: slice.pixels) else {
    FileHandle.standardError.write("failed: \(slice.name)\n".data(using: .utf8)!)
    failed = true
    continue
  }
  let path = "\(outDir)/\(slice.name).png"
  try! png.write(to: URL(fileURLWithPath: path))
  print(
    "\(slice.name).png  \(slice.pixels)×\(slice.pixels)  \(png.count) bytes"
      + "  [\(slice.artwork.file)]")
}
exit(failed ? 1 : 0)
